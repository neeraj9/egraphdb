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
-module(egraph_reindexing_master_server).

-behaviour(gen_server).

-include("egraph_constants.hrl").

%% API
-export([start_link/1]).
-ignore_xref([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(LAGER_ATTRS, [{type, reindex_server}]).

-record(state, {
          ref = undefined :: reference(),
          timeout_msec :: pos_integer()
         }).

%%%===================================================================
%%% API
%%%===================================================================

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
                    ?DEFAULT_REINDEXER_SERVER_TIMEOUT_MSEC),
    lager:debug("TimeoutMsec = ~p", [TimeoutMsec]),
    Ref = erlang:start_timer(TimeoutMsec, self(), tick),
    {ok,
     #state{ref = Ref, timeout_msec = TimeoutMsec}}.

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
            #state{ref = _R, timeout_msec = TimeoutMsec}
            = State) ->
    lager:debug(?LAGER_ATTRS, "[~p] ~p refreshing", [self(), ?MODULE]),
    process_tick(TimeoutMsec, State);
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

-spec process_tick(TimeoutMsec :: pos_integer(),
                   State :: term()) -> {noreply, State :: term()}.
process_tick(TimeoutMsec, State) ->
    MaxShards = trunc(math:pow(2, 11)) + 1,
    case egraph_reindex_model:read_all_resource(undefined, MaxShards, 0) of
        {ok, DbInfos, _} ->
            ActiveDbInfos = lists:filter(fun(E) -> maps:get(<<"is_reindexing">>, E, 0) == 1 end,
                                         DbInfos),
            InactiveDbInfos = lists:filter(fun(E) -> maps:get(<<"is_reindexing">>, E, 0) == 0 end,
                                           DbInfos),
            %% inform all inactive shards first
            lists:foreach(fun(E) ->
                                  ShardId = maps:get(<<"shard_id">>, E),
                                  Name = erlang:list_to_existing_atom(
                                           "egraph_reindexing_server_" ++ integer_to_list(ShardId)),
                                  gen_server:cast(Name, {refresh, E})
                          end, InactiveDbInfos),
            %% inform limited active shards because otherwise it will be too much
            %% for database to handle.
            LimitedActiveDbInfos = lists:sublist(
                                     ActiveDbInfos,
                                     egraph_config_util:reindex_max_shard_per_run()),
            lists:foreach(fun(E) ->
                                  ShardId = maps:get(<<"shard_id">>, E),
                                  Name = erlang:list_to_existing_atom(
                                           "egraph_reindexing_server_" ++ integer_to_list(ShardId)),
                                  gen_server:cast(Name, {refresh, E})
                          end, LimitedActiveDbInfos);
        {error, not_found} ->
            %% nothing yet
            ok;
        TableError ->
            lager:error("Cannot read from table, TableError = ~p",
                        [TableError]),
            ok
    end,
    Ref = erlang:start_timer(TimeoutMsec, self(), tick),
    {noreply, State#state{ref = Ref}}.


