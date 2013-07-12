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
-module(leo_rpc_client_worker).

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
          clock  :: pos_integer(),
          node   :: atom(),
          module :: atom(),
          method :: atom(),
          args = [] :: list(any())
         }).


%% ===================================================================
%% APIs
%% ===================================================================
-spec(start_link([]) ->
             {ok, pid()} | {error, term()}).
start_link(_) ->
    gen_server:start_link(?MODULE, [], []).

stop(ServerRef) ->
    gen_server:call(ServerRef, stop).


%%====================================================================
%% gen_server callbacks
%%====================================================================
init([]) ->
    State = #state{args = []},
    {ok, State}.

handle_call({in, Clock, Node, Mod, Method, Args},_From,_State) ->
    {reply, ok, #state{clock  = Clock,
                       node   = Node,
                       module = Mod,
                       method = Method,
                       args   = Args}};

handle_call({out, Clock}, _From, #state{clock = Clock,
                                       node   = Node,
                                       module = Mod,
                                       method = Method,
                                       args   = Args}) ->
    {reply, {ok, {Node, Mod, Method, Args}}, #state{}};

handle_call({out,_Clock}, _From,_State) ->
    {reply, {error, invalid_key}, #state{}};

handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

handle_call(_Request, _From, State) ->
    {reply, unknown_request, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ===================================================================
%% Inner Functions
%% ===================================================================
