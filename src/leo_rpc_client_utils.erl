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
-module(leo_rpc_client_utils).

-author('Yosuke Hara').

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([get_client_worker_id/2, create_client_worker_id/2]).


%% ===================================================================
%% API functions
%% ===================================================================
%% @doc Retrieve client-worker's id by host and port
%%
-spec(get_client_worker_id(string()|atom(), pos_integer()) ->
             atom()).
get_client_worker_id(Host, Port) when is_atom(Host) ->
    get_client_worker_id(atom_to_list(Host), Port);

get_client_worker_id(Host, Port) ->
    Id = list_to_atom(create_client_worker_id(Host, Port)),
    Id.


%% @doc Generate client-worker-id from host and port
%%
-spec(create_client_worker_id(string(), pos_integer()) ->
             string()).
create_client_worker_id(Host, Port) ->
    Host1 = case is_atom(Host) of
                true  -> atom_to_list(Host);
                false -> Host
            end,

    lists:append([?DEF_CLIENT_POOL_NAME_PREFIX,
                  Host1, "_at_", integer_to_list(Port)]).

