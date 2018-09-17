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
-module(egraph_generic_handler).

-include("egraph_constants.hrl").

-behaviour(cowboy_rest).

%% cowboy_rest callbacks
-export([init/2]).
-export([service_available/2]).
-export([allowed_methods/2]).
-export([is_authorized/2]).
-export([content_types_provided/2]).
-export([content_types_accepted/2]).
-export([resource_exists/2]).
-export([delete_resource/2]).

%% to avoid compiler error for unsed functions
-export([to_json/2, from_json/2, to_erlang_binary/2,
         to_erlang_stream_binary/2, from_erlang_binary/2]).

-record(state, {model :: module(),
                start = erlang:monotonic_time(millisecond),
                model_state :: term(),
                resource_id :: binary() | undefined,
                resource :: binary() | term() | undefined}).

-define(MIMETYPE, {<<"application">>, <<"json">>, []}).
-define(MIMETYPE_ERLANG, {<<"application">>, <<"x-erlang-binary">>, []}).
-define(MIMETYPE_ERLANG_STREAM, {<<"application">>, <<"x-erlang-stream-binary">>, []}).
-define(LAGER_ATTRS, [{type, handler}]).

%% handler callbacks to make elvis happy although cowboy_rest behaviour
%% is already imported.
-callback init(Req, any())
    -> {ok | module(), Req, any()}
    | {module(), Req, any(), any()}
    when Req::cowboy_req:req().

%% @private called when starting the handling of a request
init(Req, _Opts=[Model]) ->
    Id = cowboy_req:binding(id, Req),
    QsProplist = cowboy_req:parse_qs(Req),
    State = #state{resource_id=Id,
                   model=Model,
                   model_state=Model:init(Id, QsProplist)},
    lager:debug(?LAGER_ATTRS, "[~p] ~p State = ~p", [self(), ?MODULE, State]),
    Req2 = Req#{log_enabled => true},
    Req3 = Req2#{start_time => State#state.start},
    Req4 = Req3#{metrics_source => State#state.model},
    {cowboy_rest, Req4, State}.

%% @private Check if we're configured to be in lockdown mode to see if the
%% service should be available
service_available(Req, State) ->
    {not application:get_env(?APPLICATION_NAME, lockdown, false), Req, State}.

%% @private Allow CRUD stuff standard
allowed_methods(Req, State) ->
    {[<<"POST">>, <<"GET">>, <<"PUT">>, <<"DELETE">>], Req, State}.

%% @private No authorization in place for this demo
is_authorized(Req, State) ->
    {true, Req, State}.

