%%======================================================================
%%
%% Leo RPC
%%
%% Copyright (c) 2012-2014 Rakuten, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% ---------------------------------------------------------------------
%% TCP Server  - Acceptor.
%%======================================================================
-module(leo_rpc_server_listener).

-author('Yosuke Hara').

%% External API
-export([start_link/5]).

%% Callbacks
-export([init/5, accept/5]).

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").


%%-----------------------------------------------------------------------
%% External API
%%-----------------------------------------------------------------------
-spec(start_link({atom(), atom()}, pid(), atom(), atom(), #tcp_server_params{}) ->
             {ok, pid()}).
start_link({Locale, Name}, Socket, State, Module, Options) ->
    {ok, Pid} = proc_lib:start_link(
                  ?MODULE, init,
                  [self(), Socket, State, Module, Options]),

    case Locale of
        local -> register(Name, Pid);
        _ -> global:register_name(Name, Pid)
    end,
    {ok, Pid}.

%% ---------------------------------------------------------------------
%% Callbacks
%% ---------------------------------------------------------------------
init(Parent, Socket, State, Module, Options) ->
    proc_lib:init_ack(Parent, {ok, self()}),

    ListenerOptions = Options#tcp_server_params.listen,
    Active = proplists:get_value(active, ListenerOptions),
    accept(Socket, State, Module, Active, Options).


accept(ListenSocket, State, Module, Active,
       #tcp_server_params{accept_timeout = Timeout,
                          accept_error_sleep_time = SleepTime} = Options) ->
    case gen_tcp:accept(ListenSocket, Timeout) of
        {ok, Socket} ->
            case recv(Active, Socket, State, Module, Options) of
                {error, _Reason} ->
                    gen_tcp:close(Socket);
                _ ->
                    void
            end;
        {error, _Reason} ->
            timer:sleep(SleepTime)
    end,
    accept(ListenSocket, State, Module, Active, Options).


recv(false = Active, Socket, State, Module, Options) ->
    #tcp_server_params{recv_length = Length} = Options,
    case catch gen_tcp:recv(Socket, Length) of
        {ok, Data} ->
            call(Active, Socket, Data, State, Module, Options);
        {'EXIT', Reason} ->
            {error, Reason};
        {error, closed} ->
            {error, connection_closed};
        {error, Reason} ->
            {error, Reason}
    end;

recv(true = Active, _DummySocket, State, Module, Options) ->
    receive
        {tcp, Socket, Data} ->
            call(Active, Socket, Data, State, Module, Options);
        {tcp_closed, _Socket} ->
            {error, connection_closed};
        {error, Reason} ->
            {error, Reason}
    after Options#tcp_server_params.recv_timeout ->
            {error, timeout}
    end.

call(Active, Socket, Data, State, Module, Options) ->
    case Module:handle_call(Socket, Data, State) of
        {reply, DataToSend, NewState} ->
            gen_tcp:send(Socket, DataToSend),
            recv(Active, Socket, NewState, Module, Options);
        {noreply, NewState} ->
            recv(Active, Socket, NewState, Module, Options);
        {close, State} ->
            {error, connection_closed};
        {close, DataToSend, State} ->
            gen_tcp:send(Socket, DataToSend);
        Other ->
            Other
    end.

