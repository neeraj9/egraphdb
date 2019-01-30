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
-module(egraph_app).
-author("neerajsharma").

-behaviour(application).

-include("egraph_constants.hrl").

%% Application callbacks
-export([start/2,
         stop/1]).

-define(LAGER_ATTRS, [{type, startup}]).

%%%===================================================================
%%% Application callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application is started using
%% application:start/[1,2], and should start the processes of the
%% application. If the application is structured according to the OTP
%% design principles as a supervision tree, this means starting the
%% top supervisor of the tree.
%%
%% @end
%%--------------------------------------------------------------------
-spec(start(StartType :: normal | {takeover, node()} | {failover, node()},
    StartArgs :: term()) ->
  {ok, pid()} |
  {ok, pid(), State :: term()} |
  {error, Reason :: term()}).
start(_StartType, _StartArgs) ->
    %% call wallclock time first, so that counters are reset
    %% so on subsequent calls the Total time returned by
    %% erlang:statistics(wall_clock) can be used as uptime.
    egraph_util:node_uptime(second),

    %% setup zlib dict
    egraph_zlib_util:init_zlib_dictionaries(),

    %% setup caches
    {ok, Caches} = application:get_env(?APPLICATION_NAME, caches),
    lists:foreach(fun({CacheName, CacheOptions}) ->
                          egraph_cache_util:cache_start_link(
                            CacheOptions, CacheName)
                  end, Caches),

    % TODO only when running in production
    PrivDir = code:priv_dir(?APPLICATION_NAME),
    %PrivDir = "priv",
    lager:debug(?LAGER_ATTRS, "[~p] ~p detected PrivDir=~p",
                [self(), ?MODULE, PrivDir]),
    HttpRestConfig = application:get_env(?APPLICATION_NAME, http_rest, []),
    case HttpRestConfig of
        [] ->
            %% DONT start the http server
            ok;
        _ ->
            Port = proplists:get_value(port, HttpRestConfig, ?DEFAULT_HTTP_PORT),
            start_http_server(PrivDir, Port, HttpRestConfig)
    end,

    %% set httpc options
    HttpClientSetOptions = egraph_config_util:generic_http_client_set_options(),
    lager:info("[~p] ~p HttpClientSetOptions = ~p", [self(), ?MODULE, HttpClientSetOptions]),
    httpc:set_options(HttpClientSetOptions),
    %% setup circuit breakers
    egraph_fuse:setup(?CIRCUIT_BREAKER_HTTP_API_LATENCY),
    %% start supervisor
    egraph_sup:start_link([]).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called whenever an application has stopped. It
%% is intended to be the opposite of Module:start/2 and should do
%% any necessary cleaning up. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec(stop(State :: term()) -> term()).
stop(_State) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

start_http_server(PrivDir, Port, HttpRestConfig) ->
   Dispatch = cowboy_router:compile(get_routes()),
    NrListeners = proplists:get_value(nr_listeners,
                                      HttpRestConfig,
                                      ?DEFAULT_HTTP_NR_LISTENERS),
    Backlog = proplists:get_value(backlog,
                                  HttpRestConfig,
                                  ?DEFAULT_HTTP_BACKLOG),
    MaxConnections = proplists:get_value(max_connections,
                                         HttpRestConfig,
                                         ?DEFAULT_HTTP_MAX_CONNECTIONS),
    %% Important: max_keepalive is only available in cowboy 2
    MaxKeepAlive = proplists:get_value(max_keepalive,
                                       HttpRestConfig,
                                       ?DEFAULT_MAX_HTTP_KEEPALIVES),
    IsSsl = proplists:get_value(ssl, HttpRestConfig,
                                ?DEFAULT_HTTP_IS_SSL_ENABLED),
    case IsSsl of
        true ->
            {ok, _} = cowboy:start_tls(https, [
                {port, Port},
                {num_acceptors, NrListeners},
                {backlog, Backlog},
                {max_connections, MaxConnections},
                %% {cacertfile, PrivDir ++ "/ssl/ca-chain.cert.pem"},
                {certfile, PrivDir ++ "/ssl/cert.pem"},
                {keyfile, PrivDir ++ "/ssl/key.pem"},
                {versions, ['tlsv1.2']},
                {ciphers, ?DEFAULT_HTTPS_CIPHERS}
                ],
                #{env => #{dispatch => Dispatch},
                  %% TODO: stream_handlers => [stream_http_rest_log_handler],
                  %%onresponse => fun egraph_log_utils:req_log/4,
                  max_keepalive => MaxKeepAlive});
        false ->
            {ok, _} = cowboy:start_clear(http, [
                {port, Port},
                {num_acceptors, NrListeners},
                {backlog, Backlog},
                {max_connections, MaxConnections}
                ],
                #{env => #{dispatch => Dispatch},
                  %% TODO: stream_handlers => [stream_http_rest_log_handler],
                  %%onresponse => fun egraph_log_utils:req_log/4,
                  max_keepalive => MaxKeepAlive})
    end.

%% @private get routes for cowboy dispatch
-spec get_routes() -> list().
get_routes() ->
    [{'_',
      [
       %% v1 handlers
       {"/v1/search/[:id]", egraph_generic_handler, [egraph_v1_search_model]},
       %% core handlers
       {"/index/[:id]", egraph_generic_handler, [egraph_index_model]},
       {"/detail/[:id]", egraph_generic_handler, [egraph_detail_model]},
       {"/link/[:id]", egraph_generic_handler, [egraph_link_model]},
       {"/reindex/[:id]", egraph_generic_handler, [egraph_reindex_model]},
       {"/compression/dict/[:id]", egraph_generic_handler, [egraph_dictionary_model]},
       {"/f/[:id]", egraph_generic_handler, [egraph_function_model]},
       {"/fquery/[:id]", egraph_generic_handler, [egraph_fquery_model]},
       %% generic handlers
       {"/api/[:id]", egraph_generic_handler, [egraph_generic_model]},
       {"/stats", egraph_stats_handler, []},
       {"/alive", egraph_alive_handler, []}
  ]}].
