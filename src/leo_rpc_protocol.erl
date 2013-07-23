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
-module(leo_rpc_protocol).

-author('Yosuke Hara').

-include("leo_rpc.hrl").
-include_lib("eunit/include/eunit.hrl").

-export([start_link/0, start_link/1,
         stop/0]).
-export([init/1, handle_call/3]).
-export([param_to_binary/3, binary_to_param/1,
         result_to_binary/1, binary_to_result/1
        ]).

-undef(TIMEOUT).
-define(TIMEOUT, 5000).

-define(RET_ERROR, <<"+ERROR\r\n">>).

%% ===================================================================
%% API-1
%% ===================================================================
start_link() ->
    Params = #tcp_server_params{listen = [binary, {packet, line},
                                          {active, false}, {reuseaddr, true},
                                          {backlog, 1024}, {nodelay, true}]},
    start_link(Params).

start_link(Params) ->
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
    leo_rpc_server:start_link(?MODULE, [],
                              Params#tcp_server_params{num_of_listeners = NumOfAcceptors,
                                                       port = ListenPort}).

stop() ->
    leo_rpc_server:stop().


%%----------------------------------------------------------------------
%% Callback function(s)
%%----------------------------------------------------------------------
init(_) ->
    {ok, null}.


handle_call(Socket, Data, State) ->
    Reply = case Data of
                << "*", ModMethodLen:?BLEN_MOD_METHOD_LEN/integer, "\r\n" >> ->
                    Data1 = handle_call_1(Socket, ModMethodLen, Data),

                    case binary_to_param(Data1) of
                        {ok, #rpc_info{module = Mod,
                                       method = Method,
                                       params = Args}} ->
                            Ret = case catch erlang:apply(Mod, Method, Args) of
                                      {'EXIT', Cause} ->
                                          {error, Cause};
                                      Term ->
                                          Term
                                  end,
                            result_to_binary(Ret);
                        {error,_Cause} ->
                            ?RET_ERROR
                    end;
                _ ->
                    ?RET_ERROR
            end,
    {reply, Reply, State}.


%% @doc Retrieve the 2nd line
%% @private
handle_call_1(Socket, ModMethodLen, Acc) ->
    ok = inet:setopts(Socket, [{packet, raw}]),
    case gen_tcp:recv(Socket, (ModMethodLen + 2), ?TIMEOUT) of
        {ok, Bin1} ->
            handle_call_2(Socket, << Acc/binary, Bin1/binary >>);
        _ ->
            Acc
    end.

%% @doc Retrieve the 3rd line
%% @private
handle_call_2(Socket, Acc) ->
    ok = inet:setopts(Socket, [{packet, line}]),
    case gen_tcp:recv(Socket, 0, ?TIMEOUT) of
        %% Retrieve the 3nd line
        {ok, << _ParamsLen:?BLEN_PARAM_LEN,
                BodyLen:?BLEN_BODY_LEN, "\r\n" >> = Bin} ->
            handle_call_3(Socket, BodyLen, << Acc/binary, Bin/binary >> )
    end.


%% @doc Retrieve the 4th line
%% @private
handle_call_3(Socket, BodyLen, Acc) ->
    ok = inet:setopts(Socket, [{packet, raw}]),
    Ret = case gen_tcp:recv(Socket, (BodyLen + 2), ?TIMEOUT) of
              {ok, Bin} ->
                  << Acc/binary, Bin/binary >>;
              _ ->
                  Acc
          end,
    ok = inet:setopts(Socket, [{packet, line}]),
    Ret.


%% ===================================================================
%% API-2
%% ===================================================================
%% @doc Convert from param to binary
%% Format:
%% << "*",
%%    $ModMethodBin/binary,    "/r/n",
%%    $ParamsLenBin:8/integer, $BodyLen:32/integer, "/r/n",
%%    $Param_1_Bin_Len/binary, "/r/n", "T"|"B", $Param_1_Bin/binary, "/r/n",
%%    ...
%%    $Param_N_Bin_Len/binary, "/r/n", "T"|"B", $Param_N_Bin/binary, "/r/n",
%%    "/r/n" >>
%%
-spec(param_to_binary(atom(), atom(), list()) ->
             binary()).
param_to_binary(Mod, Method, Args) ->
    ModMethodBin = term_to_binary({Mod, Method}),
    ModMethodLen = byte_size(ModMethodBin),
    ParamLen     = length(Args),

    Body = lists:foldl(fun(Item, Acc) when is_binary(Item) ->
                               Len = byte_size(Item),
                               << Acc/binary,
                                  Len:?BLEN_PARAM_TERM/integer, ?CRLF/binary,
                                  ?BIN_ORG_TYPE_BIN/binary,     ?CRLF/binary,
                                  Item/binary, ?CRLF/binary >>;
                          (Item, Acc) ->
                               Bin = term_to_binary(Item),
                               Len = byte_size(Bin),
                               << Acc/binary,
                                  Len:?BLEN_PARAM_TERM/integer, ?CRLF/binary,
                                  ?BIN_ORG_TYPE_TERM/binary,    ?CRLF/binary,
                                  Bin/binary, ?CRLF/binary >>
                       end, <<>>, Args),
    BodyLen = byte_size(Body),
    << "*", ModMethodLen:?BLEN_MOD_METHOD_LEN/integer, ?CRLF/binary,
       ModMethodBin/binary, ?CRLF/binary,
       ParamLen:?BLEN_PARAM_LEN/integer, BodyLen:?BLEN_BODY_LEN/integer, ?CRLF/binary,
       Body/binary, ?CRLF/binary >>.


