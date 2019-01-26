%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2017, Neeraj Sharma
%%% @doc
%%% Enable publishing events in a transactional manner, where
%%% when the parent process (which must be sending events
%%% to this node) without explicitly calling send messages
%%% the events are logged for debugging (but not sent out).
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
-module(egraph_sysmon_server).

-behaviour(gen_server).

-include("egraph_constants.hrl").

%% API
-export([start_link/0]).
-ignore_xref([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          ref :: reference(),
          interval = 1000 :: pos_integer(),
          vm_metrics = [] :: list(),
          prefix = [<<"sm.">>]:: [binary()],
          archived_counters = #{}
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Reason}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

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
init([]) ->
    case application:get_env(?APPLICATION_NAME, sysmon) of
        {ok, SysmonConfig} ->
            Interval = proplists:get_value(interval, SysmonConfig),
            %% Using scheduler_wall_time to calculate scheduler-utilization
            erlang:system_flag(scheduler_wall_time, true),
            Ts0 = lists:sort(erlang:statistics(scheduler_wall_time)),
            {ok, #state{interval = Interval,
                archived_counters = #{scheduler => Ts0}},
                0};
        _ -> {ok, #state{}}
    end.

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
            #state{ref = _R, interval = FlushInterval,
                   vm_metrics = VMSpec, prefix = Prefix,
                   archived_counters = ArchivedCounters}
            = State) ->
    UpdatedArchivedCounters = do_vm_metrics(
        Prefix, VMSpec, ArchivedCounters),
    do_http_metrics(Prefix),
    do_nstat_metrics(Prefix),
    Ref = erlang:start_timer(FlushInterval, self(), tick),
    {noreply, State#state{ref = Ref,
                          archived_counters = UpdatedArchivedCounters}};

