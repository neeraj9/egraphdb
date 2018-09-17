%%%-------------------------------------------------------------------
%%% @author Neeraj Sharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%% A collection of generic utilities which are generally useful.
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
-module(egraph_stats_util).

-include("egraph_constants.hrl").

-export([node_info/0, git_info/0, system_critical_info/0, sysconfig_info/0, node_uptime/0]).

node_info() ->
    #{
        <<"git">> => git_info(),
        <<"system_critical_info">> => system_critical_info(),
        <<"sysconfig_info">> => sysconfig_info()
    }.

sysconfig_info() ->
    CircuitBreakerSearchDeltaMsec = application:get_env(
                                      ?APPLICATION_NAME,
                                      circuit_breaker_search_delta_msec,
                                      -1),
    CircuitBreakersConfig = convert_sysconfig_proplist_to_json_map(
                              circuit_breakers),
    OpenTracingConfig = convert_sysconfig_proplist_to_json_map(
                          opentracing),
    HttpRestConfig = convert_sysconfig_proplist_to_json_map(
                       http_rest),
    CachesConfig = convert_sysconfig_proplist_to_json_map(
                     caches),
    PalmaPoolConfig = application:get_env(
                        ?APPLICATION_NAME, palma_pools, []),
    NumPalmaPools = length(PalmaPoolConfig),
    PalmaPoolInfo = lists:foldl(fun(E, AccIn) ->
                                        Poolname = atom_to_binary(element(1, E), utf8),
                                        NumWorkers = element(2, E),
                                        ShutdownDelayMsec = element(4, E),
                                        List = 
                                            case element(3,element(2,element(3,E))) of
                                                [] -> "";
                                                Data -> [H | _] = Data, H
                                            end,
                                        Url =
                                            case is_proplist(List) of
                                                true -> proplists:get_value(host,List,"");
                                                false -> List
                                            end,    
                                        R = #{ <<"pool_name">> => Poolname,
                                            <<"pool_url">> => list_to_binary(Url),
                                           <<"num_workers">> => NumWorkers,
                                           <<"shutdown_delay_msec">> => ShutdownDelayMsec},
                                        [R | AccIn]
                                end, [], PalmaPoolConfig),
    FolsomGraphiteConfig = application:get_env(
                             ?APPLICATION_NAME, folsom_graphite, []),
    IsFolsomEnabled = proplists:get_value(enabled, FolsomGraphiteConfig, false),
    FolsomEndpoint = case proplists:get_value(endpoint, FolsomGraphiteConfig, undefined) of
                         undefined ->
                             #{};
                         {FolsomIp, FolsomPort} ->
                             #{<<"ip">> => list_to_binary(FolsomIp),
                               <<"port">> => FolsomPort}
                     end,
    SysmonConfig = application:get_env(
                     ?APPLICATION_NAME, sysmon, []),
    IsSysmonEnabled = proplists:get_value(enabled, SysmonConfig),
    #{
        <<"circuit_breaker_search_delta_msec">> => CircuitBreakerSearchDeltaMsec,
        <<"circuit_breakers">> => CircuitBreakersConfig,
        <<"opentracing">> => OpenTracingConfig,
        <<"http_rest">> => HttpRestConfig,
        <<"caches">> => CachesConfig,
        <<"palma_pools">> => #{
            <<"num_pools">> => NumPalmaPools,
            <<"info">> => PalmaPoolInfo
           },
        <<"folsom_graphite">> => #{
            <<"enabled">> => IsFolsomEnabled,
            <<"endpoint">> => FolsomEndpoint
           },
        <<"sysmon_enabled">> => IsSysmonEnabled
    }.

git_info() ->
    #{
        <<"hash">> => egraph_version:hash(),
        <<"last_update">> => egraph_version:last_update(),
        <<"title">> => egraph_version:title(),
        <<"branch">> => egraph_version:branch(),
        <<"status">> => egraph_version:status()
     }.

