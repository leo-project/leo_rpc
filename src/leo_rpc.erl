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
%%======================================================================
-module(leo_rpc).

-author('Yosuke Hara').

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([async_call/4,
         call/4, call/5, call/6,
         multicall/4, multicall/5,
         nb_yield/1, nb_yield/2,
         ping/1, status/0, node/0, nodes/0
        ]).

-export([loop_1/4, loop_2/4]).

-define(DEF_TIMEOUT, 5000).


%%--------------------------------------------------------------------
%%  APIs
%%--------------------------------------------------------------------
%% @doc Implements call streams with promises, a type of RPC which does not suspend
%%      the caller until the result is finished.
%%      Instead, a key is returned which can be used at a later stage to collect the value.
%%      The key can be viewed as a promise to deliver the answer.
-spec(async_call(atom(), atom(), atom(), list(any())) ->
             pid()).
async_call(Node, Mod, Method, Args) ->
    erlang:spawn(?MODULE, loop_1, [Node, Mod, Method, Args]).


%% @doc Evaluates apply(Module, Function, Args) on the node Node
%%      and returns the corresponding value Res, or {badrpc, Reason} if the call fails.
-spec(call(atom(), atom(), atom(), list(any())) ->
             any() | {badrpc, any()}).
call(Node, Mod, Method, Args) ->
    call(Node, Mod, Method, Args, ?DEF_TIMEOUT).

-spec(call(atom(), atom(), atom(), list(any()), pos_integer()) ->
             any() | {badrpc, any()}).
call(Node, Mod, Method, Args, Timeout) ->
    ParamsBin = leo_rpc_protocol:param_to_binary(Mod, Method, Args),

    case exec(Node, ParamsBin, Timeout) of
        {ok, Val} ->
            case leo_rpc_protocol:binary_to_result(Val) of
                {error, Cause} ->
                    {badrpc, Cause};
                Res ->
                    Res
            end;
        {error, Cause} ->
            {badrpc, Cause}
    end.

-spec(call(pid(), atom(), atom(), atom(), list(any()), pos_integer()) ->
             any() | {badrpc, any()}).
call(From, Node, Mod, Method, Args, Timeout) ->
    Ret = call(Node, Mod, Method, Args, Timeout),
    erlang:send(From, {Node, Ret}).


%% @doc A multicall is an RPC which is sent concurrently from one client to multiple servers.
%%      This is useful for collecting some information from a set of nodes.
-spec(multicall(atom(), atom(), atom(), list(any())) ->
             any() | {badrpc, any()}).
multicall(Nodes, Mod, Method, Args) ->
    multicall(Nodes, Mod, Method, Args, ?DEF_TIMEOUT).

-spec(multicall(atom(), atom(), atom(), list(any()), integer()) ->
             any() | {badrpc, any()}).
multicall(Nodes, Mod, Method, Args, Timeout) ->
    Self = self(),
    Pid  = erlang:spawn(?MODULE, loop_2,
                        [Self, erlang:length(Nodes), {[],[]}, Timeout]),
    ok = multicall_1(Nodes, Pid, Mod, Method, Args, Timeout),
    receive
        Ret ->
            Ret
    after Timeout ->
            timeout
    end.

multicall_1([],_Pid,_Mod,_Method,_Args,_Timeout) ->
    ok;
multicall_1([Node|Rest], Pid, Mod, Method, Args, Timeout) ->
    spawn(?MODULE, call, [Pid, Node, Mod, Method, Args, Timeout]),
    multicall_1(Rest, Pid, Mod, Method, Args, Timeout).


%% @doc This is able to call non-blocking.
%%      It returns the tuple {value, Val} when the computation has finished,
%%      or timeout when Timeout milliseconds has elapsed.
-spec(nb_yield(pid()) ->
             {value, any()} | timeout).
nb_yield(Key) ->
    nb_yield(Key, ?DEF_TIMEOUT).

-spec(nb_yield(pid(), pos_integer()) ->
             {value, any()} | timeout | {badrpc, any()}).
nb_yield(Key, Timeout) when is_pid(Key) ->
    case erlang:is_process_alive(Key) of
        false ->
            {badrpc, invalid_key};
        true ->
            erlang:send(Key, {get, self()}),
            receive
                {badrpc, timeout} ->
                    timeout;
                {badrpc, Cause} ->
                    {badrpc, Cause};
                Ret ->
                    {value, Ret}
            after Timeout ->
                    timeout
            end
    end;
