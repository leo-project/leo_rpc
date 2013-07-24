%%======================================================================
%%
%% Leo-RPC
%%
%% Copyright (c) 2013 Rakuten, Inc.
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

-define(REMOTE_NODE, 'node_0@127.0.0.1').

new(_Id) ->
    catch application:start(leo_rpc),
    Ret1 = net_adm:ping(?REMOTE_NODE),
    Ret2 = leo_rpc:call(?REMOTE_NODE, 'erlang', 'date', []),

    ?debugVal({Ret1, Ret2}),
    {ok, null}.


run(rpc_call,_KeyGen, ValueGen, State) ->
    case rpc:call(?REMOTE_NODE, 'erlang', 'byte_size', [ValueGen()]) of
        {error, Reason} ->
            {error, Reason, State};
        _Res ->
            {ok, State}
    end;

run(leo_rpc_call,_KeyGen, ValueGen, State) ->
    case leo_rpc:call(?REMOTE_NODE, 'erlang', 'byte_size', [ValueGen()]) of
        {error, Reason} ->
            {error, Reason, State};
        _Res ->
            {ok, State}
    end;

run(rpc_async_call,_KeyGen, ValueGen, State) ->
    RPCKey = rpc:async_call(?REMOTE_NODE, 'erlang', 'byte_size', [ValueGen()]),
    case rpc:nb_yield(RPCKey, 5000) of
        {value, {error, Reason}} ->
            {error, Reason, State};
        {value, _Ret} ->
            {ok, State}
    end;

run(leo_rpc_async_call,_KeyGen, ValueGen, State) ->
    RPCKey = leo_rpc:async_call(?REMOTE_NODE, 'erlang', 'byte_size', [ValueGen()]),
    case leo_rpc:nb_yield(RPCKey, 5000) of
        {value, {error, Reason}} ->
            {error, Reason, State};
        {value, _Ret} ->
            {ok, State}
    end.