%% @doc Convert from binary to param
-spec(binary_to_param(binary()) ->
             {ok, []} | {error, any()}).
binary_to_param(<< "*",
                   ModMethodLen:?BLEN_MOD_METHOD_LEN/integer, "\r\n",
                   Rest1/binary >>) ->

    %% retrieve: module, method
    case Rest1 of
        << ModMethodBin:ModMethodLen/binary, "\r\n", Rest2/binary >> ->
            {Mod, Method} = binary_to_term(ModMethodBin),

            %% retrieve: param's length
            case Rest2 of
                << ParamsLen:?BLEN_PARAM_LEN/integer,
                   _BodyLen:?BLEN_BODY_LEN/integer, "\r\n", Rest3/binary >> ->
                    %% retrieve: params
                    case binary_to_param_1(Rest3, []) of
                        {ok, Params} when ParamsLen == length(Params) ->
                            {ok, #rpc_info{module = Mod,
                                           method = Method,
                                           params = Params}};
                        {ok, _} ->
                            {error, invalid_format};
                        {error, Cause} ->
                            {error, Cause}
                    end;
                _ ->
                    {error, invalid_format}
            end;
        _ ->
            {error, invalid_format}
    end;
binary_to_param(_) ->
    {error, invalid_format}.


binary_to_param_1(?CRLF, Acc) ->
    {ok, lists:reverse(Acc)};
binary_to_param_1(<< L:?BLEN_PARAM_TERM/integer, "\r\n", Rest/binary >>, Acc) ->
    case Rest of
        << Type:?BLEN_TYPE_LEN/binary,  "\r\n", Rest1/binary>> ->
            case Rest1 of
                << Param:L/binary, "\r\n", Rest2/binary>> ->
                    case Type of
                        ?BIN_ORG_TYPE_TERM -> binary_to_param_1(Rest2, [binary_to_term(Param)|Acc]);
                        ?BIN_ORG_TYPE_BIN  -> binary_to_param_1(Rest2, [Param|Acc]);
                        _ ->
                            {error, invalid_format}
                    end;
                _ ->
                    {error, invalid_format}
            end;
        _ ->
            {error, invalid_format}
    end;
binary_to_param_1(_Bin,_) ->
    {error, invalid_format}.


%% @doc Convert from result-value to binary
%% Format:
%% << "*",
%%    $OriginalDataTypeBin/binary, "/r/n",
%%    $BodyBin_1_Len/integer,      "/r/n",
%%    $BodyBin_1/binary,           "/r/n",
%%    ...
%%    $BodyBin_N_Len/integer,      "/r/n",
%%    $BodyBin_N/binary,           "/r/n",
%%    "/r/n"
%%    >>
%%
-spec(result_to_binary(any()) ->
             binary()).
result_to_binary(Term) when is_tuple(Term) ->
    {ok, Body} = result_to_binary_1(tuple_size(Term), Term, <<>>),
    << "*",
       ?BIN_ORG_TYPE_TUPLE/binary, ?CRLF/binary,
       Body/binary, ?CRLF/binary >>;
result_to_binary(Term) when is_binary(Term) ->
    Len = byte_size(Term),
    Body = << Len:?BLEN_PARAM_TERM/integer, ?CRLF/binary,
              Term/binary, ?CRLF/binary >>,
    << "*",
       ?BIN_ORG_TYPE_BIN/binary, ?CRLF/binary,
       Body/binary, ?CRLF/binary >>;
result_to_binary(Term) ->
    Bin = term_to_binary(Term),
    Len = byte_size(Bin),
    Body = << Len:?BLEN_PARAM_TERM/integer, ?CRLF/binary,
              Bin/binary, ?CRLF/binary >>,
    << "*",
       ?BIN_ORG_TYPE_TERM/binary, ?CRLF/binary,
       Body/binary, ?CRLF/binary >>.


result_to_binary_1(0,_Term, Acc) ->
    {ok, Acc};
result_to_binary_1(Index, Term, Acc) ->
    Bin1 = case element(Index, Term) of
               Item when is_binary(Item) ->
                   Len = byte_size(Item),
                   << Acc/binary,
                      Len:?BLEN_PARAM_TERM/integer, ?CRLF/binary,
                      ?BIN_ORG_TYPE_BIN/binary,     ?CRLF/binary,
                      Item/binary,                  ?CRLF/binary >>;
               Item ->
                   Bin2 = term_to_binary(Item),
                   Len = byte_size(Bin2),
                   << Acc/binary,
                      Len:?BLEN_PARAM_TERM/integer, ?CRLF/binary,
                      ?BIN_ORG_TYPE_TERM/binary,    ?CRLF/binary,
                      Bin2/binary,                  ?CRLF/binary >>
           end,
    result_to_binary_1(Index-1, Term, Bin1).


%% @doc Convert from binary to result-value
%%
-spec(binary_to_result(binary()) ->
             any()).

binary_to_result(<< "*", Type:?BLEN_TYPE_LEN/binary, "\r\n", Rest/binary >>) ->
    << Len:?BLEN_PARAM_TERM/integer, "\r\n", Rest1/binary >> = Rest,
    case Type of
        ?BIN_ORG_TYPE_BIN ->
            << Bin:Len/binary, "\r\n\r\n" >> = Rest1,
            Bin;
        ?BIN_ORG_TYPE_TERM ->
            << Term:Len/binary, "\r\n\r\n" >> = Rest1,
            binary_to_term(Term);
        ?BIN_ORG_TYPE_TUPLE ->
            void;
        _ ->
            {error, invalid_format}
    end;
binary_to_result(_) ->
    {error, invalid_format}.

