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
-module(egraph_folsom_graphite_server).

-behaviour(gen_server).

-include("egraph_constants.hrl").

%% API
-export([start_link/1]).
-ignore_xref([start_link/1]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {
          host :: undefined,
          port :: undefined | pos_integer(),
          bucket :: binary(),
          dimensions :: [{atom(), atom() | binary()}, ...],
          ref :: reference(),
          sock = undefined,
          interval = 1000 :: pos_integer(),
          vm_metrics = [] :: list(),
          archived_counters = #{},
          folsom_table_prefixes :: [binary()]
         }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link(Index) -> {ok, Pid} | ignore | {error, DDBrror}
%% @end
%%--------------------------------------------------------------------
start_link(Index) ->
    lager:info("Index=~p", [Index]),
    {ok, FolsomDdbConfig} = application:get_env(?APPLICATION_NAME, folsom_graphite),
    lager:info("FolsomDdbConfig=~p", [FolsomDdbConfig]),
    FolsomDdbBuckets = proplists:get_value(buckets, FolsomDdbConfig),
    BucketIndexConfig = lists:nth(Index, FolsomDdbBuckets),
    Name = proplists:get_value(name, BucketIndexConfig),
    lager:info("starting actor ~p", [Name]),
    gen_server:start_link({local, Name}, ?MODULE, [FolsomDdbConfig, BucketIndexConfig], []).

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
init([FolsomDdbConfig, BucketIndexConfig]) ->
    lager:info("init(~p, ~p)", [FolsomDdbConfig, BucketIndexConfig]),
    process_flag(trap_exit, true),
    case proplists:get_value(enabled, FolsomDdbConfig, false) of
        true ->
            {Host, Port} = proplists:get_value(endpoint, FolsomDdbConfig),
            BucketSuffix = proplists:get_value(bucket_suffix, FolsomDdbConfig, ""),
            BucketS = proplists:get_value(bucket, BucketIndexConfig),
            Bucket = egraph_util:convert_to_binary(BucketS ++ BucketSuffix),
            DimensionsConfig = proplists:get_value(dimensions, BucketIndexConfig),
            %% Note that dimensions are order sensitive, so sort
            %% then for uniqueness and any mistakes while configuring the order.
            SortedDimensions = lists:keysort(1, DimensionsConfig),
            SelfNodeNameBin = binary:replace(atom_to_binary(node(), utf8), <<".">>, <<"-">>, [global]),
            Dimensions = lists:foldr(fun({K, V}, AccIn) ->
                case {K, V} of
                    {node, node} ->
                        [iolist_to_binary([atom_to_binary(K, utf8), <<"=">>, SelfNodeNameBin]) | AccIn];
                    {node, NodeName} ->
                        [iolist_to_binary([atom_to_binary(K, utf8), <<"=">>, NodeName]) | AccIn];
                    _ ->
                        [iolist_to_binary([atom_to_binary(K, utf8), <<"=">>, V]) | AccIn]
                end
                end, [], SortedDimensions),
            Interval = proplists:get_value(interval, BucketIndexConfig),
            TablePrefixes = proplists:get_value(folsom_table_prefixes, BucketIndexConfig),

            State = #state{interval = Interval, dimensions = Dimensions, bucket = Bucket,
                vm_metrics = [], host = Host, port = Port,
                folsom_table_prefixes = TablePrefixes},
            Ref = erlang:start_timer(Interval, self(), tick),
            case connect(Host, Port, Bucket, Interval) of
                {ok, Sock} ->
                    {ok, State#state{sock = Sock, ref = Ref}};
                {error, Reason} ->
                    erlang:throw({error, Reason})
            end;
        false -> {ok, #state{}}
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
            #state{ref = _R, interval = Interval, sock = Sock,
                   host = _Host, port = _Port, bucket = _Bucket,
                   vm_metrics = VMSpec, dimensions = Dimensions,
                   archived_counters = ArchivedCounters,
                   folsom_table_prefixes = TablePrefixes}
            = State) ->

    {UpdatedArchivedCounters, Sock1} = aggregate_and_send_metrics(
        Sock, Dimensions, VMSpec, ArchivedCounters, TablePrefixes),
