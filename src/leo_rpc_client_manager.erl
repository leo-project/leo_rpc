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
-module(leo_rpc_client_manager).

-author('Yosuke Hara').

-behaviour(gen_server).

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/1, stop/0]).
-export([inspect/0, inspect/1, status/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
          interval = 0 :: pos_integer(),
          active = [] :: list(tuple())
         }).

%% ===================================================================
%% APIs
%% ===================================================================
-spec(start_link(pos_integer()) ->
             {ok, pid()} | {error, term()}).
start_link(Interval) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [Interval], []).


stop() ->
    gen_server:call(?MODULE, stop).


inspect() ->
    gen_server:cast(?MODULE, inspect).

inspect(Node) ->
    gen_server:call(?MODULE, {inspect, Node}).

status() ->
    gen_server:call(?MODULE, status).


%%====================================================================
%% gen_server callbacks
%%====================================================================
init([Interval]) ->
    defer_inspect(Interval),
    {ok, #state{interval = Interval}}.


handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call({inspect, Node}, _From, State) ->
    {ok, Active} = inspect_fun(0, false),
    Ret = case lists:keyfind(Node, 1, Active) of
              {_,_Host,_Port, NumOfActive,_Workers} when NumOfActive > 0 ->
                  active;
              _ ->
                  inactive
          end,
    {reply, Ret, State};

handle_call(status, _From, #state{active = Active} = State) ->
    {reply, {ok, Active}, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.

handle_cast(inspect, #state{interval = Interval} = State) ->
    {ok, Active} = inspect_fun(Interval),
    {noreply, State#state{active = Active}};

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info(stop, State) ->
    {stop, shutdown, State};

handle_info(_Info, State) ->
    {stop, {unhandled_message, _Info}, State}.


terminate(_Reason,_State) ->
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%====================================================================
%% Internal Functions
%%====================================================================
%% @doc Inspect rpc-workers's status
%%
-spec(defer_inspect(pos_integer()) ->
             ok).
defer_inspect(Interval) ->
    timer:apply_after(Interval, ?MODULE, inspect, []).


%% @doc Inspect rpc-workers's status
%%
-spec(inspect_fun(pos_integer()) ->
             ok).
inspect_fun(Interval) ->
    inspect_fun(Interval, true).

inspect_fun(Interval, IsDefer) ->
    Ret = inspect_fun_1([]),
    case IsDefer of
        true  -> defer_inspect(Interval);
        false -> void
    end,
    Ret.

inspect_fun_1([] = Acc) ->
    Ret = ets:first(?TBL_RPC_CONN_INFO),
    inspect_fun_2(Ret, Acc).
inspect_fun_1(Acc, Key) ->
    Ret = ets:next(?TBL_RPC_CONN_INFO, Key),
    inspect_fun_2(Ret, Acc).

inspect_fun_2('$end_of_table', Acc) ->
    {ok, lists:reverse(Acc)};
inspect_fun_2(Key, Acc) ->
    [{_, #rpc_conn{host = Host,
                   port = Port,
                   manager_ref = ManagerRef}}|_] = ets:lookup(?TBL_RPC_CONN_INFO, Key),
    {ok, Status} = gen_server:call(ManagerRef, status),
    {ok, Active} = inspect_fun_3(Status, 0),
    inspect_fun_1([{Key, Host, Port, Active, length(Status)}|Acc], Key).

inspect_fun_3([], Active) ->
    {ok, Active};
inspect_fun_3([ServerRef|Rest], Active) ->
    case gen_server:call(ServerRef, status) of
        {ok, true} ->
            inspect_fun_3(Rest, Active + 1);
        _ ->
            inspect_fun_3(Rest, Active)
    end.

