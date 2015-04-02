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
%% ---------------------------------------------------------------------
%% Leo RPC
%%
%% @doc leo_rpc is an original RPC library
%%      whose interface is similar to Erlang's buildin RPC.
%% @reference https://github.com/leo-project/leo_rpc/blob/develop/master/leo_rpc.erl
%% @end
%%======================================================================
-module(leo_rpc).

-author('Yosuke Hara').

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start/0,
         async_call/4,
         call/4, call/5, call/6,
         multicall/4, multicall/5,
         nb_yield/1, nb_yield/2,
         cast/4,
         ping/1, status/0, node/0, nodes/0, port/0
        ]).

-export([loop_1/4, loop_2/4]).

-define(DEF_TIMEOUT, 5000).


%%--------------------------------------------------------------------
%%  APIs
%%--------------------------------------------------------------------
%% @doc Launch leo-rpc
-spec(start() ->
             ok | {error, any()}).
start() ->
    application:start(?MODULE).


%% @doc Implements call streams with promises, a type of RPC which does not suspend
%%      the caller until the result is finished.
%%      Instead, a key is returned which can be used at a later stage to collect the value.
%%      The key can be viewed as a promise to deliver the answer.
-spec(async_call(Node, Mod, Method, Args) ->
             pid() when Node   :: atom(),
                        Mod    :: module(),
                        Method :: atom(),
                        Args   :: [any()]).
async_call(Node, Mod, Method, Args) ->
    erlang:spawn(?MODULE, loop_1, [Node, Mod, Method, Args]).


%% @doc Evaluates apply(Module, Function, Args) on the node Node
%%      and returns the corresponding value Res, or {badrpc, Reason} if the call fails.
-spec(call(Node, Mod, Method, Args) ->
             Ret |
             {badrpc, any()} when Node :: atom(),
                                  Mod :: module(),
                                  Method :: atom(),
                                  Args :: [any()],
                                  Ret :: any()).
call(Node, Mod, Method, Args) ->
    call(Node, Mod, Method, Args, ?DEF_TIMEOUT).


%% @doc Evaluates apply(Module, Function, Args) on the node Node
%%      and returns the corresponding value Res, or {badrpc, Reason} if the call fails.
-spec(call(Node, Mod, Method, Args, Timeout) ->
             Ret |
             {badrpc, any()} when Node :: atom(),
                                  Mod  :: module(),
                                  Method  :: atom(),
                                  Args    :: [any()],
                                  Timeout :: pos_integer(),
                                  Ret :: any()).
call(Node, Mod, Method, Args, Timeout) ->
    ParamsBin = leo_rpc_protocol:param_to_binary(Mod, Method, Args),

    case exec(Node, ParamsBin, Timeout) of
        {ok, Val} ->
            Val;
        {error, Cause} ->
            {badrpc, Cause}
    end.


%% @doc Evaluates apply(Module, Function, Args) on the node Node
%%      and returns the corresponding value Res, or {badrpc, Reason} if the call fails.
-spec(call(From, Node, Mod, Method, Args, Timeout) ->
             Ret |
             {badrpc, any()} when From :: pid(),
                                  Node :: atom(),
                                  Mod  :: module(),
                                  Method  :: atom(),
                                  Args    :: [any()],
                                  Timeout :: pos_integer(),
                                  Ret :: any()).
call(From, Node, Mod, Method, Args, Timeout) ->
    Ret = call(Node, Mod, Method, Args, Timeout),
    erlang:send(From, {Node, Ret}).


%% @doc A multicall is an RPC which is sent concurrently from one client to multiple servers.
%%      This is useful for collecting some information from a set of nodes.
-spec(multicall(Nodes, Mod, Method, Args) ->
             Ret |
             {badrpc, any()} when Nodes  :: [atom()],
                                  Mod    :: module(),
                                  Method :: atom(),
                                  Args   :: [any()],
                                  Ret    :: any()).
multicall(Nodes, Mod, Method, Args) ->
    multicall(Nodes, Mod, Method, Args, ?DEF_TIMEOUT).


%% @doc A multicall is an RPC which is sent concurrently from one client to multiple servers.
%%      This is useful for collecting some information from a set of nodes.
-spec(multicall(Nodes, Mod, Method, Args, Timeout) ->
             Ret |
             {badrpc, any()} when Nodes   :: [atom()],
                                  Mod     :: module(),
                                  Method  :: atom(),
                                  Args    :: [any()],
                                  Timeout :: pos_integer(),
                                  Ret     :: [any()]).
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


%% @private
-spec(multicall_1(Nodes, Pid, Mod, Method, Args, Timeout) ->
             ok when Nodes   :: [atom()],
                     Pid     :: pid(),
                     Mod     :: module(),
                     Method  :: atom(),
                     Args    :: [any()],
                     Timeout :: pos_integer()).
multicall_1([],_Pid,_Mod,_Method,_Args,_Timeout) ->
    ok;
multicall_1([Node|Rest], Pid, Mod, Method, Args, Timeout) ->
    spawn(?MODULE, call, [Pid, Node, Mod, Method, Args, Timeout]),
    multicall_1(Rest, Pid, Mod, Method, Args, Timeout).


%% @doc This is able to call non-blocking.
%%      It returns the tuple {value, Val} when the computation has finished,
%%      or timeout when Timeout milliseconds has elapsed.
-spec(nb_yield(Key) ->
             {value, any()} |
             timeout when Key :: pid()).
