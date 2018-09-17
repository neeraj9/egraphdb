%%
%% Copyright (c) 2018.
%%
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
-module(egraph_error_util).

-include("egraph_error_codes.hrl").

%% API
-export([all_error_codes/0,
    error_code_to_http_code/1,
    error/3,
    error/2,
    get_error_code/1,
    explain/1,
    is_error/1]).

%% Must match exactly with egraph_error_codes.hrl
-type egraph_error_code() :: ?PLATO_ERR_CODE_INTERNAL_ERROR.

-spec all_error_codes() -> [egraph_error_code()].
all_error_codes() ->
    [ ?PLATO_ERR_CODE_INTERNAL_ERROR ].

%% Must match exactly with egraph_error_codes.hrl
-spec error_code_to_http_code(Code :: egraph_error_code()) -> integer().
error_code_to_http_code(?PLATO_ERR_CODE_INTERNAL_ERROR) -> 500.

%% @doc Construct a map with given error information
%%
%% The intent of this function is to standardize the
%% error reporting along with an easy mechanism to
%% search for all the places in the code where
%% error is constructed.
-spec error(Code :: integer(), Message :: binary(), Additional :: map()) -> map().
error(Code, Message, Additional)
    when is_integer(Code) andalso is_binary(Message) andalso is_map(Additional) ->
    #{
        <<"status">> => <<"ERROR">>,
        <<"error_code">> => Code,
        <<"error_message">> => Message,
        <<"additional">> => Additional
    }.

%% @doc Construct a map with given error information
%%
%% The intent of this function is to standardize the
%% error reporting along with an easy mechanism to
%% search for all the places in the code where
%% error is constructed.
-spec error(Code :: integer(), Message :: binary()) -> map().
error(Code, Message) when is_integer(Code) andalso is_binary(Message) ->
    #{
        <<"status">> => <<"ERROR">>,
        <<"error_code">> => Code,
        <<"error_message">> => Message
    }.

-spec get_error_code(ErrorMap :: map()) -> integer().
get_error_code(ErrorMap) ->
    maps:get(<<"error_code">>, ErrorMap).

-spec explain(ErrorCode :: egraph_error_code()) -> [binary()].
explain(?PLATO_ERR_CODE_INTERNAL_ERROR) ->
    [
        ?PLATO_ERR_MSG_INTERNAL_ERROR
    ].

-spec is_error(Map :: map()) -> boolean().
is_error(Map) when is_map(Map) ->
    maps:get(<<"status">>, Map, <<>>) =:= <<"ERROR">>.

