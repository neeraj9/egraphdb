%%%-------------------------------------------------------------------
%%% @doc
%%% Supervisor for the egraph app. This will boot the
%%% supervision tree required for persistent application state.
%%% @end
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
-module(egraph_sup).
-behaviour(supervisor).

-export([start_link/1]).
%% callbacks
-export([init/1]).

-include("egraph_constants.hrl").

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API
%%%===================================================================
-spec start_link([module()]) -> {ok, pid()} | ignore | {error, term()}.
start_link(Models) ->
        supervisor:start_link({local, ?SERVER}, ?MODULE, Models).

%%%===================================================================
%%% Callbacks
%%%===================================================================
init(_Specs) ->
    MemStoresSupSpec = [{egraph_memstores_sup,
                         {egraph_memstores_sup, start_link, []},
                         permanent, 5000, supervisor,
                         [egraph_memstores_sup]}],
    EcrnSupSpec = [{ecrn_sup, {ecrn_sup, start_link, []},
                   permanent, 5000, supervisor, [ecrn_sup]}],
    SysmonConfig = application:get_env(?APPLICATION_NAME, sysmon, []),
    SysmonSpecs = case proplists:get_value(enabled, SysmonConfig, false) of
                      true ->
                          [{egraph_sysmon_server,
                            {egraph_sysmon_server, start_link, []},
                            permanent, 5000, worker, [egraph_sysmon_server]}];
                      false ->
                          []
                  end,
    MetaCacheOpts = [],
    MetaCacheSpecs = [{egraph_metacache_server,
                          {egraph_metacache_server, start_link, [MetaCacheOpts]},
                          permanent, 5000, worker,
                          [egraph_metacache_server]}],
    FolsomMetricSpecs = [{egraph_folsom_metric_sup,
                          {egraph_folsom_metric_sup, start_link, []},
                          permanent, 5000, supervisor,
                          [egraph_folsom_metric_sup]}],
    DelayedOpts = [],
    DelayedStartupServerSpecs = [{egraph_delaystart_server, {
                                   egraph_delaystart_server,
                                   start_link, [DelayedOpts]},
                                  permanent, 5000, worker,
                                  [egraph_delaystart_server]}],
    ReindexServerSpecs = case application:get_env(?APPLICATION_NAME, enable_reindex, false) of
                             false ->
                                 [];
                             true ->
                                ReindexerSpecs = lists:foldl(fun(Id, AccIn) ->
                                                                     ChildName = list_to_atom("egraph_reindexing_server_" ++ integer_to_list(Id)),
                                                                     [{ChildName, {
                                                                        egraph_reindexing_server,
                                                                        start_link, [[{name, ChildName}, {shard_id, Id}]]},
                                                                      permanent, 5000, worker,
                                                                      [egraph_reindexing_server]} | AccIn]
                                                             end, [], lists:seq(0, trunc(math:pow(2, 11)) - 1)),
                                ReindexerMasterSpecs = [{egraph_reindexing_master_server, {
                                                           egraph_reindexing_master_server,
                                                           start_link, [ [] ]},
                                                         permanent, 5000, worker,
                                                         [egraph_reindexing_master_server]}],
                                ReindexerMasterSpecs ++ ReindexerSpecs
                         end,
    {ok, { {one_for_one, 1000, 3600},
        MemStoresSupSpec
         ++ MetaCacheSpecs
         ++ EcrnSupSpec ++ SysmonSpecs ++ FolsomMetricSpecs
         ++ DelayedStartupServerSpecs ++ ReindexServerSpecs}}.


%%%===================================================================
%%% Internal functions
%%%===================================================================

