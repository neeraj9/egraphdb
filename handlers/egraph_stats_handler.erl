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
-module(egraph_stats_handler).

-include("egraph_constants.hrl").

-export([init/2]).

-define(LAGER_ATTRS, [{type, handler}]).

init(Req0, Opts) ->
    lager:debug(?LAGER_ATTRS, "[~p] ~p received request = ~p, Opts = ~p",
                [self(), ?MODULE, Req0, Opts]),
    Nodes = [node() | nodes()],
    {Responses, _BadNodes} = rpc:multicall(
                               Nodes, egraph_stats_util, node_info, [],
                               ?DEFAULT_EGRAPH_CLUSTER_CALL_TIMEOUT_MSEC),
    GoodResponses = lists:filter(fun(E) -> is_map(E) end, Responses),
    Content = jiffy:encode(GoodResponses),
    Req = cowboy_req:reply(200, #{
            <<"content-type">> => <<"application/json; charset=utf-8">>,
            <<"connection">> => <<"keep-alive">>}, Content, Req0),
    {ok, Req, Opts}.

