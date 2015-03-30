%%======================================================================
%%
%% Leo-RPC
%%
%% Copyright (c) 2013-2015 Rakuten, Inc.
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
%%======================================================================
-module(basho_bench_driver_leo_rpc).

-export([new/1,
         run/4]).

-include_lib("eunit/include/eunit.hrl").

-record(state, {
          remote_node :: atom()
         }).

new(Id) ->
    case Id of
        1 ->
            application:start(leo_rpc);
        _ ->
            void
    end,
    RemoteNodeIP    = basho_bench_config:get('remote_node_ip', "127.0.0.1"),
    RemoteNodePort  = basho_bench_config:get('remote_node_port', 13076),
    RemoteNodeAlias = list_to_atom(lists:append(["remote_1@",
                                                 RemoteNodeIP,
                                                 ":",
                                                 integer_to_list(RemoteNodePort) ])),
    Ret = leo_rpc:call(RemoteNodeAlias, 'erlang', 'date', []),
    ?debugVal({RemoteNodeAlias, Ret}),
    {ok, #state{remote_node = RemoteNodeAlias}}.


run(leo_rpc_call,_KeyGen, ValueGen, #state{remote_node = RemoteNode} = State) ->
    case leo_rpc:call(RemoteNode, 'erlang', 'byte_size', [ValueGen()]) of
        {error, Reason} ->
            {error, Reason, State};
        _Res when is_integer(_Res) ->
            {ok, State};
        _Res ->
            ?debugVal(_Res),
            {error, 'invalid_value', State}
    end;

run(leo_rpc_async_call,_KeyGen, ValueGen, #state{remote_node = RemoteNode} = State) ->
    RPCKey = leo_rpc:async_call(RemoteNode, 'erlang', 'byte_size', [ValueGen()]),
    case leo_rpc:nb_yield(RPCKey, 5000) of
        {value, {error, Reason}} ->
            {error, Reason, State};
        {value, _Ret} ->
            {ok, State}
    end.
