%%======================================================================
%%
%% Leo Backend-DB
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

%% @doc: data parse related definitions
%%
-define(CRLF, <<"\r\n">>).
-define(BIN_ORG_TYPE_BIN,   <<"B">>).
-define(BIN_ORG_TYPE_TERM,  <<"M">>).
-define(BIN_ORG_TYPE_TUPLE, <<"T">>).

-define(BLEN_MOD_METHOD_LEN,  8).
-define(BLEN_TYPE_LEN,        1).
-define(BLEN_PARAM_LEN,       8).
-define(BLEN_PARAM_TERM,     32).


%% @doc: rpc-server related definitions
%%
-define(POOL_NAME, 'leo_tcp_pool').
-define(DEF_ACCEPTORS,   64).
-define(DEF_LISTEN_PORT, 13075).

-define(DEF_CLIENT_POOL_NAME_PREFIX, "leo_rpc_client_").
-define(DEF_CLIENT_CONN_POOL_SIZE, 8).
-define(DEF_CLIENT_CONN_BUF_SIZE, 16).

-define(DEF_CLIENT_WORKER_SUP_ID, 'leo_rpc_client_worker').
-define(DEF_CLIENT_WORKER_POOL_SIZE, 8).
-define(DEF_CLIENT_WORKER_BUF_SIZE, 16).

-record(rpc_info, { module :: atom(),
                    method :: atom(),
                    params = [] :: list(any())
                  }).


%% @doc: rpc-connection/rpc-client related definitions
%%
-define(TBL_RPC_CONN_INFO, 'leo_rpc_conn_info').

-record(rpc_conn, { node :: atom(),
                    host = [] :: string(),
                    port = ?DEF_LISTEN_PORT :: pos_integer(),
                    workers = 0 :: pos_integer(),
                    manager_ref :: atom()
                  }).


-ifdef(TEST).
-define(DEF_INSPECT_INTERVAL, 500).
-else.
-define(DEF_INSPECT_INTERVAL, 5000).
-endif.

