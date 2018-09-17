%% %CopyrightBegin%
%%%
%%% Taken from github.com/beamparticle/beamparticle.
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
-module(egraph_compiler).
-author(neerajsharma).

-include("egraph_constants.hrl").

-export([evaluate_erlang_expression/2]).

%% @doc Evaluate a given Erlang expression and give back result.
%%
%% intercept local and external functions, while the external
%% functions are intercepted for tracing only. This is dangerous,
%% but necessary for maximum flexibity to call any function.
%% If required this can be modified to intercept external
%% module functions as well to jail them within a limited set.
-spec evaluate_erlang_expression(binary(), normal | optimize) -> any().
evaluate_erlang_expression(ErlangExpression, CompileType) ->
    ErlangParsedExpressions =
        get_erlang_parsed_expressions(ErlangExpression),
    evaluate_erlang_parsed_expressions(ErlangParsedExpressions, CompileType).

-spec get_erlang_parsed_expressions(fun() | string() | binary()) -> any().
get_erlang_parsed_expressions(ErlangExpression) when is_binary(ErlangExpression) ->
    get_erlang_parsed_expressions(binary_to_list(ErlangExpression));
get_erlang_parsed_expressions(ErlangExpression) when is_list(ErlangExpression) ->
    {ok, ErlangTokens, _} = erl_scan:string(ErlangExpression),
    {ok, ErlangParsedExpressions} = erl_parse:parse_exprs(ErlangTokens),
    ErlangParsedExpressions.

-spec evaluate_erlang_parsed_expressions(term(), normal | optimize) -> any().
evaluate_erlang_parsed_expressions(ErlangParsedExpressions, normal) ->
    %% bindings are also returned as third tuple element but not used
    {value, Result, _} = erl_eval:exprs(ErlangParsedExpressions, [],
                                        {value, fun intercept_local_function/2},
                                        {value, fun intercept_nonlocal_function/2}),
    Result;
evaluate_erlang_parsed_expressions(ErlangParsedExpressions, optimize) ->
    %% bindings are also returned as third tuple element but not used
    {value, Result, _} = erl_eval:exprs(ErlangParsedExpressions, [],
                                        {value, fun intercept_local_function/2}),
    Result.

%% @private
%% @doc Intercept calls to local function and patch them in.
-spec intercept_local_function(FunctionName :: atom(),
                               Arguments :: list()) -> any().
intercept_local_function(FunctionName, Arguments) ->
    lager:debug("Local call to ~p with ~p~n", [FunctionName, Arguments]),
    case {FunctionName, Arguments} of
        {log_info, [Format, ArgList]} ->
            lager:info(Format, ArgList);
        {log_info, [Format]} ->
            lager:info(Format);
        {search_destination, [SourceId]} when is_binary(SourceId) andalso (byte_size(SourceId) == 8) ->
            %% return {ok, [Id :: binary()]}
            case egraph_link_model:search(SourceId, destination) of
                {ok, Ids} -> Ids;
                _ -> []
            end;
        {get_detail, [Id]} when is_binary(Id) andalso (byte_size(Id) == 8) ->
            %% return [map()]
            case egraph_detail_model:read_resource(Id) of
                {ok, [Info]} -> Info;
                _ -> #{}
            end;
        {get_detail_fold, [Fun, InitialAcc, Ids]} when is_function(Fun, 2) andalso is_list(Ids) ->
            egraph_api:get_detail_fold(Fun, InitialAcc, Ids);
        {get_detail_concurrent_fold, [Fun, Ids]} when is_function(Fun, 2) andalso is_list(Ids) ->
            egraph_api:get_detail_concurrent_fold(Fun, Ids);
        {search_index, [Data, KeyType, IndexName]} ->
            case egraph_index_model:search(Data, KeyType, IndexName) of
                {ok, Ids} -> Ids;
                _ -> []
            end;
        {search_range_index, [DataStart, DataEnd, KeyType, IndexName]} ->
            case egraph_index_model:search({DataStart, DataEnd}, KeyType, IndexName) of
                {ok, Ids} -> Ids;
                _ -> []
            end;
        {http_client_accept_content_type, [ContentType]} ->
            egraph_api:http_client_accept_content_type(ContentType);
        {http_stream_reply, [Code, ContentType]} ->
            egraph_api:http_stream_reply(Code, ContentType);
        {http_stream_body, [Data, Opt]} when Opt == nofin orelse Opt == fin ->
            egraph_api:http_stream_body(Data, Opt);
        _ ->
            undefined
    end.

%% @private
%% @doc Intercept calls to non-local function
-spec intercept_nonlocal_function({ModuleName :: atom(), FunctionName :: atom()}
                                  | fun(),
                                  Arguments :: list()) -> any().
intercept_nonlocal_function({ModuleName, FunctionName}, Arguments) ->
    %% TODO: Put some restriction here
    apply(ModuleName, FunctionName, Arguments);
intercept_nonlocal_function(Fun, Arguments) when is_function(Fun) ->
    %% TODO: Put some restriction here
    apply(Fun, Arguments);
intercept_nonlocal_function(Fun, Arguments) when is_atom(Fun) ->
    %% TODO: Put some restriction here

    %% When local function name are used within variables as atom,
    %% so they land here.
    %% Example: Functions = [ fun_a, fun_b ]
    intercept_local_function(Fun, Arguments).

