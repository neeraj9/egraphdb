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
-module(egraph_reindexing_server).

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
          timeout_msec :: pos_integer(),
          shard_id :: non_neg_integer(),
          dbinfo = #{} :: map()
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
    Name = proplists:get_value(name, Opts),
    gen_server:start_link({local, Name}, ?MODULE, Opts, []).

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
    ShardId = proplists:get_value(shard_id, Opts),
    %%Ref = erlang:start_timer(TimeoutMsec, self(), tick),
    {ok,
     #state{timeout_msec = TimeoutMsec, shard_id = ShardId}}.
     %%#state{ref = Ref, timeout_msec = TimeoutMsec, shard_id = ShardId}}.

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
handle_call({refresh, DbInfo}, _From, #state{dbinfo = LocalDbInfo} = State) ->
    LocalVersion = maps:get(<<"version">>, LocalDbInfo, -1),
    ReceivedVersion = maps:get(<<"version">>, DbInfo),
    State2 = case ReceivedVersion >= LocalVersion of
                 true ->
                     work_sync(DbInfo, State);
                 false ->
                     %% ignore older event
                     State
             end,
    {reply, ok, State2};
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
handle_cast({refresh, DbInfo}, #state{dbinfo = LocalDbInfo} = State) ->
    lager:debug("DbInfo = ~p, State = ~p", [DbInfo, State]),
    LocalVersion = maps:get(<<"version">>, LocalDbInfo, -1),
    ReceivedVersion = maps:get(<<"version">>, DbInfo),
    State2 = case ReceivedVersion >= LocalVersion of
                 true ->
                     lager:debug("[~p >= ~p] DbInfo = ~p, LocalVersion = ~p",
                                 [ReceivedVersion, LocalVersion, DbInfo, LocalVersion]),
                     work_sync(DbInfo, State);
                 false ->
                     %% ignore older event
                     State
             end,
    {noreply, State2};
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
            #state{ref = _R, timeout_msec = _TimeoutMsec}
            = State) ->
    lager:debug(?LAGER_ATTRS, "[~p] ~p refreshing", [self(), ?MODULE]),
    %%process_tick(TimeoutMsec, State);
    {noreply, State};
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

work_sync(DbInfo, State) ->
     CallbackPid = self(),
     OldTrapExitFlag = erlang:process_flag(trap_exit, true),
     WorkerPid = erlang:spawn_link(fun() ->
                                           State2 = process_db_info(DbInfo, State),
                                           CallbackPid ! {ok, State2}
                                   end),
     %% infinitely wait for worker process
     State4 = work_sync_receive_result(WorkerPid, DbInfo, State),
     erlang:process_flag(trap_exit, OldTrapExitFlag),
     State4.

work_sync_receive_result(WorkerPid, DbInfo, State) ->
     %% infinitely wait for worker process
     LocalVersion = maps:get(<<"version">>, DbInfo, -1),
     receive
         {ok, State3} ->
             %% consume worker process exit message
             receive
                 {'EXIT', WorkerPid, _Msg} -> ok
             after 0 -> ok
             end,
             State3;
         {'$gen_cast', {refresh,
                        #{<<"version">> := ReceivedVersion} = _DbInfo2}
         } when ReceivedVersion =< LocalVersion ->
             work_sync_receive_result(WorkerPid, DbInfo, State);
         {'EXIT', WorkerPid, _Msg} ->
             State
     end.

%%-spec process_tick(TimeoutMsec :: pos_integer(),
%%                   State :: term()) -> {noreply, State :: term()}.
%%process_tick(TimeoutMsec, #state{shard_id = ShardId} = State) ->
    %% TODO
    %%case egraph_reindex_model:read_resource(ShardId) of
    %%    {ok, [DbInfo]} ->
    %%        process_db_info(DbInfo, State);
    %%    TableError ->
    %%        lager:debug("Cannot read from table, TableError = ~p", [TableError]),
    %%        ok
    %%end,
    %%Ref = erlang:start_timer(TimeoutMsec, self(), tick),
    %%{noreply, State#state{ref = Ref}}.


process_db_info(DbInfo, #state{shard_id = ShardId} = State) ->
    lager:debug("ShardId = ~p, DbInfo = ~p", [ShardId, DbInfo]),
    case maps:get(<<"is_reindexing">>, DbInfo, 0) of
        1 ->
            %% TODO: enable or continue if running already
            ReindexDetails = maps:get(<<"details">>, DbInfo),
            MaxDataUpdatedDatetime = egraph_util:convert_binary_to_datetime(
                                       maps:get(<<"max_data_updated_datetime">>, ReindexDetails)),
            MinDataUpdatedDatetime = egraph_util:convert_binary_to_datetime(
                                       maps:get(<<"min_data_updated_datetime">>, ReindexDetails)),
            ReindexingDataUpdatedDatetime = case maps:get(
                                        <<"reindexing_data_updated_datetime">>,
                                        ReindexDetails,
                                        undefined) of
                                                   undefined ->
                                                       MaxDataUpdatedDatetime;
                                                   ReindexDatetimeBin ->
                                                       egraph_util:convert_binary_to_datetime(
                                                         ReindexDatetimeBin)
                                               end,
            NumRowsPerRun = maps:get(<<"num_rows_per_run">>, ReindexDetails),
            case egraph_detail_model:search_resource(
                   ShardId,
                   previous,
                   ReindexingDataUpdatedDatetime,
                   MinDataUpdatedDatetime,
                   NumRowsPerRun) of
                {ok, Records} ->
                    %% {error,{1062,<<"23000">>,
                    %%         <<"Duplicate entry 'abc-zY&\\xE6\\xA9\\x13' for key 'PRIMARY'">>}}
                    %%
                    %% IMPORTANT: the records is in ascending order, so reverse it to get min
                    %%            datetime use lists:foldr/3
                    R = lists:foldr(fun(_E, error) ->
                                            error;
                                       (E, _AccIn) ->
                                        Details = maps:get(<<"details">>, E),
                                        Indexes = maps:get(<<"indexes">>, E, null),
                                        case egraph_detail_model:reindex_key(
                                               Details, Indexes) of
                                            [] ->
                                                maps:get(<<"updated_datetime">>, E);
                                            _ ->
                                                error
                                        end
                                end, ok, Records),
                    case R of
                        error ->
                            %% failed.
                            lager:error("Reindex failed, will retry again later"),
                            State;
                        LeastDatetimeBin ->
                            %% move ahead
                            %% NOTE: The leastDatetimeBin is used as-is, so next time
                            %% the same record 
                            LeastDatetime = egraph_util:convert_binary_to_datetime(LeastDatetimeBin),
                            NextLowerDatetime = qdate:to_date(qdate:add_seconds(-1, LeastDatetime)),
                            lager:debug("LeastDatetime = ~p, NextLowerDatetime = ~p", [LeastDatetime, NextLowerDatetime]),
                            UpdatedReindexDetails = ReindexDetails#{
                                                      <<"reindexing_data_updated_datetime">> => egraph_util:convert_datetime_to_binary(NextLowerDatetime)},
                            UpdatedDbInfo = DbInfo#{<<"details">> => UpdatedReindexDetails},
                            egraph_reindex_model:create(undefined, UpdatedDbInfo, []),
                            OldVersion = maps:get(<<"version">>, UpdatedDbInfo),
                            State#state{dbinfo = UpdatedDbInfo#{<<"version">> => OldVersion + 1}}
                    end;
                {error, not_found} ->
                    %% TODO mark done
                    UpdatedDbInfo = DbInfo#{<<"is_reindexing">> => 0},
                    egraph_reindex_model:create(undefined, UpdatedDbInfo, []),
                    OldVersion = maps:get(<<"version">>, UpdatedDbInfo),
                    State#state{dbinfo = UpdatedDbInfo#{<<"version">> => OldVersion + 1}};
                _ ->
                    %% temporary database error, so retry later
                    State
            end;
        _ ->
            %% TODO: no reindexing running
            State
    end.