handle_info(timeout, State = #state{interval = Interval}) ->
    {ok, {vm_metrics, VMMetrics}} = get_sysmon_vm_metrics(),
    Ref = erlang:start_timer(Interval, self(), tick),
    {noreply, State#state{ref = Ref, vm_metrics = VMMetrics}};
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


do_http_metrics(Prefix) ->
    try
        EgraphListenerActiveConnections = ranch_server:count_connections(http),
        egraph_log_utils:publish_gauge(
          iolist_to_binary(
            [Prefix, <<"http.egraph_listener.active_connections">>]),
          EgraphListenerActiveConnections),
        lager:debug("[~p] ~p Active Connections = ~p",
                    [self(), ?MODULE, EgraphListenerActiveConnections])
    catch
        C:E  ->
            lager:error("[~p] ~p http metric failed ~p ~p",
                        [self(), ?MODULE, C, E]),
            ok
    end,
    ok.

%% Publish network statistics via the nstat application
%% which must be already installed in your system.
-spec do_nstat_metrics(Prefix :: binary()) -> ok.
do_nstat_metrics(Prefix) ->
    try
        Output = os:cmd("nstat --json"),
        Info = jiffy:decode(list_to_binary(Output), [return_maps]),
        maps:fold(fun(K, V, AccIn) ->
                          Metric = iolist_to_binary(
                                     [Prefix, <<"kernel.net.">>, K]),
                          egraph_log_utils:publish_gauge(Metric, V),
                          %% [{Metric, V} | AccIn]
                          AccIn
                  end, [], maps:get(<<"kernel">>, Info))
    catch
        C:E  ->
            lager:error("net metric failed ~p ~p", [C, E]),
            ok
    end,
    ok.

do_vm_metrics(_Prefix, [], ArchivedCounters) ->
    ArchivedCounters;
do_vm_metrics(Prefix, [{cpu, avg1}|Spec], ArchivedCounters) ->
    Value = cpu_sup:avg1() / 256,
    egraph_log_utils:publish_gauge(iolist_to_binary([Prefix, <<"cpu.avg1">>]), Value),
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [{cpu, avg5}|Spec], ArchivedCounters) ->
    Value = cpu_sup:avg5() / 256,
    egraph_log_utils:publish_gauge(iolist_to_binary([Prefix, <<"cpu.avg5">>]), Value),
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [{cpu, avg15}|Spec], ArchivedCounters) ->
    Value = cpu_sup:avg5() / 256,
    egraph_log_utils:publish_gauge(iolist_to_binary([Prefix, <<"cpu.avg15">>]), Value),
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [{cpu, util}|Spec], ArchivedCounters) ->
    cpu_sup:nprocs(),
    case cpu_sup:util([detailed, per_cpu]) of
        CpuUtilization when is_list(CpuUtilization) ->
            lists:foreach(fun(E) ->
                {CpuNum, Busy, _, _} = E,
                lists:foreach(fun(Field) ->
                    {F, V} = Field,
                    Name = iolist_to_binary(
                             [Prefix, <<"cpu.">>, integer_to_binary(CpuNum),
                              <<".">>, atom_to_binary(F, utf8)]),
                    egraph_log_utils:publish_gauge(Name, V)
                              end, Busy)
                          end, CpuUtilization),
            %% Compute cumulative cpu utilization and publish that as well
            CumulativeCpuUtil = lists:foldl(fun(E, AccIn) ->
                {_CpuNum, Busy, _, _} = E,
                lists:foldl(fun(Field, A) ->
                    {F, V} = Field,
                    case maps:get(F, A, undefined) of
                        undefined -> A#{F => V};
                        OldVal -> A#{F => (OldVal + V)}
                    end
                            end, AccIn, Busy)
                                            end, #{}, CpuUtilization),
            Ncpu = length(CpuUtilization),
            maps:fold(fun(K, V, _) ->
                Name = iolist_to_binary(
                         [Prefix, <<"cpu.total.">>, atom_to_binary(K, utf8)]),
                egraph_log_utils:publish_gauge(Name, V / Ncpu)
                      end, undefined, CumulativeCpuUtil),
            CumulativeCpuBusy = maps:fold(fun(_K, V, OldVal) ->
                OldVal + V
                                          end, 0, CumulativeCpuUtil),
            Name = iolist_to_binary([Prefix, <<"cpu.total">>]),
            egraph_log_utils:publish_gauge(Name, CumulativeCpuBusy / Ncpu);
        _ -> ok
    end,
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [{io, all}|Spec], ArchivedCounters) ->
    TotalIo = erlang:statistics(io),
    {{input, InputBytes}, {output, OutputBytes}} = TotalIo,
    Ninput = iolist_to_binary([Prefix, <<"vm.io.in">>]),
    InputDeltaCount = case maps:get(Ninput, ArchivedCounters, undefined) of
                          undefined -> InputBytes;
                          InputOldCount -> InputBytes - InputOldCount
                      end,
    egraph_log_utils:publish_gauge(Ninput, InputDeltaCount),
    Noutput = iolist_to_binary([Prefix, <<"vm.io.out">>]),
    OutputDeltaCount = case maps:get(Noutput, ArchivedCounters, undefined) of
                           undefined -> OutputBytes;
                           OutputOldCount -> OutputBytes - OutputOldCount
                       end,
    egraph_log_utils:publish_gauge(Noutput, OutputDeltaCount),
    UpdatedArchivedCounters = ArchivedCounters#{
        Ninput => InputBytes,
        Noutput => OutputBytes
    },
    do_vm_metrics(Prefix, Spec, UpdatedArchivedCounters);
