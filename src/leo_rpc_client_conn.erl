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
%% @doc leo_rpc_client_conn is a rpc-client
%% @reference https://github.com/leo-project/leo_rpc/blob/master/src/leo_rpc_client_conn
%% @end
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
          socket :: port()|undefined,
          reconnect_sleep :: integer(),
          buf    :: binary(),
          nreq   :: non_neg_integer(),
          pid_from :: {pid(), _}|undefined,
          finalizer :: fun()|undefined
         }).


-define(SOCKET_OPTS, [binary,
                      {active, once},
                      {packet, raw},
                      {reuseaddr, true}]).
-define(RECV_TIMEOUT, 20000).
-define(MAX_REQ_PER_CON, 1000000).

%% ===================================================================
%% APIs
%% ===================================================================
%% @doc Start the server
%%
-spec(start_link(list(any())) ->
             {ok, pid()} | {error, term()}).
start_link([Host, IP, Port, ReconnectSleepInterval]) ->
    gen_server:start_link(?MODULE, [Host, IP, Port, ReconnectSleepInterval], []).


%% @doc Stop the server
-spec(stop(pid()) ->
             ok | {error, any()}).
stop(ServerRef) ->
    gen_server:call(ServerRef, stop).


%%====================================================================
%% gen_server callbacks
%%====================================================================
%% @doc gen_server callback - Module:init(Args) -> Result
init([Host, IP, Port, ReconnectSleepInterval]) ->
    State = #state{host = Host,
                   ip = IP,
                   port = Port,
                   reconnect_sleep = ReconnectSleepInterval,
                   nreq = 0,
                   buf = <<>>},
    case connect(State) of
        {ok, NewState} ->
            {ok, NewState};
        {error, Reason} ->
            {stop, {connection_error, Reason}}
    end.


