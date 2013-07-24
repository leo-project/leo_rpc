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
-define(BLEN_BODY_ROWS,       8).
-define(BLEN_BODY_LEN,       32).


%% @doc: rpc-server related definitions
%%
-define(POOL_NAME, 'leo_tcp_pool').
-define(DEF_ACCEPTORS,   128).
-define(DEF_LISTEN_IP,   "127.0.0.1").
-define(DEF_LISTEN_PORT, 13075).

-define(DEF_CLIENT_POOL_NAME_PREFIX, "leo_rpc_client_").
-define(DEF_CLIENT_CONN_POOL_SIZE, 64).
-define(DEF_CLIENT_CONN_BUF_SIZE,  32).

-define(DEF_CLIENT_WORKER_SUP_ID, 'leo_rpc_client_worker').
-define(DEF_CLIENT_WORKER_POOL_SIZE, 64).
-define(DEF_CLIENT_WORKER_BUF_SIZE,  64).

-record(rpc_info, { module :: atom(),
                    method :: atom(),
                    params = [] :: list(any())
                  }).


%% @doc: rpc-connection/rpc-client related definitions
%%
-define(TBL_RPC_CONN_INFO, 'leo_rpc_conn_info').

-record(rpc_conn, { host = [] :: string(),
                    ip :: string(),
                    port = ?DEF_LISTEN_PORT :: pos_integer(),
                    workers = 0 :: pos_integer(),
                    manager_ref :: atom()
                  }).

-record(tcp_server_params, {
          prefix_of_name = "leo_rpc_listener_"  :: string(),
          listen = [binary, {packet, line},
                    {active, false}, {reuseaddr, true},
                    {backlog, 1024}, {nodelay, true}],
          port                    = 13075 :: pos_integer(),
          num_of_listeners        = 256   :: pos_integer(),
          restart_times           = 3     :: pos_integer(),
          time                    = 60    :: pos_integer(),
          shutdown                = 2000  :: pos_integer(),
          accept_timeout          = infinity,
          accept_error_sleep_time = 3000  :: pos_integer(),
          recv_length             = 0     :: pos_integer(),
          recv_timeout            = infinity
         }).


-ifdef(TEST).
-define(DEF_INSPECT_INTERVAL, 500).
-else.
-define(DEF_INSPECT_INTERVAL, 5000).
-endif.

