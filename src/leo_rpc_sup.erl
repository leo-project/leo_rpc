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
-module(leo_rpc_sup).

-author('Yosuke Hara').

-behaviour(supervisor).

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/0, stop/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

stop() ->
    case whereis(?MODULE) of
        Pid when is_pid(Pid) ->
            exit(Pid, shutdown),
            ok;
        _ ->
            not_started
    end.


%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([]) ->
    catch leo_misc:init_env(),

    NumOfAcceptors =
        case application:get_env('leo_rpc', 'num_of_acceptors') of
            {ok, Env1} -> Env1;
            _ -> ?DEF_ACCEPTORS
        end,
    ListenPort =
        case application:get_env('leo_rpc', 'listen_port') of
            {ok, Env2} -> Env2;
            _ -> ?DEF_LISTEN_PORT
        end,

    RanchSupSpec = {ranch_sup, {ranch_sup, start_link, []},
                    permanent, 5000, supervisor, [ranch_sup]},
    RanchChildSpec = ranch:child_spec(leo_rpc_protocol, NumOfAcceptors,
                                      ranch_tcp, [{port, ListenPort}],
                                      leo_rpc_protocol, []),

    ClientSupSpec = {leo_rpc_client_sup, {leo_rpc_client_sup, start_link, []},
                     permanent, 5000, supervisor, [leo_rpc_client_sup]},
    ChildSpecs = [RanchSupSpec, RanchChildSpec, ClientSupSpec],
    {ok, { {one_for_one, 5, 10}, ChildSpecs} }.

