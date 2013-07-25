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
-module(leo_rpc_client_conn).

-author('Yosuke Hara').

-behaviour(gen_server).

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

%% API
-export([start_link/1, stop/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, {
          id     :: atom(),
          host   :: string(),
          ip     :: pos_integer(),
          port   :: integer(),
          socket :: reference()|undefined,
          reconnect_sleep :: integer(),
          queue = [] :: list()
         }).


-define(SOCKET_OPTS, [binary, {active, once}, {packet, line}, {reuseaddr, true}]).
-define(RECV_TIMEOUT, 5000).


%% ===================================================================
%% APIs
%% ===================================================================
-spec(start_link(list(any())) ->
             {ok, pid()} | {error, term()}).
start_link([Host, IP, Port, ReconnectSleepInterval]) ->
    gen_server:start_link(?MODULE, [Host, IP, Port, ReconnectSleepInterval], []).

stop(ServerRef) ->
    gen_server:call(ServerRef, stop).


%%====================================================================
%% gen_server callbacks
%%====================================================================
init([Host, IP, Port, ReconnectSleepInterval]) ->
    State = #state{host = Host,
                   ip = IP,
                   port = Port,
                   reconnect_sleep = ReconnectSleepInterval,
                   queue = []},
    case connect(State) of
        {ok, NewState} ->
            {ok, NewState};
        {error, Reason} ->
            {stop, {connection_error, Reason}}
    end.

handle_call({request, Req}, From, State) ->
    exec(Req, From, State);

handle_call(status,_From, #state{socket = Socket} = State) ->
    Ret = (Socket /= undefined),
    {reply, {ok, Ret}, State};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info({tcp, Socket, Bs}, State) ->
    Res = recv(Socket, Bs),
    inet:setopts(Socket, [{active, once},{packet, line}]),
    {noreply, handle_response(Res, State)};

handle_info({tcp_error, _Socket, _Reason}, State) ->
    {noreply, State};

handle_info({tcp_closed, _Socket}, State) ->
    case State#state.reconnect_sleep of
        0 ->
            void;
        _ ->
            Self = self(),
            spawn(fun() -> reconnect_loop(Self, State) end)
    end,
    {noreply, State#state{socket = undefined, queue = []}};

handle_info({connection_ready, Socket}, #state{socket = undefined} = State) ->
    {noreply, State#state{socket = Socket}};

handle_info(stop, State) ->
    {stop, shutdown, State};

handle_info(_Info, State) ->
    {stop, {unhandled_message, _Info}, State}.

terminate(_Reason, #state{socket = Socket}) ->
    case Socket of
        undefined ->
            ok;
        Socket ->
            catch gen_tcp:close(Socket),
            ok
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Inner Functions
%% ===================================================================
%% @doc: Send the given request to the rpc-server
%% @ptivate
-spec(exec(iolist(), pid(), #state{}) ->
             {noreply, #state{}} | {reply, Reply::any(), #state{}}).
exec(Req, From, #state{socket = undefined} = State) ->
    case connect(State) of
        {ok, #state{socket = Socket} = State1} ->
            case gen_tcp:send(Socket, Req) of
                ok ->
                    NewQueue = [From|State1#state.queue],
                    {noreply, State1#state{queue = NewQueue}};
                {error, Reason} ->
                    {reply, {error, Reason}, State1}
            end;
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end;

exec(Req, From, #state{socket = Socket} = State) ->
    case gen_tcp:send(Socket, Req) of
        ok ->
            NewQueue = [From|State#state.queue],
            {noreply, State#state{queue = NewQueue}};
        {error, Reason} ->
            {reply, {error, Reason}, State}
    end.


%% @doc: Handle the response coming from Server
%% @private
-spec(handle_response(binary(), #state{}) ->
             #state{}).
handle_response(Data, #state{queue = Queue} = State) ->
    NewQueue = reply(Data, Queue),
    State#state{queue = NewQueue}.


%% @doc: Send data to the 1st-client in the queue
%% @private
reply(_, []) ->
    error_logger:warning_msg(
      "~p,~p,~p,~p~n",
      [{module, ?MODULE_STRING}, {function, "reply/2"},
       {line, ?LINE}, {body, "Nothing in queue"}]),
    throw(empty_queue);

reply(Value, Queue) ->
    [From|NewQueue] = lists:reverse(Queue),
    gen_server:reply(From, {ok, Value}),
    NewQueue.


%% @doc: Connect to server
%% @private
connect(State) ->
    case gen_tcp:connect(State#state.ip, State#state.port, ?SOCKET_OPTS) of
        {ok, Socket} ->
            {ok, State#state{socket = Socket}};
        {error, Reason} ->
            {error, {connection_error, Reason}}
    end.


%% @doc: Repeat until a connection can be established
reconnect_loop(_, #state{reconnect_sleep = 0}) ->
    ok;
reconnect_loop(Client, #state{reconnect_sleep = ReconnectSleepInterval} = State) ->
    case catch(connect(State)) of
        {ok, #state{socket = Socket}} ->
            gen_tcp:controlling_process(Socket, Client),
            erlang:send(Client, {connection_ready, Socket});
        _ ->
            timer:sleep(ReconnectSleepInterval),
            reconnect_loop(Client, State)
    end.


%% @doc Convert from result-value to binary
%% data-format:
%% << "*",
%%    $OriginalDataTypeBin/binary, ResultBodyLen/integer, "/r/n",
%%    $BodyBin_1_Len/integer,      "/r/n",
%%    $BodyBin_1/binary,           "/r/n",
%%    ...
%%    $BodyBin_N_Len/integer,      "/r/n",
%%    $BodyBin_N/binary,           "/r/n",
%%    "/r/n"
%%    >>
%%
-spec(recv(pid(), binary()) ->
             any() | {error, invalid_format}).
recv(Socket, << "*",
                Type:?BLEN_TYPE_LEN/binary,
                BodyLen:?BLEN_BODY_LEN/integer, "\r\n" >>) ->
    inet:setopts(Socket, [{packet, raw}]),
    case gen_tcp:recv(Socket, (BodyLen + 2), ?RECV_TIMEOUT) of
        {ok, << Len:?BLEN_PARAM_TERM/integer, "\r\n", Rest/binary >>} ->
            case Type of
                ?BIN_ORG_TYPE_BIN ->
                    << RetBin:Len/binary, "\r\n\r\n" >> = Rest,
                    RetBin;
                ?BIN_ORG_TYPE_TERM ->
                    << Term:Len/binary, "\r\n\r\n" >> = Rest,
                    binary_to_term(Term);
                ?BIN_ORG_TYPE_TUPLE ->
                    %% TODO
                    void;
                _ ->
                    {error, invalid_format}
            end;
        _ ->
            {error, invalid_format}
    end;
recv(_Socket,_) ->
    {error, invalid_format}.