%% @doc gen_server callback - Module:handle_call(Request, From, State) -> Result
handle_call({request, Req, FinalizerFun}, From, State) ->
    exec(Req, From, State#state{finalizer = FinalizerFun});

handle_call(cancel, _From, State) ->
    terminate(cancel, State),
    {stop, cancel, ok, State#state{pid_from = undefined}};

handle_call(status,_From, #state{socket = Socket} = State) ->
    Ret = (Socket /= undefined),
    {reply, {ok, Ret}, State};

handle_call(stop, _From, State) ->
    terminate(stop, State),
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.


%% @doc gen_server callback - Module:handle_cast(Request, State) -> Result
handle_cast(_Msg, State) ->
    {noreply, State}.


%% @doc gen_server callback - Module:handle_info(Info, State) -> Result
handle_info({tcp, Socket, Bs}, #state{buf = Buf} = State) ->
    case recv(Socket, <<Buf/binary, Bs/binary>>) of
        {error,_Cause} ->
            NewState2 = case connect(State) of
                            {ok, NewState} ->
                                NewState;
                            _ ->
                                State#state{socket = undefined}
                        end,
            NewState3 = call_finalizer(NewState2),
            {noreply, NewState3};
        {value, Value, Rest} ->
            %% The receive buf should be empty
            case Rest of
                <<>> ->
                    void;
                Garbage ->
                    error_logger:error_msg(
                      "~p,~p,~p,~p~n",
                      [{module, ?MODULE_STRING}, {function, "handle_info/2"},
                       {line, ?LINE}, {body, {garbage_left_in_buf, Socket, Garbage}}])
            end,
            inet:setopts(Socket, [{active, once}]),
            NewState_1 = State#state{buf = Rest},
            NewState_2 = handle_response(Value, NewState_1),
            {noreply, NewState_2}
    end;

handle_info({tcp_error, Socket, Reason}, #state{pid_from = From} = State) ->
    error_logger:error_msg(
      "~p,~p,~p,~p~n",
      [{module, ?MODULE_STRING}, {function, "handle_info/2"},
       {line, ?LINE}, {body, {tcp_error, Socket, Reason}}]),
    reply({error, Reason}, From),
    terminate(tcp_error, State),
    {noreply, State#state{pid_from = undefined,
                          socket = undefined,
                          nreq = 0}};

handle_info({tcp_closed, _Socket}, State) ->
    terminate(tcp_closed, State),
    case State#state.reconnect_sleep of
        0 ->
            void;
        _ ->
            Self = self(),
            spawn(fun() -> reconnect_loop(Self, State) end)
    end,
    {noreply, State#state{socket = undefined}};

handle_info({connection_ready, Socket}, #state{socket = undefined} = State) ->
    {noreply, State#state{socket = Socket}};

handle_info(stop, State) ->
    terminate(stop, State),
    {stop, shutdown, State};

handle_info(_Info, State) ->
    terminate(_Info, State),
    {stop, {unhandled_message, _Info}, State}.


%% @doc gen_server callback - Module:terminate(Reason, State)
terminate(_Reason, #state{socket = Socket} = State) ->
    case Socket of
        undefined ->
            ok;
        Socket ->
            catch gen_tcp:close(Socket),
            ok
    end,
    call_finalizer(State),
    ok.

%% @doc gen_server callback - Module:code_change(OldVsn, State, Extra) -> {ok, NewState} | {error, Reason}
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ===================================================================
%% Inner Functions
%% ===================================================================
%% @doc: Send the given request to the rpc-server
%% @private
-spec(exec(iolist(), {pid(), _}, #state{}) ->
             {noreply, #state{}} | {reply, Reply::any(), #state{}}).
exec(Req, From, #state{socket = undefined} = State) ->
    case connect(State) of
        {ok, #state{socket = Socket} = State1} ->
            case gen_tcp:send(Socket, Req) of
                ok ->
                    {noreply, State1#state{pid_from = From}};
                {error,_Reason} ->
                    catch gen_tcp:close(Socket),
                    spawn(fun() -> reconnect_loop(self(), State) end),
                    NewState = call_finalizer(State),
                    {noreply, NewState#state{socket = undefined}}
            end;
        {error,_Reason} ->
            spawn(fun() -> reconnect_loop(self(), State) end),
            NewState = call_finalizer(State),
            {noreply, NewState#state{socket = undefined}}
    end;

exec(Req, From, #state{socket = Socket} = State) ->
    case gen_tcp:send(Socket, Req) of
        ok ->
            %% {noreply, State#state{pid_from = From}};
            {noreply, State#state{pid_from = From,
                                  socket = Socket}};
        {error,_Reason} ->
            catch gen_tcp:close(Socket),
            spawn(fun() -> reconnect_loop(self(), State) end),
            NewState = call_finalizer(State),
            {noreply, NewState#state{socket = undefined}}
    end.

%% @doc: Handle the response coming from Server
%% @private
-spec(handle_response(_, #state{}) ->
             #state{}).
handle_response(Data, #state{pid_from = From,
                             socket = Socket,
                             nreq = NumReq} = State) ->
    reply(Data, From),
    State_1 = call_finalizer(State),

    case (?env_max_req_for_reconnection() =< NumReq + 1) of
        true ->
            case connect(State_1) of
                {error, _} ->
                    State_1#state{pid_from = undefined,
                                  socket = undefined,
                                  nreq = 0};
                {ok, State_3} ->
                    State_3#state{pid_from = undefined,
                                  nreq = 0}
            end;
        false ->
            State_1#state{pid_from = undefined,
                          socket = Socket,
                          nreq = NumReq + 1}
    end.


%% @doc: Send data to the client
%% @private
reply(Value, undefined) ->
    error_logger:warning_msg(
      "~p,~p,~p,~p~n",
      [{module, ?MODULE_STRING}, {function, "reply/2"},
       {line, ?LINE}, {body, {ignored_due_to_timeout, Value}}]);

reply(Value, From) ->
    gen_server:reply(From, {ok, Value}).

%% @doc: Call finalizer only once
%% @private
call_finalizer(#state{finalizer = undefined} = State) ->
    State;
call_finalizer(#state{finalizer = Finalizer} = State) ->
    Finalizer(),
    State#state{finalizer = undefined}.

%% @doc: Connect to server
%% @private
connect(#state{socket = OldSocket} = State) ->
    case OldSocket of
        undefined ->
            void;
        _ ->
            catch gen_tcp:close(OldSocket)
    end,

    case catch gen_tcp:connect(State#state.ip,
                               State#state.port,
                               ?SOCKET_OPTS) of
        {ok, Socket} ->
            {ok, State#state{socket = Socket}};
        {error, Reason} ->
            {error, {connection_error, Reason}};
        {'EXIT',Reason} ->
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
%%      data-format:
%%      &lt;&lt; "*",
%%         $OriginalDataTypeBin/binary, ResultBodyLen/integer, "/r/n",
%%         $BodyBin_1_Len/integer,      "/r/n",
%%         $BodyBin_1/binary,           "/r/n",
%%         ...
%%         $BodyBin_N_Len/integer,      "/r/n",
%%         $BodyBin_N/binary,           "/r/n",
%%         "/r/n"
%%      &gt;&gt;
%%
-spec(recv(port(), binary()) ->
             {value, any(), binary()} | {error, any()}).
recv(Socket, Bin) ->
    Size = byte_size(Bin),
    recv(Socket, Bin, Size).

recv(Socket, Bin, GotSize) when GotSize < ?BLEN_LEN_TYPE_WITH_BODY ->
    WantSize = ?BLEN_LEN_TYPE_WITH_BODY,
    case gen_tcp:recv(Socket, WantSize - GotSize, ?RECV_TIMEOUT) of
        {ok, Rest} ->
            recv(Socket, <<Bin/binary, Rest/binary>>, WantSize);
        _ ->
            {error, {invalid_data_length, GotSize}}
    end;

recv(Socket, << $*,
                Type:?BLEN_TYPE_LEN/binary,
                BodyLen:?BLEN_BODY_LEN/integer, ?CRLF_STR, Rest/binary >>, Size) ->
    GotSize = byte_size(Rest),
    NeedSize = BodyLen + 2,
    WantSize = NeedSize - GotSize,

    case WantSize of
        RecvByte when RecvByte =< 0 ->
            <<TargetBin:NeedSize/binary, NextBin/binary>> = Rest,
            recv_0(Type, TargetBin, NextBin);
        RecvByte ->
            case gen_tcp:recv(Socket, RecvByte, ?RECV_TIMEOUT) of
                {ok, Rest2} ->
                    recv_0(Type, <<Rest/binary, Rest2/binary>>, <<>>);
                _ ->
                    {error, {invalid_data_length, Size}}
            end
    end.


recv_0(?BIN_ORG_TYPE_BIN, << Len:?BLEN_PARAM_TERM/integer, ?CRLF_STR, Rest/binary >>, NextBin) ->
    << RetBin:Len/binary, ?CRLF_CRLF_STR >> = Rest,
    {value, RetBin, NextBin};
recv_0(?BIN_ORG_TYPE_TERM, << Len:?BLEN_PARAM_TERM/integer, ?CRLF_STR, Rest/binary >>, NextBin) ->
    << Term:Len/binary, ?CRLF_CRLF_STR >> = Rest,
    {value, binary_to_term(Term), NextBin};
recv_0(?BIN_ORG_TYPE_TUPLE, << Len:?BLEN_PARAM_TERM/integer, ?CRLF_STR, Rest/binary >>, NextBin) ->
    recv_1(Len, Rest, [], NextBin);
recv_0(InvalidType, _Rest, _NextBin) ->
    {error, {invalid_root_type, InvalidType}}.


recv_1(_, ?CRLF, Acc, NextBin) ->
    {value, list_to_tuple(Acc), NextBin};
recv_1(Len, << $B, ?CRLF_STR, Rest1/binary >>, Acc, NextBin) ->
    recv_2(Len, ?BIN_ORG_TYPE_BIN, Rest1, Acc, NextBin);
recv_1(Len, << $M, ?CRLF_STR, Rest1/binary >>, Acc, NextBin) ->
    recv_2(Len, ?BIN_ORG_TYPE_TERM, Rest1, Acc, NextBin);
recv_1(Len, << $T, ?CRLF_STR, Rest1/binary >>, Acc, NextBin) ->
    recv_2(Len, ?BIN_ORG_TYPE_TUPLE, Rest1, Acc, NextBin);
recv_1(_,_InvalidBlock,_,_NextBin) ->
    {error, {invalid_tuple_type, _InvalidBlock}}.


recv_2(Len, Type, Rest1, Acc, NextBin) ->
    case (byte_size(Rest1) > Len) of
        true ->
            << Item:Len/binary, ?CRLF_STR, Rest2/binary >> = Rest1,
            {Len2, Rest4} =
                case Rest2 of
                    << Len1:?BLEN_PARAM_TERM/integer, ?CRLF_STR, Rest3/binary >> ->
                        {Len1, Rest3};
                    _ ->
                        {0, Rest2}
                end,

            Acc1 = case Type of
                       ?BIN_ORG_TYPE_BIN ->
                           [Item|Acc];
                       _ ->
                           [binary_to_term(Item)|Acc]
                   end,
            recv_1(Len2, Rest4, Acc1, NextBin);
        false ->
            {error, {invalid_data_length, Len, Type, Rest1}}
    end.
