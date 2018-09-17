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
-module(egraph_callback).
-ignore_xref([behaviour_info/1]).
-type state() :: term().
-type id() :: binary().
-export_type([id/0]).

-callback init() -> state().
-callback init(term(), [{binary(), binary()}]) -> state().
-callback terminate(state()) -> term().
-callback validate(term(), state()) -> {boolean(), state()}.
-callback create(id() | undefined, term(), state()) ->
            {false | true | {true, id()}, state()}.
-callback read(id(), state()) -> {{ok, term()} | {error, not_found}, state()}.
-callback update(id(), term(), state()) -> {boolean(), state()}.
-callback delete(id(), state()) -> {boolean(), state()}.
