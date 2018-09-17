%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(egraph_fuse).
-author("neerajsharma").

-export([api_model_to_fuse/1,
         circuit_broken/1,
         setup/1,
         blown/1,
         melt/1]).

-spec api_model_to_fuse(atom()) -> undefined | atom().
api_model_to_fuse(_) ->
    http_api_latency.

-spec circuit_broken(undefined | http_api_latency) -> boolean().
circuit_broken(undefined) ->
    false;
circuit_broken(http_api_latency = Fuse) ->
    blown(Fuse).

-spec setup(http_api_latency) -> ok.
setup(http_api_latency = Fuse) ->
    Config = egraph_config_util:circuit_breaker_config(Fuse),
    MaxR = proplists:get_value(maxr, Config),
    MaxT = proplists:get_value(maxt, Config),
    ResetMsec = proplists:get_value(reset, Config),
    Strategy = {standard, MaxR, MaxT},
    Refresh = {reset, ResetMsec},
    Opts = {Strategy, Refresh},
    fuse:install(Fuse, Opts).


-spec blown(http_api_latency) -> boolean().
blown(http_api_latency = Fuse) ->
    %% async querying fuse state is known to have race conditions
    %% but is very fast and do not block unlike sync.
    %% This implies that it will take a while for fuse to reflect
    %% true value, but that is alright for a short while.
    fuse:ask(Fuse, async_dirty) == blown.

-spec melt(http_api_latency) -> ok.
melt(http_api_latency = Fuse) ->
    fuse:melt(Fuse).