node_uptime() ->
    UptimeSec = egraph_util:node_uptime(second),
    NodeName = node(),
    {UptimeSec, NodeName}.

system_critical_info() ->
    UptimeSec = egraph_util:node_uptime(second),
    UptimeMin = UptimeSec div 60,
    UptimeHour = UptimeMin div 60,
    UptimeDay = UptimeHour div 24,
    #{
        <<"uptime_in_sec">> => UptimeSec,
        <<"uptime_in_min">> => UptimeMin,
        <<"uptime_in_hour">> => UptimeHour,
        <<"uptime_in_day">> => UptimeDay,
        <<"os">> => #{
            <<"ulimit">> => #{
                <<"open_files">> => list_to_binary(string:trim(os:cmd("ulimit -n"))),
                <<"core_file_size">> => list_to_binary(string:trim(os:cmd("ulimit -c"))),
                <<"scheduling_priority">> => list_to_binary(string:trim(os:cmd("ulimit -f"))),
                <<"file_size">> => list_to_binary(string:trim(os:cmd("ulimit -n"))),
                <<"stack_size">> => list_to_binary(string:trim(os:cmd("ulimit -s")))
            }
        },
        <<"process">> => #{
            <<"count">> => erlang:system_info(process_count),
            <<"limit">> => erlang:system_info(process_limit)
        },
        <<"ets">> => #{
            <<"count">> => erlang:system_info(ets_count),
            <<"limit">> => erlang:system_info(ets_limit)
        },
        <<"port">> => #{
            <<"count">> => erlang:system_info(port_count),
            <<"limit">> => erlang:system_info(port_limit)
        },
        <<"stats">> => #{
            <<"active_tasks_all">> => erlang:statistics(active_tasks_all)
        },
        <<"cluster">> => #{
            <<"self">> => atom_to_binary(node(), utf8),
            <<"peers">> => [atom_to_binary(X, utf8) || X <- nodes()]
        },
        <<"atom">> => #{
            <<"atom_count">> => erlang:system_info(atom_count),
            <<"atom_limit">> => erlang:system_info(atom_limit)
        },
        <<"memory">> => maps:from_list([{atom_to_binary(X, utf8), Y} || {X,Y} <- erlang:memory()]),
        <<"garbage_collection">> => maps:from_list([{atom_to_binary(X, utf8), Y} || {X,Y} <- erlang:system_info(garbage_collection)]),
        <<"erlang">> => #{
            <<"build_type">> => atom_to_binary(erlang:system_info(build_type), utf8),
            <<"otp_release">> => list_to_binary(erlang:system_info(otp_release)),
            <<"multi_scheduling">> => atom_to_binary(erlang:system_info(multi_scheduling), utf8),
            <<"debug_compiled">> => atom_to_binary(erlang:system_info(debug_compiled), utf8),
            <<"delayed_node_table_gc">> => erlang:system_info(delayed_node_table_gc),
            <<"dirty_cpu_schedulers">> => erlang:system_info(dirty_cpu_schedulers),
            <<"dirty_cpu_schedulers_online">> => erlang:system_info(dirty_cpu_schedulers_online)
        }
    }.

convert_sysconfig_proplist_to_json_map(Name) ->
    Config = application:get_env(?APPLICATION_NAME, Name, []),
    maps:from_list([convert_proplist_for_json(X, Y) || {X, Y} <- Config]).

convert_proplist_for_json(X, Y) when is_list(Y) ->
    {atom_to_binary(X, utf8), maps:from_list(
                                    [{atom_to_binary(A, utf8), B} || {A, B} <- Y])};
convert_proplist_for_json(X, Y) ->
    {atom_to_binary(X, utf8), Y}.


is_proplist(L) when is_list(L) ->
    lists:all(fun
                  ({K,_}) when is_atom(K)   -> true;
                  ({K,_}) when is_binary(K) -> io_lib:printable_latin1_list(binary_to_list(K));
                  (_)                       -> false
              end, L);
is_proplist(_) -> false.

