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

-define(DEF_POOL_SIZE, 32).
-define(DEF_POOL_BUF,  32).
-define(DEF_RPC_PORT,  13075).
-define(SHUTDOWN_WAITING_TIME, 2000).
-define(MAX_RESTART,              5).
-define(MAX_TIME,                60).

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
    case whereis(?MODULE) of
        Pid when is_pid(Pid) ->
            exit(Pid, shutdown),
            ok;
        _ ->
            not_started
    end.


start_child(Host, IP, Port) ->
    start_child(Host, IP, Port, 0).

start_child(Host, IP, Port, ReconnectSleep) ->
    Id = leo_rpc_client_utils:get_client_worker_id(Host, Port),
    case whereis(Id) of
        undefined ->
            WorkerArgs = [Host, IP, Port, ReconnectSleep],
            InitFun = fun(ManagerRef) ->
                              true = ets:insert(?TBL_RPC_CONN_INFO,
                                                {Host, #rpc_conn{host = Host,
                                                                 ip = IP,
                                                                 port = Port,
                                                                 workers = ?DEF_CLIENT_CONN_POOL_SIZE,
                                                                 manager_ref = ManagerRef}})
                      end,
            ChildSpec  = {Id, {leo_pod_sup, start_link,
                               [Id,
                                ?DEF_CLIENT_CONN_POOL_SIZE,
                                ?DEF_CLIENT_CONN_BUF_SIZE,
                                leo_rpc_client_conn, WorkerArgs, InitFun]},
                          permanent, ?SHUTDOWN_WAITING_TIME,
                          supervisor, [leo_pod_sup]},
            case supervisor:start_child(?MODULE, ChildSpec) of
                {ok, _Pid} ->
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