do_vm_metrics(Prefix, [{scheduler, util}|Spec], ArchivedCounters) ->
    %% erlang:statistics(scheduler_wall_time)
    Ts0 = maps:get(scheduler, ArchivedCounters),
    Ts1 = lists:sort(erlang:statistics(scheduler_wall_time)),
    PerSchedulerDelta = lists:map(fun({{I, A0, T0}, {I, A1, T1}}) ->
        {I, (A1 - A0)/(T1 - T0)} end, lists:zip(Ts0, Ts1)),
    lists:foreach(fun(E) ->
        {Id, Percent} = E,
        N = iolist_to_binary(
              [Prefix, <<"vm.scheduler.">>, integer_to_binary(Id)]),
        %%lager:info("SchId=~p, Percent=~p", [N, Percent * 100]),
        egraph_log_utils:publish_gauge(N, Percent * 100)
                  end, PerSchedulerDelta),
    {A, T} = lists:foldl(fun({{_, A0, T0}, {_, A1, T1}}, {Ai, Ti}) ->
        {Ai + (A1 - A0), Ti + (T1 - T0)} end, {0, 0}, lists:zip(Ts0, Ts1)),
    TotalSchedulerUtilization = A/T,
    %%lager:info("TotalSchedulerUtilization=~p",
    %%[TotalSchedulerUtilization * 100]),
    egraph_log_utils:publish_gauge(
      iolist_to_binary(
        [Prefix, <<"vm.scheduler.total">>]), TotalSchedulerUtilization * 100),
    UpdatedArchivedCounters = ArchivedCounters#{scheduler => Ts1},
    do_vm_metrics(Prefix, Spec, UpdatedArchivedCounters);
do_vm_metrics(Prefix, [{run_queue, all}|Spec], ArchivedCounters) ->
    %% also use erlang:statistics(run_queue_lengths) for individual
    %% run queues per scheduler
    %% Note that run_queue_lengths is also efficient

    %% run_queue is more expensive, so dont use it
    Value = erlang:statistics(total_run_queue_lengths),
    N = iolist_to_binary([Prefix, <<"vm.run_queue">>]),
    egraph_log_utils:publish_gauge(N, Value),
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [{memory, Type}|Spec], ArchivedCounters) ->
    Value = erlang:memory(Type),
    N = iolist_to_binary(
          [Prefix, <<"vm.memory.">>, atom_to_binary(Type, utf8)]),
    egraph_log_utils:publish_gauge(N, Value),
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [{disk, all} | Spec], ArchivedCounters) ->
    DiskData = disksup:get_disk_data(),
    case DiskData of
        [{"none", 0, 0}] -> ok;
        _ ->
            lists:foreach(fun({DevName, _TotalBytes, UsedPercent}) ->
                Tokens = string:tokens(DevName, "/"),
                ShouldPublish = case Tokens of
                                    ["run", "user", "1000"] ->
                                        %% 1000 is for ubuntu (standard user)
                                        true;
                                    ["run", "user" | _] ->
                                        false;
                                    _ ->
                                        true
                                end,
                case ShouldPublish of
                    true ->
                        PathName = case Tokens of
                                       [] -> "ROOT";
                                       _ ->
                                           list_to_binary(
                                             string:join(Tokens, "~"))
                                   end,
                        N = iolist_to_binary(
                              [Prefix, <<"disk.used_percent.">>, PathName]),
                        Value = UsedPercent,
                        egraph_log_utils:publish_gauge(N, Value);
                    false ->
                        ok
                end
                end,
                DiskData)
    end,
    do_vm_metrics(Prefix, Spec, ArchivedCounters);
do_vm_metrics(Prefix, [_|Spec], ArchivedCounters) ->
    do_vm_metrics(Prefix, Spec, ArchivedCounters).


%% @private get sysmon vm_metrics configuration
-spec get_sysmon_vm_metrics() -> {ok, {vm_metrics, list()}}.
get_sysmon_vm_metrics() ->
    VMMetrics = case application:get_env(?APPLICATION_NAME, sysmon) of
                    {ok, SysmonConfig} ->
                        proplists:get_value(vm_metrics, SysmonConfig, []);
                    _ ->
                        []
                end,
    {ok, {vm_metrics, VMMetrics}}.