%% @private Does the resource exist at all?
resource_exists(Req, State=#state{resource_id=Id, model=M, model_state=S}) ->
    Method = cowboy_req:method(Req),
    case Method of
        %% optimization: do not read when asked to write/overwrite
        <<"POST">> ->
            {false, Req, State};
        <<"PUT">> ->
            {false, Req, State};
        _ ->
            case M:read(Id, S) of
                { {ok, Resource}, NewS} ->
                    {true, Req, State#state{resource_id=Id, model_state=NewS,
                                            resource=Resource}};
                { {error, not_found}, NewS} ->
                    {false, Req, State#state{resource_id=Id, model_state=NewS}}
            end
    end.

%%%===================================================================
%%% GET Callbacks
%%%===================================================================

%% @private
content_types_provided(Req, State) ->
    {[{?MIMETYPE, to_json},
      {?MIMETYPE_ERLANG, to_erlang_binary},
      {?MIMETYPE_ERLANG_STREAM, to_erlang_stream_binary}], Req, State}.

%% @private
to_json(Req, State=#state{resource=Resource}) when is_binary(Resource) ->
    {Resource, Req, State};
to_json(Req, State=#state{resource=Resource}) when is_map(Resource) orelse is_list(Resource) orelse is_boolean(Resource) ->
    {jiffy:encode(Resource), Req, State}.

%% @private
to_erlang_binary(Req, State=#state{resource=Resource}) ->
    {erlang:term_to_binary(Resource), Req, State}.

%% @private
to_erlang_stream_binary(Req, State=#state{resource=Resource}) ->
    {egraph_api:encode_erlang_stream_binary(Resource), Req, State}.

%%%===================================================================
%%% DELETE Callbacks
%%%===================================================================

%% @private
delete_resource(Req, State=#state{resource_id=Id, model=M, model_state=S}) ->
    case M:delete(Id, S) of
        {true, NewS} -> {true, Req, State#state{model_state=NewS}};
        {_, NewS} -> {false, Req, State#state{model_state=NewS}}
    end.

%%%===================================================================
%%% PUT/POST Callbacks
%%%===================================================================

%% @private Define content types we accept and handle
content_types_accepted(Req, State) ->
    {[{?MIMETYPE, from_json},
      {?MIMETYPE_ERLANG, from_erlang_binary}], Req, State}.

%% @private Handle the update and figure things out.
from_json(Req, State=#state{resource_id=Id, resource=R, model=M,
                            model_state=S}) ->
    case read_http_post_body(Req) of
        {ok, Body, Req1} ->
            Method = cowboy_req:method(Req1),
            %% TODO @todo already in init
            QsProplist = cowboy_req:parse_qs(Req1),
            lager:debug(?LAGER_ATTRS,
                        "[~p] ~p Method = ~p, QsProplist = ~p, Body=~p",
                        [self(), ?MODULE, Method, QsProplist, Body]),
            case Method of
                <<"PUT">> when Id =:= undefined; R =:= undefined ->
                    {false, Req1, State};
                _ ->
                    handle_http_post_request(Method, Body, QsProplist,
                                             R, Id, M, Req1, State, S,
                                             <<"application/json">>)
            end;
        _ ->
            %% timeout
            Req2 = cowboy_req:reply(
                           ?HTTP_REQUEST_TIMEOUT_CODE,
                           [{<<"content-type">>, <<"application/json">>}],
                           <<"{\"error\": 408, \"msg\": \"timeout\"}">>,
                           Req),
            {stop, Req2, State}
    end.

%% @private Handle the update and figure things out.
from_erlang_binary(Req, State=#state{resource_id=Id, resource=R, model=M,
                                     model_state=S}) ->
    case read_http_post_body(Req) of
        {ok, Body, Req1} ->
            Method = cowboy_req:method(Req1),
            %% TODO @todo already in init
            QsProplist = cowboy_req:parse_qs(Req1),
            lager:debug(?LAGER_ATTRS,
                        "[~p] ~p Method = ~p, QsProplist = ~p, Body=~p",
                        [self(), ?MODULE, Method, QsProplist, Body]),
            case Method of
                <<"PUT">> when Id =:= undefined; R =:= undefined ->
                    {false, Req1, State};
                _ ->
                    handle_http_post_request(Method, Body, QsProplist,
                                             R, Id, M, Req1, State, S,
                                             <<"application/x-erlang-binary">>)
            end;
        _ ->
            %% timeout
            Req2 = cowboy_req:reply(
                           ?HTTP_REQUEST_TIMEOUT_CODE,
                           [{<<"content-type">>,
                             <<"application/x-erlang-binary">>}],
                           erlang:term_to_binary(
                             #{<<"error">> => 408,
                               <<"msg">> => <<"timeout">>}),
                           Req),
            {stop, Req2, State}
    end.

%% @private if the resource returned a brand new ID, set the value properly
%% for the location header.
post_maybe_expand({true, Id}, Req, _ContentType) ->
    Path = cowboy_req:path(Req),
    {{true, [Path, trail_slash(Path), Id]}, Req};
post_maybe_expand(Val, Req, ContentType) when is_map(Val) ->
    Req1 = cowboy_req:set_resp_header(
             <<"content-type">>, ContentType, Req),
    EncodedValue = case ContentType of
                       <<"application/x-erlang-binary">> ->
                           erlang:term_to_binary(Val);
                       <<"application/json">> ->
                           jiffy:encode(Val)
                   end,
    Req2 = cowboy_req:set_resp_body(EncodedValue, Req1),
    {true, Req2};
post_maybe_expand(Val, Req, ContentType) when is_binary(Val) ->
    Req1 = cowboy_req:set_resp_header(
             <<"content-type">>, ContentType, Req),
    Req2 = cowboy_req:set_resp_body(Val, Req1),
    {true, Req2};
post_maybe_expand(Val, Req, _ContentType) ->
    {Val, Req}.

trail_slash(Path) ->
    case binary:last(Path) of
        $/ -> "";
        _ -> "/"
    end.

handle_http_post_request(Method, Body, QsProplist, R, Id, M, Req1, State, S, ContentType) ->
    try
        lager:debug(?LAGER_ATTRS, "[~p] ~p ~p(~p, ~p, ~p, ~p)",
                    [self(), ?MODULE, M, Id, Body,
                     QsProplist, S]),
        DecodedBody = case is_erlang_content_type(ContentType) of
                          true ->
                              erlang:binary_to_term(Body, [safe]);
                          false ->
                              jiffy:decode(Body, [return_maps])
                      end,
        case {Method, M:validate(DecodedBody, S)} of
            {<<"POST">>, {true, S2}}
              when Id =:= undefined andalso R =:= undefined ->
                %% due to optimization, when repeated POST or
                %% PUT is used for an existing Id, the guard
                %% above refer to Id not being undefined. So,
                %% when Id is known then use M:update/4 and
                %% unconditionally overwrite key value.

                %% save http request for any possible streaming response
                erlang:put(?HTTP_REQ_KEY, Req1),
                {Res, S3} = M:create(Id, DecodedBody, S2),
                Req2 = erlang:erase(?HTTP_REQ_KEY),
                {NewRes, Req3} = case erlang:erase(?HTTP_IS_STREAM) of
                                     true ->
                                         {stop, Req2};
                                     _ ->
                                         post_maybe_expand(Res, Req2, ContentType)
                                 end,
                lager:debug(?LAGER_ATTRS, "[~p] ~p Result = ~p",
                            [self(), ?MODULE, {NewRes, Req3}]),
                {NewRes, Req3, State#state{model_state=S3}};
            {Method, {true, S2}} when
                Method =:= <<"POST">>
                orelse Method =:= <<"PUT">> ->
                %% save http request for any possible streaming response
                erlang:put(?HTTP_REQ_KEY, Req1),
                {Res, S3} = M:update(Id, DecodedBody, S2),
                Req2 = erlang:erase(?HTTP_REQ_KEY),
                {NewRes, Req3} = case erlang:erase(?HTTP_IS_STREAM) of
                                     true ->
                                         {stop, Req2};
                                     _ ->
                                         post_maybe_expand(Res, Req2, ContentType)
                                 end,
                {NewRes, Req3, State#state{model_state=S3}};
            {_, {false, S2}} ->
                {false, Req1, State#state{model_state=S2}}
        end
    catch
        error:badarg:StackTrace ->
            erlang:erase(?HTTP_REQ_KEY),
            erlang:erase(?HTTP_IS_STREAM),
            lager:error(?LAGER_ATTRS, "[~p] ~p error:badarg stacktrace = ~p",
                        [self(), ?MODULE, StackTrace]),
            {false, Req1, State}
    end.

read_http_post_body(Req) ->
    %% see https://ninenines.eu/docs/en/cowboy/2.0/guide/req_body/
    %%{Length, Req0} = cowboy_req:body_length(Req),
    %% {read_length, 12 * 1020 * 1024}, could use this setting as well
    %% read_timeout is in milliseconds
    {HttpMaxReadBytes, HttpMaxReadTimeoutMsec} =
        case application:get_env(?APPLICATION_NAME, http_rest) of
            {ok, HttpRestConfig} ->
                A = proplists:get_value(max_read_length,
                    HttpRestConfig, ?DEFAULT_MAX_HTTP_READ_BYTES),
                B = proplists:get_value(max_read_timeout_msec,
                    HttpRestConfig, ?DEFAULT_MAX_HTTP_READ_TIMEOUT_MSEC),
                {A, B};
            _ -> {?DEFAULT_MAX_HTTP_READ_BYTES,
                ?DEFAULT_MAX_HTTP_READ_TIMEOUT_MSEC}
        end,
    Options = #{length => HttpMaxReadBytes, timeout => HttpMaxReadTimeoutMsec},
    cowboy_req:read_body(Req, Options).

is_erlang_content_type(<<"application/x-erlang-binary">>) -> true;
is_erlang_content_type(_) -> false.

