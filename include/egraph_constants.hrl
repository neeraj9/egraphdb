%%%-------------------------------------------------------------------
%%% @author Neeraj Sharma
%%% @copyright (C) 2016, Neeraj Sharma
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

-define(APPLICATION_NAME, egraph).

-define(DEFAULT_HTTP_PORT, 9901).
-define(DEFAULT_HTTP_IS_SSL_ENABLED, true).
-define(DEFAULT_MAX_HTTP_KEEPALIVES, 100).
-define(DEFAULT_HTTP_NR_LISTENERS, 1000).
-define(DEFAULT_HTTP_BACKLOG, 1024).
-define(DEFAULT_HTTP_MAX_CONNECTIONS, 50000).

-define(DEFAULT_MAX_HTTP_READ_TIMEOUT_MSEC, 1000).
-define(DEFAULT_MAX_HTTP_READ_BYTES, 12 * 1024 * 1024).

%% see https://en.wikipedia.org/wiki/List_of_HTTP_status_codes
-define(HTTP_REQUEST_TIMEOUT_CODE, 408).
-define(HTTP_METHOD_NOT_ALLOWED_CODE, 405).

-define(DECIMAL_PRECISION, 2).

%% http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html#sec10.4.16
-define(HTTP_CODE_UNSUPPORTED_MEDIA_TYPE, 415).
-define(HTTP_CODE_METHOD_NOT_ALLOWED, 405).
-define(HTTP_CODE_NOT_ACCEPTABLE, 406).
-define(HTTP_CODE_SERVICE_UNAVAILABLE, 503).

-define(DEFAULT_HTTP_JSON_RESPONSE_HEADER, #{<<"content-type">> => <<"application/json; charset=utf-8">>,
                                             <<"connection">> => <<"keep-alive">>}).

-define(HTTP_OK_RESPONSE_CODE, 200).
-define(HTTP_NOT_FOUND, 404).
-define(HTTP_BAD_REQUEST, 400).

%% Metrics stored in metric store starts with a prefix
-define(METRIC_PREFIX, <<"egraph">>).

-define(MYSQL_POOL_NAME, dbro_pool).

%% TODO the readonly pool must be separate
%% %% must match pool name with sys.config
-define(EGRAPH_RO_MYSQL_POOL_NAME, egraphdbro_pool).
-define(EGRAPH_RW_MYSQL_POOL_NAME, egraphdbrw_pool).

-define(DEFAULT_MYSQL_QUERY_TIMEOUT_MSEC, 2000).
-define(DEFAULT_REDIS_QUERY_TIMEOUT_MSEC, 5000).
-define(DEFAULT_HTTP_CONNECTION_TIMEOUT, 10000).
-define(DEFAULT_HTTP_TIMEOUT, 10000).
-define(DEFAULT_HTTP_REALTIME_UPDATE_TIMEOUT, 8000).
-define(DEFAULT_HTTP_CACHED_SL_TIMEOUT, 3000).
%% This is a greedy configuration, which will keep latencies
%% to minimum but open new connections as soon as possible.
-define(DEFAULT_HTTP_CLIENT_SET_OPTIONS,
        [{max_keep_alive_length, 0}, {max_sessions, 200}]).

%% Cache Information
-define(CACHE_GENERIC, cache_generic).
-define(DEFAULT_CACHE_MEMORY_BYTES, 64*1024*1024).
-define(DEFAULT_CACHE_SEGMENTS, 10).
-define(DEFAULT_CACHE_TTL_SEC, 3600).


%% retry timeout in millisecond when delayed startup fails
%% the first time for any services.
-define(DEFAULT_DELAYED_STARTUP_RETRY_TIMEOUT_MSEC, 2000).

-define(DEFAULT_MEMSTORE_TABLE_TIMEOUT_MSEC, 1000).


-define(DEFAULT_TTL_TIMEOUT_SEC, 120).

-define(CIRCUIT_BREAKER_HTTP_API_LATENCY, http_api_latency).

-define(DEFAULT_CIRCUIT_BREAKER_DELTA_MSEC, 5000).
%% Inform clients to try after 2 seconds
-define(DEFAULT_CIRCUIT_BREAKER_REPLY_AFTER_SEC, <<"2">>).
-define(DEFAULT_CIRCUIT_BREAKER_CONFIG,
        [{maxr, 100}, {maxt, 1000}, {reset, 10000}]).

-define(DEFAULT_INDEX_BINARY, <<"1">>).

-define(DEFAULT_MYSQL_TIMEOUT_MSEC, 5000).


-define(EGRAPH_TABLE_REINDEX_STATUS, <<"egraph_reindex_status">>).
-define(EGRAPH_TABLE_COMPRESSION_DICT, <<"egraph_compression_dict">>).
-define(EGRAPH_TABLE_FUNCTION, <<"egraph_function">>).

-define(EGRAPH_TABLE_LOOKUP_BASE, <<"egraph_lookup_base">>).
-define(EGRAPH_TABLE_LOOKUP_INT_BASE, <<"egraph_lookup_int_base">>).
-define(EGRAPH_TABLE_LOOKUP_GEO_BASE, <<"egraph_lookup_geo_base">>).
-define(EGRAPH_TABLE_LOOKUP_DOUBLE_BASE, <<"egraph_lookup_double_base">>).
-define(EGRAPH_TABLE_LOOKUP_DATETIME_BASE, <<"egraph_lookup_datetime_base">>).
-define(EGRAPH_TABLE_LOOKUP_DATE_BASE, <<"egraph_lookup_date_base">>).
-define(EGRAPH_TABLE_LOOKUP_TEXT_BASE, <<"egraph_lookup_text_base">>).
-define(EGRAPH_TABLE_DETAILS_BASE, <<"egraph_details_base">>).
-define(EGRAPH_TABLE_LINK_BASE, <<"egraph_link_base">>).


%% number of times to retry write
-define(EGRAPH_WRITE_RETRY, 2).

-define(EGRAPH_DETAILS_SPECIAL_KEY, <<"__key">>).
-define(EGRAPH_DETAILS_SPECIAL_SOURCE, <<"__source">>).
-define(EGRAPH_DETAILS_SPECIAL_DESTINATION, <<"__destination">>).
-define(EGRAPH_DETAILS_SPECIAL_INDEX, <<"__indexes">>).

-define(EGRAPH_INDEX_SPECIAL_SUFFIX_LOWERCASE, <<"_lc__">>).

-define(DEFAULT_EGRAPH_INDEX_SEARCH_LIMIT_RECORDS, 1000000).

-define(EGRAPH_ZLIB_DICTS_TABLE_NAME, compress_dict).

-define(DEFAULT_EGRAPH_CLUSTER_CALL_TIMEOUT_MSEC, 2000).

-define(DEFAULT_EGRAPH_CONCURRENT_JOB_TIMEOUT_MSEC, 20000).
-define(DEFAULT_EGRAPH_CONCURRENT_JOB_MAX_ACTORS, 10).

-define(HTTP_REQ_KEY, req).
-define(HTTP_IS_STREAM, is_stream).

-define(DEFAULT_REINDEXER_SERVER_TIMEOUT_MSEC, 20000).

-define(DEFAULT_REINDEXER_MASTER_MAX_SHARDS, 5).

