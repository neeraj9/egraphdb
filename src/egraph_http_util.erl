%%%-------------------------------------------------------------------
%%% @author Neeraj Sharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%% A collection of http utilities which are generally useful.
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
-module(egraph_http_util).
-author("Neeraj Sharma").

-include("egraph_constants.hrl").

%% dont need traceability for these functions
%%-compile([native, {hipe, [o3]}]).

%% API
-export([http_accept_types/1]).


-spec http_accept_types(Req :: cowboy_req:req()) -> [binary()].
http_accept_types(Req) ->
    AcceptHeader = cowboy_req:header(<<"accept">>, Req),
    Parts = binary:split(AcceptHeader, <<",">>, [global, trim_all]),
    lists:foldl(fun(E, AccIn) ->
                        [string:lowercase(E) | AccIn]
                end, [], Parts).

