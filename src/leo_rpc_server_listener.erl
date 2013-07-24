%%======================================================================
%%
%% Leo RPC
%%
%% Copyright (c) 2012-2013 Rakuten, Inc.
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
start_link({Locale, Name}, Socket, State, Module, Option) ->
    {ok, Pid} = proc_lib:start_link(
                  ?MODULE, init,
                  [self(), Socket, State, Module, Option]),

    case Locale of
        local -> register(Name, Pid);
        _ -> global:register_name(Name, Pid)
    end,
    {ok, Pid}.

%% ---------------------------------------------------------------------
%% Callbacks
%% ---------------------------------------------------------------------
init(Parent, Socket, State, Module, Option) ->
    proc_lib:init_ack(Parent, {ok, self()}),

    ListenerOption = Option#tcp_server_params.listen,
    Active = proplists:get_value(active, ListenerOption),
    accept(Socket, State, Module, Active, Option).


accept(ListenSocket, State, Module, Active,
       #tcp_server_params{accept_timeout = Timeout,
                          accept_error_sleep_time = SleepTime} = Option) ->
    case gen_tcp:accept(ListenSocket, Timeout) of
        {ok, Socket} ->
            recv(Active, Socket, State, Module, Option);
        {error,_Reason} ->
            timer:sleep(SleepTime)
    end,
    accept(ListenSocket, State, Module, Active, Option).


recv(false = Active, Socket, State, Module, Option) ->
    #tcp_server_params{recv_length = Length,
                       recv_timeout = Timeout} = Option,

    case catch gen_tcp:recv(Socket, Length, Timeout) of
        {ok, Data} ->
            call(Active, Socket, Data, State, Module, Option);
        {'EXIT', Reason} ->
            {error, Reason};
        {error, closed} ->
            {error, connection_closed};
        {error, Reason} ->
            {error, Reason}
    end;

recv(true = Active, _DummySocket, State, Module, Option) ->
    receive
        {tcp, Socket, Data} ->
            call(Active, Socket, Data, State, Module, Option);
        {tcp_closed, _Socket} ->
            tcp_closed;
        {error, Reason} ->
            {error, Reason}
    after Option#tcp_server_params.recv_timeout ->
            {error, timeout}
    end.

call(Active, Socket, Data, State, Module, Option) ->
    case Module:handle_call(Socket, Data, State) of
        {reply, DataToSend, NewState} ->
            gen_tcp:send(Socket, DataToSend),
            recv(Active, Socket, NewState, Module, Option);
        {noreply, NewState} ->
            recv(Active, Socket, NewState, Module, Option);
        {close, State} ->
            {error, connection_closed};
        {close, DataToSend, State} ->
            gen_tcp:send(Socket, DataToSend);
        Other ->
            Other
    end.

