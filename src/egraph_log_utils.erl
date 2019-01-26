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
-module(egraph_log_utils).
-export([create_log_req/2]).
-export([req_log/4]).
-export([publish_counter/2,
         publish_gauge/2,
         publish_histogram/2]).

-include("egraph_constants.hrl").


create_log_req(Req, Model) ->
    %% setup otter
    Method = cowboy_req:method(Req),
    RequestPath = cowboy_req:path(Req),
    QsVals = cowboy_req:qs(Req),
    otter_span_pdict_api:start({Method, Model}),
    otter_span_pdict_api:tag("node", node()),
    otter_span_pdict_api:log({path, RequestPath}),
    otter_span_pdict_api:log({qs_vals, QsVals}),
    HttpRestConfig = application:get_env(?APPLICATION_NAME,
                                         http_rest,
                                         []),
    IsLogEnabled = proplists:get_value(log_enabled, HttpRestConfig, false),
    Req#{log_enabled => IsLogEnabled,
         start_time => erlang:monotonic_time(millisecond),
         metrics_source => Model}.

%% @doc Request logs provided as a cowboy hook.
%%
%% Folsom metrics can be triggered by having the cowboy handler setting
%% a given `metrics_source' in the `meta' values of the `cowboy_req'
%% object. Counts for status codes returned will be accumulated.
%% If adding a `meta' value named `start_time', whose value is obtained
%% by calling `erlang:montonic_time(milli_seconds)',  time difference
%% calculation will be done between this time value and the end of the
%% response.
%%
%% By setting `log_enabled' to `true' in the `cowboy_req' `meta' object,
%% log lines for an HTTP status will be generated for each response.
req_log(Status, _Headers, _IoData, Req) ->
    FinalResult = http_status_to_otter_final_result(Status),
    otter_span_pdict_api:log({http_status, Status}),
    otter_span_pdict_api:tag("final_result", FinalResult),
    otter_span_pdict_api:finish(),
    Req1 = publish_metrics(Status, Req),
    Req2 = publish_req_logs(Status, Req1),
    Req2.

publish_metrics(Status, Req1) ->
    Type = http_status_to_metric_name(Status),
    publish_counter(Type, 1),
    case maps:get(metrics_source, Req1, undefined) of
        undefined ->
            Req1;
        Term when is_atom(Term) ->
            Method = cowboy_req:method(Req1),
            RootKey = atom_to_binary(Term, utf8),
            OrgUnitBin = ?DEFAULT_INDEX_BINARY,
            publish_counter(<<"api.", Method/binary, ".", RootKey/binary, ".", Type/binary, ".", OrgUnitBin/binary>>, 1),
            StatusBin = integer_to_binary(Status),
            publish_counter(<<"api-n.", Method/binary, ".", RootKey/binary, ".", StatusBin/binary, ".", OrgUnitBin/binary>>, 1),
            case maps:get(start_time, Req1, undefined) of
                undefined ->
                    Req1;
                T0 ->
                    T1 = erlang:monotonic_time(milli_seconds),
                    DeltaT = T1 - T0,
                    case egraph_fuse:api_model_to_fuse(Term) of
                        undefined ->
                            ok;
                        Fuse ->
                            case DeltaT > egraph_config_util:circuit_breaker_delta_msec(Fuse) of
                                true ->
                                    egraph_fuse:melt(Fuse);
                                false ->
                                    ok
                            end
                    end,
                    publish_histogram(<<"api.", Method/binary, ".",
                                        RootKey/binary, ".",
                                        Type/binary, ".ms."/utf8, OrgUnitBin/binary>>, DeltaT),
                    publish_histogram(<<"api.", Method/binary, ".",
                                        RootKey/binary, ".ms."/utf8, OrgUnitBin/binary>>, DeltaT),
                    Req1
            end
    end.

publish_req_logs(Status, Req1) ->
    case maps:get(log_enabled, Req1, false) of
        true ->
            Method = cowboy_req:method(Req1),
            Path = cowboy_req:path(Req1),
            Agent = cowboy_req:header(<<"user-agent">>, Req1, <<"">>),
            {IP, _Port} = cowboy_req:peer(Req1),
            Str = "method=~s path=~s status=~p ip=~s agent=~p",
            Args = [Method, Path, Status, format_ip(IP),
                    binary_to_list(Agent)],
            case Status of
                _ when Status < 500 -> req_logs:info(Str, Args);
                _ when Status >= 500 -> req_logs:warning(Str, Args)
            end,
            Req1;
        false ->
            Req1
    end.

publish_gauge(Key, Val) ->
    case folsom_metrics:notify({Key, Val}) of
        {error, _, nonexistent_metric} ->
            folsom_metrics:new_gauge(Key),
            folsom_metrics:notify({Key, Val});
        ok ->
            ok
    end.

publish_counter(Key, Val) ->
    case folsom_metrics:notify({Key, {inc, Val}}) of
        {error, _, nonexistent_metric} ->
            folsom_metrics:new_counter(Key),
            folsom_metrics:notify({Key, {inc, Val}});
        ok ->
            ok
    end.

publish_histogram(Key, Val) ->
    case folsom_metrics:notify({Key, Val}) of
        {error, _, nonexistent_metric} ->
            folsom_metrics:new_histogram(Key),
            folsom_metrics:notify({Key, Val});
        ok ->
            ok
    end.

format_ip({A, B, C, D}) ->
    [integer_to_list(A), ".", integer_to_list(B), ".",
     integer_to_list(C), ".", integer_to_list(D)].


http_status_to_metric_name(Status) when Status < 200 -> <<"1xx">>;
http_status_to_metric_name(Status) when Status < 300 -> <<"2xx">>;
http_status_to_metric_name(Status) when Status < 400 -> <<"3xx">>;
http_status_to_metric_name(Status) when Status < 500 -> <<"4xx">>;
http_status_to_metric_name(Status) when Status < 600 -> <<"5xx">>;
http_status_to_metric_name(_) -> <<"bad_status">>.

%% although it may be strage but 4xx are ok too.
%% This applies to otter though.
http_status_to_otter_final_result(Status) when Status < 500 -> "ok";
http_status_to_otter_final_result(_) -> "fail".

