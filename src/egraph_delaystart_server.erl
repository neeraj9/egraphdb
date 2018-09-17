%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%%
%%% Starting additional services with certain guarantees
%%% is very important. This server ensures that the
%%% services are started consistently initially.
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
-module(egraph_delaystart_server).

-behaviour(gen_server).

-include("egraph_constants.hrl").

%% API
-export([start_link/1]).
-ignore_xref([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).
-define(LAGER_ATTRS, [{type, delayed_startup}]).

-record(state, {
          ref = undefined :: reference(),
          retry_timeout_msec :: pos_integer(),
          callback :: undefined | {M :: atom(), A :: atom(), Args :: list()},
          remaining_palma_pools = [] :: list()
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
                    retry_timeout_msec,
                    Opts,
                    ?DEFAULT_DELAYED_STARTUP_RETRY_TIMEOUT_MSEC),
    Callback = proplists:get_value(callback, Opts, undefined),
    {ok,
     #state{retry_timeout_msec = TimeoutMsec, callback = Callback},
     TimeoutMsec}.

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
            #state{ref = _R, retry_timeout_msec = TimeoutMsec,
                   remaining_palma_pools = RemainingPalmaPools}
            = State) ->
    lager:debug(?LAGER_ATTRS,
                "[~p] ~p retrying delayed startup for palma pools ~p",
                [self(), ?MODULE, RemainingPalmaPools]),
    process_tick(TimeoutMsec, RemainingPalmaPools, State);
handle_info(timeout, State = #state{retry_timeout_msec = TimeoutMsec}) ->
    %% create jobs
    Jobs = application:get_env(?APPLICATION_NAME, jobs, []),
    lists:foreach(fun(Job) ->
                          {M, F, A, SpecOnly} = Job,
                          JobSpec = {SpecOnly, {M, F, A}},
                          JobRefCreated = erlcron:cron(JobSpec),
                          lager:info(?LAGER_ATTRS, "[~p] ~p Added JobSpec = ~p, with Ref = ~p",
                                     [self(), ?MODULE, JobSpec, JobRefCreated]),
                          %% crash when job reference is not created
                          true = erlang:is_binary(JobRefCreated)
                  end, Jobs),
    %% create palma pools
    {ok, PalmaPools} = application:get_env(?APPLICATION_NAME, palma_pools),
    lager:debug(?LAGER_ATTRS, "[~p] ~p delayed startup for palma pools ~p",
                [self(), ?MODULE, PalmaPools]),
    process_tick(TimeoutMsec, PalmaPools, State);
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

delayed_palma_pool_setup(PalmaPools) ->
    PalmaPoolStartResult = lists:foldl(fun(E, AccIn) ->
        {PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec,
         RevolverOptions} = E,
        lager:info(?LAGER_ATTRS, "[~p] ~p Starting PalmaPool = ~p",
                   [self(), ?MODULE, E]),
        R = try
                palma:new(PoolName, PoolSize, PoolChildSpec, ShutdownDelayMsec,
                          RevolverOptions)
            catch
                C:ErrorReason ->
                    {error, {exception, {C, ErrorReason}}}
            end,
        case R of
            {ok, _} ->
                AccIn;
            Error2 ->
                lager:error(?LAGER_ATTRS, "[~p] ~p Entry = ~p, Error = ~p",
                            [self(), ?MODULE, E, Error2]),
                [E | AccIn]
        end
                 end, [], PalmaPools),
    case PalmaPoolStartResult of
        [] ->
            lager:info("[~p] ~p delayed startup complete", [self(), ?MODULE]),
            ok;
        _ ->
            %% TODO palma pool starts pool although the worker failed to start
            %% so stop them manually here till its fixed in palma library.
            lists:foreach(
              fun(E) ->
                      {PoolName, _, _, _, _} = E,
                      palma:stop(PoolName)
              end, PalmaPoolStartResult),
            ok
    end,
    PalmaPoolStartResult.

-spec process_tick(TimeoutMsec :: pos_integer(),
                   RemainingPalmaPools :: list(),
                   State :: term()) -> {noreply, State :: term()}.
process_tick(TimeoutMsec, RemainingPalmaPools, State) ->
    RemainingPalmaPools2 = delayed_palma_pool_setup(RemainingPalmaPools),
    case RemainingPalmaPools2 of
        [] ->
            {noreply, State#state{ref = undefined, remaining_palma_pools = []}};
        _ ->
            Ref = erlang:start_timer(TimeoutMsec, self(), tick),
            {noreply, State#state{ref = Ref,
                                  remaining_palma_pools = RemainingPalmaPools2}}
    end.