nb_yield(Key) ->
    nb_yield(Key, ?DEF_TIMEOUT).


%% @doc This is able to call non-blocking.
%%      It returns the tuple {value, Val} when the computation has finished,
%%      or timeout when Timeout milliseconds has elapsed.
-spec(nb_yield(Key, Timeout) ->
             {value, any()} |
             timeout when Key :: pid(),
                          Timeout :: pos_integer()).
nb_yield(Key, Timeout) when is_pid(Key) ->
    case erlang:is_process_alive(Key) of
        false ->
            {value, {badrpc, invalid_key}};
        true ->
            erlang:send(Key, {get, self()}),
            receive
                {badrpc, timeout} ->
                    timeout;
                {badrpc, Cause} ->
                    {value, {badrpc, Cause}};
                Ret ->
                    {value, Ret}
            after Timeout ->
                    timeout
            end
    end;
nb_yield(_,_) ->
    {value, {badrpc, invalid_key}}.


%% @doc No response is delivered and the calling process is not suspended
%%      until the evaluation is complete, as is the case with call/4,5.
-spec(cast(Node, Mod, Method, Args) ->
             true when Node :: atom(),
                       Mod :: module(),
                       Method :: atom(),
                       Args :: [any()]).
cast(Node, Mod, Method, Args) ->
    _ = spawn(?MODULE, call, [Node, Mod, Method, Args]),
    true.


%% @doc Tries to set up a connection to Node.
%%      Returns pang if it fails, or pong if it is successful.
-spec(ping(Node) ->
             pong | pang when Node :: atom()).
ping(Node) ->
    case leo_rpc_client_manager:inspect(Node) of
        active ->
            pong;
        _ ->
            pang
    end.


%% @doc Retrieve status of active connections.
-spec(status() ->
             {ok, list(#rpc_info{})} |
             {error, any()}).
status() ->
    leo_rpc_client_manager:status().


%% @doc Returns the name of the local node. The default name is <code>nonode@nohost</code>.
-spec(node() ->
             Node when Node :: atom()).
node() -> erlang:node().


%% @doc Returns a list of all connected nodes in the system, excluding the local node.
-spec(nodes() ->
             Nodes when Nodes :: [atom()]).
nodes() ->
    {ok, Nodes} = leo_rpc_client_manager:connected_nodes(),
    Nodes.

%% @doc Returns the port number of the local node.
-spec(port() ->
             pos_integer()).
port() ->
    case application:get_env(leo_rpc, listen_port) of
        {ok, Port} -> Port;
        _  -> ?DEF_LISTEN_PORT
    end.


%%--------------------------------------------------------------------
%%  Internal Function
%%--------------------------------------------------------------------
%% @doc Execute rpc
%% @private
-spec(exec(Node, ParamsBin, Timeout) ->
             {ok, any()} |
             {error, any()} when Node :: string() | atom(),
                                 ParamsBin :: binary(),
                                 Timeout :: pos_integer()).
exec(Node, ParamsBin, Timeout) when is_atom(Node) ->
    Node1 = atom_to_list(Node),
    exec(Node1, ParamsBin, Timeout);

exec(Node, ParamsBin, Timeout) ->
    %% find the node from worker-procs
    {Node1, IP1, Port1} = case string:tokens(Node, "@:") of
                              [_Node, IP, Port] ->
                                  {list_to_atom(_Node), IP, list_to_integer(Port)};
                              [_Node, IP] ->
                                  {list_to_atom(_Node), IP, leo_rpc:port()};
                              [_Node] ->
                                  {list_to_atom(_Node), ?DEF_LISTEN_IP, leo_rpc:port()};
                              _ ->
                                  {[], 0, 0}
                          end,
    case Node1 of
        [] ->
            {error, invalid_node};
        _ ->
            PodName = leo_rpc_client_utils:get_client_worker_id(Node1, Port1),
            Ret = case whereis(PodName) of
                      undefined ->
                          case leo_rpc_client_sup:start_child(Node1, IP1, Port1) of
                              ok ->
                                  ok;
                              {error, Cause} ->
                                  {error, Cause}
                          end;
                      _ ->
                          ok
                  end,
            %% execute a requested function with a remote-node
            exec_1(Ret, PodName, ParamsBin, Timeout)
    end.

-spec(exec_1(Ret1,PodName,ParamsBin,Timeout) ->
             Ret2 when Ret1 :: ok | {ok, any()} | {error, any()},
                       PodName :: atom(),
                       ParamsBin :: binary(),
                       Timeout :: pos_integer(),
                       Ret2 :: {ok, any()} | {error, any()}).
exec_1({error, Cause},_PodName,_ParamsBin,_Timeout) ->
    {error, Cause};
exec_1(ok = Ret, PodName, ParamsBin, Timeout) ->
    case catch leo_pod:checkout(PodName) of
        {ok, ServerRef} ->
            FinalizerFun = fun() ->
                                   ok = leo_pod:checkin(PodName, ServerRef)
                           end,
            Reply = case catch gen_server:call(
                                 ServerRef,
                                 {request, ParamsBin, FinalizerFun},
                                 Timeout) of
                        {'EXIT', Cause} ->
                            {error, Cause};
                        Ret_1 ->
                            Ret_1
                    end,
            Reply;
        {error, ?ERROR_DUPLICATE_DEST} = Error ->
            Error;
        _ ->
            timer:sleep(500),
            exec_1(Ret, PodName, ParamsBin, Timeout)
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
