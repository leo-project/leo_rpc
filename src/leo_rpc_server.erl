%%======================================================================
%%
%% Leo RPC
%%
%% Copyright (c) 2012-2015 Rakuten, Inc.
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
%% @doc leo_rpc_server is a rpc-server
%% @reference https://github.com/leo-project/leo_rpc/blob/master/src/leo_rpc_server.erl
%% @end
%%======================================================================
-module(leo_rpc_server).

-author('Yosuke Hara').

-export([start_link/3, stop/0]).

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").


%% @doc Start tcp-listener of the rpc-server
-spec(start_link(Module, Args, Option) ->
             ok | {error, any()} when Module::module(),
                                      Args::[any()],
                                      Option::#tcp_server_params{}).
start_link(Module, Args, #tcp_server_params{port = Port,
                                            listen = ListenerOption} = Option) ->
    case Module:init(Args) of
        {ok, State}  ->
            case gen_tcp:listen(Port, ListenerOption) of
                {ok, Socket} ->
                    add_listener(Socket, State, Module, Option);
                {error, Reason} ->
                    {error, Reason}
            end;
        {stop, Reason} ->
            {error, Reason};
        _ ->
            {error, []}
    end.


%% @doc Stop tcp-listener(s)
-spec(stop() ->
             ok).
stop() ->
    ok.


%% ---------------------------------------------------------------------
%% Internal Functions
%% ---------------------------------------------------------------------
%% @doc Add a tcp-listener's process into sup
%% @private
add_listener(Socket, State, Module, Option) ->
    NumOfListeners = Option#tcp_server_params.num_of_listeners,
    add_listener(NumOfListeners, Socket, State, Module, Option).

add_listener(0,_,_,_,_) ->
    ok;
add_listener(Id, Socket, State, Module, Option) ->
    AcceptorName = list_to_atom(
                     lists:append([Option#tcp_server_params.prefix_of_name,
                                   integer_to_list(Id)])),
    ChildSpec = {AcceptorName,
                 {leo_rpc_server_listener,
                  start_link, [{local, AcceptorName},
                               Socket,
                               State,
                               Module,
                               Option]},
                 permanent,
                 Option#tcp_server_params.shutdown,
                 worker,
                 [leo_rpc_server_listener]},
    {ok, _Pid} = supervisor:start_child(leo_rpc_sup, ChildSpec),
    add_listener(Id - 1, Socket, State, Module, Option).
