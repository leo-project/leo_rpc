%%====================================================================
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
%%====================================================================
-module(leo_rpc_tests).

-author('Yosuke Hara').

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%%--------------------------------------------------------------------
%% TEST FUNCTIONS
%%--------------------------------------------------------------------
-ifdef(EUNIT).

all_test_() ->
    {timeout, 300, {foreach, fun setup/0, fun teardown/1,
                    [{with, [T]} || T <- [
                                          fun basic_/1,
                                          fun tuple_/1,
                                          fun send_large_/1,
                                          fun receive_large_/1,
                                          fun record_/1,
                                          fun others_/1
                                         ]]}}.

setup() ->
    [] = os:cmd("epmd -daemon"),
    Node = erlang:node(),
    net_kernel:start([Node, longnames]),

    ok = application:start(leo_rpc),
    Node.

teardown(_) ->
    ok = application:stop(leo_rpc),
    net_kernel:stop(),
    ok.

basic_(Node) ->
    {timeout, 15, begin
                      %% "leo_rpc:call/4"
                      Mod1 = 'leo_misc',
                      Fun1 = 'get_value',
                      Param1 = [{'a',1},{'b',2},{'c',3}],
                      Param2 = <<"123">>,
                  
                      ?assertEqual(1,      leo_rpc:call(Node, Mod1, Fun1, ['a', Param1, Param2])),
                      ?assertEqual(2,      leo_rpc:call(Node, Mod1, Fun1, ['b', Param1, Param2])),
                      ?assertEqual(Param2, leo_rpc:call(Node, Mod1, Fun1, ['d', Param1, Param2])),
                      ?assertEqual(true, is_integer(leo_rpc:call(Node, 'leo_date', 'clock', []))),
                  
                      %% "leo_rpc:async_call/4"
                      RPCKey1 = leo_rpc:async_call(Node, Mod1, Fun1, ['a', Param1, Param2]),
                      ?assertEqual({value, 1}, leo_rpc:nb_yield(RPCKey1)),
                  
                      RPCKey2 = leo_rpc:async_call(Node, Mod1, Fun1, ['b', Param1, Param2]),
                      ?assertEqual({value, 2}, leo_rpc:nb_yield(RPCKey2)),
                  
                      RPCKey3 = leo_rpc:async_call(Node, Mod1, Fun1, ['d', Param1, Param2]),
                      ?assertEqual({value, Param2}, leo_rpc:nb_yield(RPCKey3)),
                  
                      RPCKey4 = leo_rpc:async_call(Node, 'leo_date', 'clock', []),
                      ?assertMatch({value, _}, leo_rpc:nb_yield(RPCKey4)),
                  
                      %% "leo_rpc:multicall/4"
                      Nodes = [Node, Node],
                      ?assertEqual({[1,1],[]}, leo_rpc:multicall(Nodes, Mod1, Fun1, ['a', Param1, Param2])),
                      ?assertEqual({[2,2],[]}, leo_rpc:multicall(Nodes, Mod1, Fun1, ['b', Param1, Param2])),
                      ?assertEqual({[Param2,Param2],[]}, leo_rpc:multicall(Nodes, Mod1, Fun1, ['d', Param1, Param2])),
                      ?assertMatch({[_,_],[]}, leo_rpc:multicall(Nodes, 'leo_date', 'clock', [])),
                  
                      %% "leo_rpc:cast/4"
                      ?assertEqual(true, leo_rpc:cast(Node, Mod1, Fun1, ['a', Param1, Param2])),
                      ok
                  end}.

tuple_(Node) ->
    {timeout, 15, begin
                      %% a value type is tuple
                      Params   = [{ok, 1, 2}, 3, <<"name:LEO">>, <<"type:FS">>],
                      Expected = list_to_tuple(Params),
                      ?assertEqual(Expected, leo_rpc:call(Node, 'erlang', 'list_to_tuple', [Params])),
                      ?assertMatch({_,_,_},  leo_rpc:call(Node, 'erlang', 'now', [])),
                      ok
                  end}.

send_large_(Node) ->
    {timeout, 15, begin
                      %% send a large-object
                      lists:foreach(fun(Size) ->
                                            Bin = crypto:rand_bytes(Size),
                                            RPCKey5 = leo_rpc:async_call(Node, 'erlang', 'byte_size', [Bin]),
                                            ?assertEqual({value, Size}, leo_rpc:nb_yield(RPCKey5))
                                    end, [1  * 1024*1024,
                                          2  * 1024*1024,
                                          3  * 1024*1024,
                                          4  * 1024*1024,
                                          5  * 1024*1024,
                                          6  * 1024*1024,
                                          7  * 1024*1024,
                                          8  * 1024*1024,
                                          9  * 1024*1024,
                                          10 * 1024*1024])
                  end}.

receive_large_(Node) ->
    {timeout, 15, begin
                      %% receive a large-object
                      lists:foreach(fun(Size) ->
                                            Bin = leo_rpc:call(Node, crypto, rand_bytes, [Size]),
                                            ?assertEqual(Size, byte_size(Bin))
                                    end, [1  * 1024*1024,
                                          2  * 1024*1024,
                                          3  * 1024*1024,
                                          4  * 1024*1024,
                                          5  * 1024*1024,
                                          6  * 1024*1024,
                                          7  * 1024*1024,
                                          8  * 1024*1024,
                                          9  * 1024*1024,
                                          10 * 1024*1024])
                  end}.

-record(test, {
          str :: string(),
          int :: integer(),
          bool :: boolean(),
          bin  :: binary(),
          func :: fun()
         }).

record_(Node) ->
    {timeout, 15, begin
                      F = fun(X) -> X * X end,
                      Bin = crypto:rand_bytes(10 * 1024*1024),
                      T = #test{
                             str = "test",
                             int = 1,
                             bool = true,
                             bin = Bin,
                             func = F
                            },
                      Serialized = term_to_binary(T),
                      ?assertEqual(T, leo_rpc:call(Node, 'erlang', 'binary_to_term', [Serialized]))
                  end}.

others_(Node) ->
    {timeout, 15, begin
                      %% Others
                      ?assertMatch({_,_,_},  leo_rpc:call(Node, 'erlang', 'now', [])),
                      ?assertEqual(pong, leo_rpc:ping(Node)),
                      ?assertEqual(erlang:node(), leo_rpc:node()),
                      ok
                  end}.



-endif.
