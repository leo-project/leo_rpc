%%====================================================================
%%
%% Leo RPC
%%
%% Copyright (c) 2012-2013
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
    {foreach, fun setup/0, fun teardown/1,
     [{with, [T]} || T <- [fun suite_/1
                          ]]}.

setup() ->
    [] = os:cmd("epmd -daemon"),
    Node = 'node_0@127.0.0.1',
    net_kernel:start([Node, longnames]),

    ok = application:start(leo_rpc),
    Node.

teardown(_) ->
    ok = application:stop(leo_rpc),
    net_kernel:stop(),
    ok.

suite_(Node) ->
    %% "leo_rpc:call/4"
    Mod1 = 'leo_misc',
    Fun1 = 'get_value',
    Param1 = [{'a',1},{'b',2},{'c',3}],
    Param2 = <<"123">>,

    ?assertEqual(1,      leo_rpc:call(Node, Mod1, Fun1, ['a', Param1, Param2 ])),
    ?assertEqual(2,      leo_rpc:call(Node, Mod1, Fun1, ['b', Param1, Param2 ])),
    ?assertEqual(Param2, leo_rpc:call(Node, Mod1, Fun1, ['d', Param1, Param2 ])),
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
    %% ?assertEqual({badrpc,invalid_key}, leo_rpc:nb_yield(RPCKey4)),

    %% "leo_rpc:multicall/4"
    Nodes = [Node, Node],
    ?assertEqual({[1,1],[]}, leo_rpc:multicall(Nodes, Mod1, Fun1, ['a', Param1, Param2])),
    ?assertEqual({[2,2],[]}, leo_rpc:multicall(Nodes, Mod1, Fun1, ['b', Param1, Param2])),
    ?assertEqual({[Param2,Param2],[]}, leo_rpc:multicall(Nodes, Mod1, Fun1, ['d', Param1, Param2])),
    ?assertMatch({[_,_],[]}, leo_rpc:multicall(Nodes, 'leo_date', 'clock', [])),

    %% send large-object
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
                        10 * 1024*1024]),

    %% Others
    ?assertEqual(pong, leo_rpc:ping(Node)),
    timer:sleep(1000),
    ?assertEqual('node_0@127.0.0.1', leo_rpc:node()),
    ok.


-endif.
