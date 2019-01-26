%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%%
%%% @end
%%%
%%% %CopyrightBegin%
%%%
%%% Copyright Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in> 2017.
%%% All Rights Reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% %CopyrightEnd%
%%%-------------------------------------------------------------------
-module(egraph_metacache_server).

-behaviour(gen_server).

-include("egraph_constants.hrl").

%% API
-export([start_link/1]).
-ignore_xref([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-export([latest_compression/0]).

-define(SERVER, ?MODULE).
-define(LAGER_ATTRS, [{type, reindex_server}]).

-record(state, {
          ref = undefined :: reference(),
          timeout_msec :: pos_integer(),
          latest_compression_id :: undefined | non_neg_integer()
         }).

%%%===================================================================
%%% API
%%%===================================================================

-spec latest_compression() -> undefined | {integer(), binary()}.
latest_compression() ->
    case egraph_fast_write_store:read(dict_latest) of
        {ok, Value} ->
            Value;
        _ ->
            %% wait for egraph_metacache_server actor to update
            %% compression dictionary from database if configured.
            %% In case there is no compression dictionary configured
            %% then there is no point in refreshing from database
            %% anyways (each time).
            undefined
    end.

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Opts :: list()) -> {ok, Pid} | ignore | {error, Reason}
%% @end
%%--------------------------------------------------------------------
start_link(Opts) ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init(Opts) ->
    TimeoutMsec = proplists:get_value(
                    timeout_msec,
                    Opts,
                    ?DEFAULT_METACACHE_SERVER_TIMEOUT_MSEC),
    lager:debug("TimeoutMsec = ~p", [TimeoutMsec]),
    Ref = erlang:start_timer(TimeoutMsec, self(), tick),
    {ok,
     #state{ref = Ref, timeout_msec = TimeoutMsec,
            latest_compression_id = undefined}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info({timeout, _R, tick},
            #state{ref = _R,
                   timeout_msec = TimeoutMsec,
                   latest_compression_id = CompressionId}
            = State) ->
    lager:debug(?LAGER_ATTRS, "[~p] ~p tick", [self(), ?MODULE]),
    case egraph_dictionary_model:read_max_resource() of
        {ok, M} ->
            #{ <<"id">> := Key,
               <<"dictionary">> := Dictionary } = M,
            case Key of
                CompressionId -> ok;
                _ ->
                    egraph_fast_write_store:create_or_update(dict_latest, {Key, Dictionary}),
                    egraph_zlib_util:load_dicts([{Key, Dictionary}])
            end,
            Ref = erlang:start_timer(TimeoutMsec, self(), tick),
            {noreply, State#state{latest_compression_id = Key, ref = Ref}};
        _ ->
            Ref = erlang:start_timer(TimeoutMsec, self(), tick),
            {noreply, State#state{ref = Ref}}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================


