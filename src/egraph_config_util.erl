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
-module(egraph_config_util).
-author("neerajsharma").

-include("egraph_constants.hrl").

-export([generic_http_client_config/0
         ,generic_http_client_set_options/0
         ,circuit_breaker_delta_msec/1
         ,circuit_breaker_config/1
         ,mysql_rw_pool/1
         ,mysql_ro_pools/1
         ,mysql_rw_timeout_msec/1
         ,mysql_ro_timeout_msec/1
         ,reindex_max_shard_per_run/0
        ]).

-type mysql_pool_type() :: index | link | detail.

generic_http_client_config() ->
        application:get_env(?APPLICATION_NAME, generic_http_client, []).

generic_http_client_set_options() ->
    HttpClientConfig = generic_http_client_config(),
    proplists:get_value(set_options,
                        HttpClientConfig,
                        ?DEFAULT_HTTP_CLIENT_SET_OPTIONS).

-spec circuit_breaker_delta_msec(atom()) -> pos_integer().
circuit_breaker_delta_msec(_) ->
    application:get_env(?APPLICATION_NAME,
                        circuit_breaker_delta_msec,
                        ?DEFAULT_CIRCUIT_BREAKER_DELTA_MSEC).

-spec circuit_breaker_config(atom()) -> [{term(), term()}].
circuit_breaker_config(_) ->
    CircuitBreakerConfig = application:get_env(
                             ?APPLICATION_NAME,
                             circuit_breakers,
                             []),
    proplists:get_value(
      search,
      CircuitBreakerConfig,
      ?DEFAULT_CIRCUIT_BREAKER_CONFIG).

-spec mysql_rw_pool(mysql_pool_type()) -> atom().
mysql_rw_pool(index) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, index_rw_pool),
    V;
mysql_rw_pool(detail) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, detail_rw_pool),
    V;
mysql_rw_pool(link) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, link_rw_pool),
    V.

-spec mysql_ro_pools(mysql_pool_type()) -> [atom()].
mysql_ro_pools(index) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, index_ro_pools),
    V;
mysql_ro_pools(detail) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, detail_ro_pools),
    V;
mysql_ro_pools(link) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, link_ro_pools),
    V.

-spec mysql_rw_timeout_msec(mysql_pool_type()) -> pos_integer().
mysql_rw_timeout_msec(index) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, index_rw_timeout_msec),
    V;
mysql_rw_timeout_msec(detail) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, detail_rw_timeout_msec),
    V;
mysql_rw_timeout_msec(link) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, link_rw_timeout_msec),
    V.

-spec mysql_ro_timeout_msec(mysql_pool_type()) -> pos_integer().
mysql_ro_timeout_msec(index) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, index_ro_timeout_msec),
    V;
mysql_ro_timeout_msec(detail) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, detail_ro_timeout_msec),
    V;
mysql_ro_timeout_msec(link) ->
    {ok, V} = application:get_env(?APPLICATION_NAME, link_ro_timeout_msec),
    V.

-spec reindex_max_shard_per_run() -> pos_integer().
reindex_max_shard_per_run() ->
    application:get_env(?APPLICATION_NAME,
                        reindex_max_shard_per_run,
                        ?DEFAULT_REINDEXER_MASTER_MAX_SHARDS).

