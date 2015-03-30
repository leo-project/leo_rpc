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
%%======================================================================
-module(leo_rpc_client_sup).

-author('Yosuke Hara').

-behaviour(supervisor).

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/0, stop/0]).
-export([start_child/3, start_child/4]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).
-define(SHUTDOWN_WAITING_TIME, 10000).

%% ===================================================================
%% API functions
%% ===================================================================
start_link() ->
    Res = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    ?TBL_RPC_CONN_INFO = ets:new(?TBL_RPC_CONN_INFO,
                                 [named_table, ordered_set, public,
                                  {read_concurrency, true}]),
    Res.


stop() ->
    ok.


%% @doc Launch a child worker
%%
-spec(start_child(atom(), string(), pos_integer()) ->
             ok | {error, any()}).
start_child(Host, IP, Port) ->
    start_child(Host, IP, Port, 0).

-spec(start_child(atom(), string(), pos_integer(), non_neg_integer()) ->
             ok | {error, any()}).
start_child(Host, IP, Port, ReconnectSleep) ->
    Ret = leo_rpc_client_manager:is_exists(IP, Port),
    start_child_1(Ret, Host, IP, Port, ReconnectSleep).

%% @private
start_child_1(true, _Host,_IP,_Port,_ReconnectSleep) ->
    {error, ?ERROR_DUPLICATE_DEST};
start_child_1(false, Host, IP, Port, ReconnectSleep) ->
    Id = leo_rpc_client_utils:get_client_worker_id(Host, Port),
    case whereis(Id) of
        undefined ->
            WorkerArgs = [Host, IP, Port, ReconnectSleep],
            InitFun = fun(ManagerRef) ->
                              true = ets:insert(
                                       ?TBL_RPC_CONN_INFO,
                                       {Host,
                                        #rpc_conn{host = Host,
                                                  ip = IP,
                                                  port = Port,
                                                  workers = ?DEF_CLIENT_CONN_POOL_SIZE,
                                                  manager_ref = ManagerRef}})
                      end,

            ChildSpec  = {Id, {leo_pod_sup, start_link,
                               [Id,
                                ?env_rpc_con_pool_size(),
                                ?env_rpc_con_buffer_size(),
                                leo_rpc_client_conn, WorkerArgs, InitFun]},
                          permanent, ?SHUTDOWN_WAITING_TIME,
                          supervisor, [leo_pod_sup]},

            case supervisor:start_child(?MODULE, ChildSpec) of
                {ok, _Pid} ->
                    ok;
                {error, {already_started, _Pid}} ->
                    ok;
                {error, Cause} ->
                    error_logger:warning_msg(
                      "~p,~p,~p,~p~n",
                      [{module, ?MODULE_STRING}, {function, "start_child/3"},
                       {line, ?LINE}, {body, Cause}]),
                    {error, Cause}
            end;
        _ ->
            ok
    end.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([]) ->
    Interval  = case application:get_env('leo_tcp', 'inspect_interval') of
                    {ok, EnvVal} -> EnvVal;
                    _ -> ?DEF_INSPECT_INTERVAL
                end,
    ChildSpec = [
                 {leo_rpc_client_manager,
                  {leo_rpc_client_manager, start_link, [Interval]},
                  permanent,
                  2000,
                  worker,
                  [leo_rpc_client_manager]}
                ],
    {ok, { {one_for_one, 5, 10}, ChildSpec} }.


%% ===================================================================
%% Internal Functions
%% ===================================================================