%%    {MicroSec, {UpdatedArchivedCounters, DDB4}} = timer:tc(fun aggregate_and_send_metrics/4,
%%        [DDB, Prefix, VMSpec, ArchivedCounters]),
%%    lager:debug("Elapsed ~p msec to collect and send metrics", [MicroSec / 1000]),
    Ref = erlang:start_timer(Interval, self(), tick),
    {noreply, State#state{ref = Ref, sock = Sock1, archived_counters = UpdatedArchivedCounters}};
handle_info({TcpEvent, _Socket}, State = #state{
    sock = Sock, host = Host, port = Port, interval = Interval, bucket = Bucket})
    when TcpEvent == tcp_closed orelse TcpEvent == tcp_error ->
    %% TODO: validate that the socket is indeed of DDB
    gen_tcp:close(Sock),  %% just in case
    case connect(Host, Port, Bucket, Interval) of
        {ok, Sock1} ->
            %% Timer is already running, so do not touch that
            %% Ref = erlang:start_timer(Interval, self(), tick),
            {noreply, State#state{sock = Sock1}};
        {error, Reason} ->
            erlang:throw({error, Reason})
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
terminate(_Reason, #state{sock = undefined}) ->
    ok;
terminate(_Reason, #state{sock = Socket}) ->
    gen_tcp:close(Socket),
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, DDBxtra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _DDBxtra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

aggregate_and_send_metrics(Sock, Dimensions, VMSpec, ArchivedCounters, TablePrefixes) ->
    {ArchivedCounters2, Socket1} = do_vm_metrics(Dimensions, VMSpec, ArchivedCounters, Sock),
    Spec = folsom_metrics:get_metrics_info(),
    {UpdatedArchivedCounters, Socket2} = do_metrics(Dimensions, Spec, ArchivedCounters2, TablePrefixes, Socket1),
    {UpdatedArchivedCounters, Socket2}.

do_vm_metrics(_Dimensions, [], ArchivedCounters, Socket) ->
    {ArchivedCounters, Socket};
do_vm_metrics(Dimensions, [_|Spec], ArchivedCounters, Socket) ->
    do_vm_metrics(Dimensions, Spec, ArchivedCounters, Socket).


do_metrics(Dimensions, [{N, [{type, histogram} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    Socket1 = case is_metric_in_table_prefix(N, TablePrefixes) of
               {true, _TablePrefix} ->
                   Hist = folsom_metrics:get_histogram_statistics(N),
                   %%lager:info("N=~p, Hist=~p", [N, Hist]),
                   %% publish histogram metrics only when some minimum samples exist
                   case proplists:get_value(n, Hist) of
                       0 ->
                           Socket;
                       0.0 ->
                           Socket;
                       Count when Count > 0 ->
                           case folsom_metric_to_parts(metric_name(N)) of
                               undefined ->
                                   Socket;
                               {Prefix, Suffix} ->
                                   build_histogram(Hist,
                                       Prefix, Suffix ++ Dimensions, Socket)
                           end
                   end;
               {false, _} ->
                   %%lager:warning("histogram: N=~p not in TablePrefixes=~p", [N, TablePrefixes]),
                   Socket
    end,
    case Socket1 of
        undefined ->
            {ArchivedCounters, Socket};
        _ ->
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket1)
    end;

do_metrics(Dimensions, [{N, [{type, spiral} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    Socket1 = case is_metric_in_table_prefix(N, TablePrefixes) of
               {true, _TablePrefix} ->
                   [{count, Count}, {one, One}] = folsom_metrics:get_metric_value(N),
                   case folsom_metric_to_parts(metric_name(N)) of
                       undefined ->
                           Socket;
                       {Prefix, Suffix} ->
                           send([{[Prefix, <<"count">>, Suffix, Dimensions], Count},
                               {[Prefix, <<"one">>, Suffix, Dimensions], One}], Socket)
                   end;
               {false, _} ->
                   %%lager:warning("spiral: N=~p not in TablePrefixes=~p", [N, TablePrefixes]),
                   Socket
           end,
    case Socket1 of
        undefined ->
            {ArchivedCounters, Socket};
        _ ->
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket1)
    end;

do_metrics(Dimensions,
           [{N, [{type, counter} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    case is_metric_in_table_prefix(N, TablePrefixes) of
        {true, _TablePrefix} ->
            Count = folsom_metrics:get_metric_value(N),
            DeltaCount = case maps:get(N, ArchivedCounters, undefined) of
                             undefined -> Count;
                             OldCount -> Count - OldCount
                         end,
            %% io:format("[DDB] DeltaMetrics(~p) = ~p, Metrics(~p) = ~p~n", [N, DeltaCount, N, Count]),
            %% only send when there is a change, else ddb will automatically
            %% mark them as null (or 0 or 0.0)
            Socket1 = case DeltaCount of
                       0 -> Socket;
                       0.0 -> Socket;
                       _ ->
                           case folsom_metric_to_parts(metric_name(N)) of
                               undefined ->
                                   Socket;
                               {Prefix, Suffix} ->
                                   send([Prefix, Suffix, Dimensions], DeltaCount, Socket)
                           end
                   end,
            case Socket1 of
                undefined ->
                    {ArchivedCounters, Socket};
                _ ->
                    do_metrics(Dimensions, Spec, ArchivedCounters#{N => Count}, TablePrefixes, Socket1)
            end;
        {false, _} ->
            %%lager:warning("counter: N=~p not in TablePrefixes=~p", [N, TablePrefixes]),
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket)
    end;


%% TODO: revert the network optimization which I did earlier
%% now with replace_below_confidence() in ddb

%% TODO: Start publishing bm and sm metrics at global key as well
%% which will then be automatically aggregated by ddb and shown
%% as such. Additionally create a key "sm.n" which will indicate
%% total number of aggregating parties and each of the node
%% shall push a value of 1, so that it gives the count of
%% nodes within the application cluster. This key must be
%% updated all the time for accurate count.

%% TODO: can grafana request different resolution from ddb-fe other
%% than 1 second which is the default?

do_metrics(Dimensions,
           [{N, [{type, gauge} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    Socket1 = case is_metric_in_table_prefix(N, TablePrefixes) of
               {true, _TablePrefix} ->
                   Count = folsom_metrics:get_metric_value(N),
                   case folsom_metric_to_parts(metric_name(N)) of
                       undefined ->
                           Socket;
                       {Prefix, Suffix} ->
                           send([Prefix, Suffix, Dimensions], Count, Socket)
                   end;
               {false, _} ->
                   %%lager:warning("gauge: N=~p not in TablePrefixes=~p", [N, TablePrefixes]),
                   Socket
           end,
    case Socket1 of
        undefined ->
            {ArchivedCounters, Socket};
        _ ->
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket1)
    end;

do_metrics(Dimensions,
           [{N, [{type, duration} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    Socket1 = case is_metric_in_table_prefix(N, TablePrefixes) of
               {true, _TablePrefix} ->
                   case folsom_metric_to_parts(metric_name(N)) of
                       undefined ->
                           Socket;
                       {Prefix, Suffix} ->
                           build_histogram(folsom_metrics:get_metric_value(N),
                               Prefix, Suffix ++ Dimensions, Socket)
                   end;
               {false, _} -> Socket
           end,
    case Socket1 of
        undefined ->
            {ArchivedCounters, Socket};
        _ ->
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket1)
    end;

do_metrics(Dimensions,
           [{N, [{type, meter} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    Socket1 = case is_metric_in_table_prefix(N, TablePrefixes) of
               {true, _TablePrefix} ->
                   Scale = 1000*1000,
                   [{count, Count},
                       {one, One},
                       {five, Five},
                       {fifteen, Fifteen},
                       {day, Day},
                       {mean, Mean},
                       {acceleration,
                           [{one_to_five, OneToFive},
                               {five_to_fifteen, FiveToFifteen},
                               {one_to_fifteen, OneToFifteen}]}]
                       = folsom_metrics:get_metric_value(N),
                   case folsom_metric_to_parts(metric_name(N)) of
                       undefined ->
                           Socket;
                       {Prefix, Suffix} ->
                           send([{[Prefix, <<"count">>, Suffix, Dimensions], Count},
                               {[Prefix, <<"one">>, Suffix, Dimensions], round(One*Scale)},
                               {[Prefix, <<"five">>, Suffix, Dimensions], round(Five*Scale)},
                               {[Prefix, <<"fifteen">>, Suffix, Dimensions], round(Fifteen*Scale)},
                               {[Prefix, <<"day">>, Suffix, Dimensions], round(Day*Scale)},
                               {[Prefix, <<"mean">>, Suffix, Dimensions], round(Mean*Scale)},
                               {[Prefix, <<"one_to_five">>, Suffix, Dimensions], round(OneToFive*Scale)},
                               {[Prefix, <<"five_to_fifteen">>, Suffix, Dimensions], round(FiveToFifteen*Scale)},
                               {[Prefix, <<"one_to_fifteen">>, Suffix, Dimensions], round(OneToFifteen*Scale)}],
                               Socket)
                   end;
               {false, _} -> Socket
           end,
    case Socket1 of
        undefined ->
            {ArchivedCounters, Socket};
        _ ->
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket1)
    end;

do_metrics(Dimensions,
           [{N, [{type, meter_reader} | _]} | Spec], ArchivedCounters, TablePrefixes, Socket) ->
    Socket1 = case is_metric_in_table_prefix(N, TablePrefixes) of
               {true, _TablePrefix} ->
                   Scale = 1000*1000,
                   [{one, One},
                       {five, Five},
                       {fifteen, Fifteen},
                       {mean, Mean},
                       {acceleration,
                           [{one_to_five, OneToFive},
                               {five_to_fifteen, FiveToFifteen},
                               {one_to_fifteen, OneToFifteen}]}]
                       = folsom_metrics:get_metric_value(N),
                   case folsom_metric_to_parts(metric_name(N)) of
                       undefined ->
                           Socket;
                       {Prefix, Suffix} ->
                           send([{[Prefix, <<"one">>, Suffix, Dimensions], round(One*Scale)},
                               {[Prefix, <<"five">>, Suffix, Dimensions], round(Five*Scale)},
                               {[Prefix, <<"fifteen">>, Suffix, Dimensions], round(Fifteen*Scale)},
                               {[Prefix, <<"mean">>, Suffix, Dimensions], round(Mean*Scale)},
                               {[Prefix, <<"one_to_five">>, Suffix, Dimensions], round(OneToFive*Scale)},
                               {[Prefix, <<"five_to_fifteen">>, Suffix, Dimensions], round(FiveToFifteen*Scale)},
                               {[Prefix, <<"one_to_fifteen">>, Suffix, Dimensions], round(OneToFifteen*Scale)}],
                               Socket)
                   end;
               {false, _} -> Socket
           end,
    case Socket1 of
        undefined ->
            {ArchivedCounters, Socket};
        _ ->
            do_metrics(Dimensions, Spec, ArchivedCounters, TablePrefixes, Socket1)
    end;

do_metrics(_Dimensions, [], ArchivedCounters, _TablePrefixes, Socket) ->
    {ArchivedCounters, Socket}.

build_histogram([], _, _, Socket) ->
    Socket;

%%build_histogram([{min, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"min">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{max, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"max">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{arithmetic_mean, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"arithmetic_mean">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{geometric_mean, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"geometric_mean">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{harmonic_mean, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"harmonic_mean">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{median, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"median">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{variance, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"variance">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{standard_deviation, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"standard_deviation">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{skewness, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"skewness">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);
%%
%%build_histogram([{kurtosis, V} | H], Prefix, Suffix, Socket) ->
%%    DDB1 = send([Prefix, <<"kurtosis">>, Suffix], round(V), Socket),
%%    build_histogram(H, Prefix, Suffix, Socket1);

build_histogram([{percentile, V} | H], Prefix, Suffix, Socket) ->
    %%lager:info("V=~p", [V]),
    %% [{50, P50}, {75, P75}, {95, P95}, {99, P99},
    %% {999, P999}] = V
    P95 = proplists:get_value(95, V),
    P99 = proplists:get_value(99, V),
    P999 = proplists:get_value(999, V),
    Socket1 = send([
                 %% {[Prefix, <<"p50">>, Suffix], round(P50)},
                 %% {[Prefix, <<"p75">>, Suffix], round(P75)},
                 {[Prefix, <<"p95">>, Suffix], round(P95)},
                 {[Prefix, <<"p99">>, Suffix], round(P99)},
                 {[Prefix, <<"p999">>, Suffix], round(P999)}], Socket),
    build_histogram(H, Prefix, Suffix, Socket1);

build_histogram([{n, V} | H], Prefix, Suffix, Socket) ->
    Socket1 = send([Prefix, <<"n">>, Suffix], V, Socket),
    build_histogram(H, Prefix, Suffix, Socket1);

build_histogram([_ | H], Prefix, Suffix, Socket) ->
    build_histogram(H, Prefix, Suffix, Socket).

metric_name(B) when is_binary(B) ->
    B;
metric_name(L) when is_list(L) ->
    erlang:list_to_binary(L);
metric_name(N1) when
    is_atom(N1) ->
    a2b(N1);
metric_name({N1, N2}) when
    is_atom(N1), is_atom(N2) ->
    [a2b(N1), a2b(N2)];
metric_name({N1, N2, N3}) when
    is_atom(N1), is_atom(N2), is_atom(N3) ->
    [a2b(N1), a2b(N2), a2b(N3)];
metric_name({N1, N2, N3, N4}) when
    is_atom(N1), is_atom(N2), is_atom(N3), is_atom(N4) ->
    [a2b(N1), a2b(N2), a2b(N3), a2b(N4)];
metric_name(T) when is_tuple(T) ->
    [metric_name(DDB) || DDB <- tuple_to_list(T)].

a2b(A) ->
    erlang:atom_to_binary(A, utf8).

send(MVs, Socket) ->
    MetricValues = lists:foldl(fun({Metric,Value}, AccIn)->
        Metric1 = iolist_to_binary(lists:join(<<".">>,lists:flatten(Metric))),
        MetricValue = list_to_binary(io_lib:format(
"~s ~p ~p~n", [Metric1, Value, egraph_util:get_utc_seconds()])),
        [MetricValue | AccIn]
                  end, [], MVs),
    case gen_tcp:send(Socket, iolist_to_binary(MetricValues)) of
        ok ->
            Socket;
        _ ->
            undefined
    end.

send(Metric, Value, Socket) when is_float(Value) ->
    %% send(Metric, round(Value), Socket);
    RoundedValue = round(Value * 100) / 100,
    Metric1 = iolist_to_binary(lists:join(<<".">>,lists:flatten(Metric))),
    ToSend = list_to_binary(io_lib:format(
"~s ~p ~p~n", [Metric1, RoundedValue, egraph_util:get_utc_seconds()])),
    case gen_tcp:send(Socket, ToSend) of
        ok ->
            Socket;
        _ ->
            undefined
    end;
send(Metric, Value, Socket) when is_integer(Value) ->
    Metric1 = iolist_to_binary(lists:join(<<".">>,lists:flatten(Metric))),
    ToSend = list_to_binary(io_lib:format(
"~s ~p ~p~n", [Metric1, Value, egraph_util:get_utc_seconds()])),
    case gen_tcp:send(Socket, ToSend) of
        ok ->
            Socket;
        _ ->
            undefined
    end.

is_metric_in_table_prefix(_N, []) ->
    {false, undefined};
is_metric_in_table_prefix(N, [H | Rest] = _TablePrefixes) ->
    HLen = byte_size(H),
    case N of
        <<H:HLen/binary, _/binary>> -> {true, H};
        _ -> is_metric_in_table_prefix(N, Rest)
    end.

connect(Host, Port, _Bucket, _Interval) ->
    gen_tcp:connect(Host, Port, [{keepalive, true}], 2000).

folsom_metric_to_parts(<<"api.", Rest/binary>>) ->
    Parts = binary:split(Rest, <<".">>, [global, trim]),
    case Parts of
        [Method, Model, Code, OrgUnit] ->
            {[?METRIC_PREFIX, <<"api">>, <<"count">>],
             [<<"method=", Method/binary>>, <<"model=", Model/binary>>,
              <<"ghttpcode=", Code/binary>>, <<"orgunit=", OrgUnit/binary>>]};
        [Method, Model, Code, <<"ms">>, OrgUnit] ->
            {[?METRIC_PREFIX, <<"api">>, <<"hist">>],
             [<<"method=", Method/binary>>, <<"model=", Model/binary>>,
              <<"ghttpcode=", Code/binary>>, <<"orgunit=", OrgUnit/binary>>]};
        _ ->
            undefined
    end;
folsom_metric_to_parts(<<"api-n.", Rest/binary>>) ->
    Parts = binary:split(Rest, <<".">>, [global, trim]),
    case Parts of
        [Method, Model, Code, OrgUnit] ->
            {[?METRIC_PREFIX, <<"api-n">>, <<"count">>],
             [<<"method=", Method/binary>>, <<"model=", Model/binary>>,
              <<"httpcode=", Code/binary>>, <<"orgunit=", OrgUnit/binary>>]};
        [Method, Model, Code, <<"ms">>, OrgUnit] ->
            {[?METRIC_PREFIX, <<"api-n">>, <<"hist">>],
             [<<"method=", Method/binary>>, <<"model=", Model/binary>>,
              <<"httpcode=", Code/binary>>, <<"orgunit=", OrgUnit/binary>>]};
        _ ->
            undefined
    end;
folsom_metric_to_parts(<<"sm.vm.memory.", Rest/binary>>) ->
    case Rest of
        <<"total">> ->
            undefined;
        _ ->
            {[?METRIC_PREFIX, <<"vm">>, <<"memory">>],
             [<<"mtype=", Rest/binary>>]}
    end;
folsom_metric_to_parts(<<"sm.vm.scheduler.", Rest/binary>>) ->
    case Rest of
        <<"total">> ->
            undefined;
        _ ->
            {[?METRIC_PREFIX, <<"vm">>, <<"scheduler">>],
             [<<"sid=", Rest/binary>>]}
    end;
folsom_metric_to_parts(<<"sm.vm.io.in">>) ->
    {[?METRIC_PREFIX, <<"vm">>, <<"io">>, <<"in">>], []};
folsom_metric_to_parts(<<"sm.vm.io.out">>) ->
    {[?METRIC_PREFIX, <<"vm">>, <<"io">>, <<"out">>], []};
folsom_metric_to_parts(<<"sm.vm.run_queue">>) ->
    {[?METRIC_PREFIX, <<"vm">>, <<"run_queue">>], []};
folsom_metric_to_parts(<<"sm.http.", Rest/binary>>) ->
    Parts = binary:split(Rest, <<".">>, [global, trim]),
    case Parts of
        [Ref, MetricName] ->
            %% sm.http.egraph_listener.active_connections
            {[?METRIC_PREFIX, <<"http">>, MetricName],
             [<<"ref=", Ref/binary>>]};
        _ ->
            undefined
    end;
folsom_metric_to_parts(<<"sm.kernel.net.", Rest/binary>>) ->
    Parts = binary:split(Rest, <<".">>, [global, trim]),
    case Parts of
        [MetricName] ->
            %% sm.kernel.net.UdpOutDatagrams
            {[?METRIC_PREFIX, <<"kernel">>, <<"net">>, MetricName], []};
        _ ->
            undefined
    end;
folsom_metric_to_parts(<<"sm.cpu.", Rest/binary>>) ->
    Parts = binary:split(Rest, <<".">>, [global, trim]),
    case Parts of
        [<<"avg1">>] ->
            %% sm.cpu.avg1
            {[?METRIC_PREFIX, <<"cpu">>, <<"avg1">>], []};
        [<<"avg5">>] ->
            %% sm.cpu.avg5
            {[?METRIC_PREFIX, <<"cpu">>, <<"avg5">>], []};
        [<<"avg15">>] ->
            %% sm.cpu.avg15
            {[?METRIC_PREFIX, <<"cpu">>, <<"avg15">>], []};
        [<<"total">>] ->
            %% sm.cpu.total
            undefined;
        [<<"total">>, _] ->
            undefined;
        [Id, Type] ->
            %% sm.cpu.0.kernel
            {[?METRIC_PREFIX, <<"cpu">>, <<"current">>],
             [<<"cid=", Id/binary>>, <<"ctype=", Type/binary>>]};
        _ ->
            undefined
    end;
folsom_metric_to_parts(<<"sm.disk.used_percent.", Rest/binary>>) ->
    {[?METRIC_PREFIX, <<"vm">>, <<"disk">>, <<"used_percent">>],
     [<<"path=", Rest/binary>>]};
folsom_metric_to_parts(<<"sm.redis.", Rest/binary>>) ->
    Parts = binary:split(Rest, <<".">>, [global, trim]),
    case Parts of
        [OperationType, PoolName, Result] ->
            {[?METRIC_PREFIX, <<"redis">>],
             [<<"redisop=", OperationType/binary>>, <<"pool=", PoolName/binary>>, <<"result=", Result/binary>>]}
    end;
folsom_metric_to_parts(<<"bm.api.up">>) ->
    {[?METRIC_PREFIX, <<"bm">>, <<"api">>, <<"up">>], []};
folsom_metric_to_parts(_) ->
    undefined.

