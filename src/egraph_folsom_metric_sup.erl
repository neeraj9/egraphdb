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
-module(egraph_folsom_metric_sup).

-behaviour(supervisor).

-include("egraph_constants.hrl").

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Name, Index, Type),
        {Name, {I, start_link, [Index]}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 5,
    MaxSecondsBetweenRestarts = 10,
    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {ok, FolsomDdbConfig} = application:get_env(?APPLICATION_NAME,
                                                folsom_graphite),
    FolsomDdbBuckets = proplists:get_value(buckets, FolsomDdbConfig, []),
    NumWorkers = length(FolsomDdbBuckets),
    Specs1 = [?CHILD(egraph_folsom_graphite_server,
        proplists:get_value(name,
                            lists:nth(Index, FolsomDdbBuckets)),
        Index, worker) || Index <- lists:seq(1, NumWorkers)],
    {ok, { SupFlags, Specs1} }.

%%%===================================================================
%%% Internal functions
%%%===================================================================