nb_yield(_,_) ->
    {badrpc, invalid_key}.


%% @doc Tries to set up a connection to Node.
%%      Returns pang if it fails, or pong if it is successful.
-spec(ping(atom()) ->
             pong|pang).
ping(Node) ->
    case leo_rpc_client_manager:inspect(Node) of
        active ->
            pong;
        _ ->
            pang
    end.


%% @doc Retrieve status of active connections
-spec(status() ->
             {ok, list(#rpc_info{})} | {error, any()}).
status() ->
    leo_rpc_client_manager:status().


%% @doc Returns the name of the local node. If the node is not alive, nonode@nohost is returned instead.
-spec(node() ->
             'nonode@nohost' | atom()).
node() ->
    case application:get_env(?MODULE, 'node') of
        undefined ->
            'nonode@nohost';
        {ok, Node} ->
            Node
    end.


%% @doc Returns a list of all connected nodes in the system, excluding the local node.
nodes() ->
    {ok, Nodes} = leo_rpc_client_manager:connected_nodes(),
    Nodes.


%%--------------------------------------------------------------------
%%  Internal Function
%%--------------------------------------------------------------------
%% @doc Execute rpc
%% @private
-spec(exec(atom(), binary(), pos_integer()) ->
             {ok, any()} | {error, any()}).
exec(Node, ParamsBin, Timeout) when is_atom(Node) ->
    Node1 = atom_to_list(Node),
    exec(Node1, ParamsBin, Timeout);

exec(Node, ParamsBin, Timeout) ->
    %% find the node from worker-procs
    {Node1, IP1, Port1} = case string:tokens(Node, "@:") of
                              [_Node, IP, Port] ->
                                  {list_to_atom(_Node), IP, Port};
                              [_Node, IP] ->
                                  {list_to_atom(_Node), IP, ?DEF_LISTEN_PORT};
                              [_Node] ->
                                  {list_to_atom(_Node), ?DEF_LISTEN_IP, ?DEF_LISTEN_PORT};
                              _ ->
                                  {[], 0}
                          end,

    case Node1 of
        [] ->
            {error, invalid_node};
        _ ->
            PodName = leo_rpc_client_utils:get_client_worker_id(Node1, Port1),
            case whereis(PodName) of
                undefined ->
                    leo_rpc_client_sup:start_child(Node1, IP1, Port1);
                _ ->
                    void
            end,

            %% execute a requested function with a remote-node
            exec_1(PodName, ParamsBin, Timeout)
    end.

exec_1(PodName, ParamsBin, Timeout) ->
    case leo_pod:checkout(PodName) of
        {ok, ServerRef} ->
            Ret2 = case catch gen_server:call(
                                ServerRef, {request, ParamsBin}, Timeout) of
                       {'EXIT', Cause} ->
                           {error, Cause};
                       Ret1 ->
                           Ret1
                   end,
            leo_pod:checkin_async(PodName, ServerRef),
            Ret2;
        _ ->
            {error, []}
    end.


%% @doc Receiver-1
%% @private
loop_1(Node, Mod, Method, Args) ->
    loop_1(Node, Mod, Method, Args, ?DEF_TIMEOUT).
loop_1(Node, Mod, Method, Args, Timeout) ->
    Ret = call(Node, Mod, Method, Args),
    receive
        {get, Client} ->
            erlang:send(Client, Ret)
    after
        Timeout ->
            timeout
    end.


%% @doc Receiver-2
%% @private
loop_2(From, 0, Ret, _Timeout) ->
    erlang:send(From, Ret);
loop_2(From, NumOfNodes, {ResL, BadNodes}, Timeout) ->
    receive
        {Node, {badrpc,_Cause}} ->
            loop_2(From, NumOfNodes - 1, {ResL, [Node|BadNodes]}, Timeout);
        {Node, timeout} ->
            loop_2(From, NumOfNodes - 1, {ResL, [Node|BadNodes]}, Timeout);
        {_Node, Ret} ->
            loop_2(From, NumOfNodes - 1, {[Ret|ResL], BadNodes}, Timeout)
    after
        Timeout ->
            erlang:send(From, timeout)
    end.
