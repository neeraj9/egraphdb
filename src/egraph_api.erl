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
-module(egraph_api).
-author("neerajsharma").

-include("egraph_constants.hrl").

%% API
-export([
         get_detail_fold/3
         ,get_detail_concurrent_fold/2
         ,http_client_accept_content_type/1
         ,http_stream_reply/2
         ,http_stream_body/2
         ,concurrent_stream_node_csv/4
         ,stream_node_csv/5
         ,stream_node_csv/3
         ,stream_node_json/5
         ,stream_node_json/6
         ,stream_selected_node_json/5
         ,stream_node_x_erlang_stream_binary/5
         ,stream_selected_node_x_erlang_stream_binary/4
         ,search_id/3
         ,search_id/1
         ,encode_erlang_stream_binary/1
         ,decode_erlang_stream_binary/1
         ,recursive_get_destination/3
        ]).


-spec get_detail_fold(Fun :: fun((Id :: binary(), Acc :: list()) -> [term()]),
                      InitialAcc :: list(),
                      Ids :: [binary()]) -> [term()].
get_detail_fold(Fun, InitialAcc, Ids) when is_function(Fun, 2) andalso is_list(Ids) ->
    %% return [map()]
    MappingInfo = lists:foldl(fun(E, AccIn) ->
                        ShardId = egraph_shard_util:sharded_id(key, E),
                        OldVal = maps:get(ShardId, AccIn, []),
                        AccIn#{ShardId => [E | OldVal]}
                end, #{}, Ids),
    maps:fold(fun(_K, {error, _}, AccIn) ->
                      AccIn;
                 (_K, V, AccIn) ->
                  case egraph_detail_model:read_resources(V) of
                      {error, _} ->
                          AccIn;
                      R ->
                          lists:foldl(Fun, AccIn, R)
                  end
              end, InitialAcc, MappingInfo).

get_detail_concurrent_fold(Fun, Ids) when is_function(Fun, 2) andalso is_list(Ids) ->
    %% return [map()]
    MappingInfo = lists:foldl(fun(E, AccIn) ->
                        ShardId = egraph_shard_util:sharded_id(key, E),
                        OldVal = maps:get(ShardId, AccIn, []),
                        AccIn#{ShardId => [E | OldVal]}
                end, #{}, Ids),
    MappingInfoSize = maps:size(MappingInfo),
    ListOfIds = maps:values(MappingInfo),
    %% TODO move setting to dynamic config
    MaxActors = ?DEFAULT_EGRAPH_CONCURRENT_JOB_MAX_ACTORS,
    ProcessFun = fun(L) ->
                         lists:foldl(fun({error, _}, AccIn) ->
                                             AccIn;
                                        (E, AccIn) ->
                                             case egraph_detail_model:read_resources(E) of
                                                 {error, _} ->
                                                     AccIn;
                                                 R ->
                                                     lists:foldl(Fun, AccIn, R)
                                             end
                                     end, [], L)
                 end,
    case MappingInfoSize div MaxActors of
        0 ->
            ProcessFun(ListOfIds);
        NumElementsPerSegment ->
            Segments = egraph_util:segments(NumElementsPerSegment, ListOfIds),
            Tasks = [{ProcessFun, [X]} || X <- Segments],
            %% TODO Move timeout to dynamic config
            TimeoutMsec = ?DEFAULT_EGRAPH_CONCURRENT_JOB_TIMEOUT_MSEC,
            lists:flatten(
              egraph_concurrent_util:run_concurrent(
                Tasks, TimeoutMsec))
    end.

http_client_accept_content_type(ContentType) ->
    case erlang:get(?HTTP_REQ_KEY) of
        undefined -> false;
        Req ->
            ContentTypesAccepted = egraph_http_util:http_accept_types(Req),
            lists:member(string:lowercase(ContentType),
                         ContentTypesAccepted)
    end.

http_stream_reply(Code, ContentType) ->
    case erlang:get(?HTTP_REQ_KEY) of
        undefined -> error;
        Req ->
            erlang:put(?HTTP_IS_STREAM, true),
            Req2 = cowboy_req:stream_reply(
                     Code,
                     #{<<"content-type">> => ContentType},
                     Req),
            erlang:put(?HTTP_REQ_KEY, Req2),
            ok
    end.

http_stream_body(Data, Opt) when Opt == nofin orelse Opt == fin ->
    case erlang:get(?HTTP_IS_STREAM) of
        true ->
            Req = erlang:get(?HTTP_REQ_KEY),
            cowboy_req:stream_body(Data, Opt, Req),
            ok;
        _ ->
            error
    end.

%% @doc Concurrent Streaming Search for index and retrive direct and first level
%%      indirect nodes attributes.
%%
%% (<<"abc@123.com">>, <<"text">>, <<"email">>, [ ["email"], ["info", "full_name"] ])
%%
%% fun(binary(), binary(), binary(), [[binary()]]) -> [map()].
concurrent_stream_node_csv(Key, KeyType, IndexName, SelectedPaths) ->
	stream_node_csv(Key, KeyType, IndexName, SelectedPaths, true).

stream_node_csv(Key, KeyType, IndexName, SelectedPaths, IsConcurrent) ->
    Ids = search_id(Key, KeyType, IndexName),
    stream_node_csv(Ids, SelectedPaths, IsConcurrent).

stream_node_csv(Ids, SelectedPaths, IsConcurrent) ->
    %% validate content type
    %%A = http_client_accept_content_type(<<"*/*">>),
    %%B = http_client_accept_content_type(<<"text/csv">>),
    %%true = (A orelse B),

    %% content type must be managed here instead of egraph
    http_stream_reply(200, <<"text/csv">>),
    [_ | CsvHeader] = maps:fold(fun(AsName, _E, AccIn) ->
                                    [<<",">>, AsName | AccIn]
                                  end, [], SelectedPaths),
    http_stream_body(iolist_to_binary(CsvHeader), nofin),

    Fun = fun(Info, _AccIn) ->
             Cols = maps:fold(fun(_AsName, JsonPath, AccIn3) ->
                          [<<",">>, nested:get(JsonPath, Info) | AccIn3]
                                 end, [], SelectedPaths),
             [_ | Serialized] = Cols,
             http_stream_body([<<"\n">>, iolist_to_binary(Serialized)], nofin),
             []
           end,

    case IsConcurrent of
        true -> get_detail_concurrent_fold(Fun, Ids);
        false -> get_detail_fold(Fun, [], Ids)
    end,

    http_stream_body(<<"">>, fin),
    ok.

recursive_get_destination(SourceId, Depth, MaxDepth) when MaxDepth >= Depth ->
    lager:debug("recursive_get_destination(~p, ~p, ~p)", [SourceId, Depth, MaxDepth]),
    GetDetailsFun = fun(DestinationInfo, AccIn2) ->
                            lager:debug("DestinationInfo = ~p", [DestinationInfo]),
                            DestinationId = maps:get(<<"source">>, DestinationInfo),
                            UpdatedDestinationInfo = DestinationInfo#{
                                                       <<"__destinations">> =>
                                                         recursive_get_destination(
                                                           egraph_util:hex_binary_to_bin(DestinationId), Depth + 1, MaxDepth)},
                            AccIn2#{DestinationId => UpdatedDestinationInfo}
                    end,
    case egraph_link_model:search(SourceId, destination_info) of
        {ok, DestinationLinkInfos} ->
            lager:debug("[] DestinationLinkInfos = ~p", [DestinationLinkInfos]),
            DestinationIds = lists:foldl(fun(E, AccIn) ->
                                                 [egraph_util:hex_binary_to_bin(maps:get(<<"destination">>, E)) | AccIn]
                                         end, [], DestinationLinkInfos),
            DetailsMapping = egraph_api:get_detail_fold(GetDetailsFun, #{}, DestinationIds),
            lists:foldl(fun(DestinationLinkInfo, AccIn) ->
                                DestinationId = maps:get(<<"destination">>, DestinationLinkInfo),
                                [DestinationLinkInfo#{<<"__node_details">> => maps:get(DestinationId, DetailsMapping, #{})} | AccIn]
                        end, [], DestinationLinkInfos);
        _ ->
            []
    end;
recursive_get_destination(_SourceId, _Depth, _MaxDepth) ->
    [].

%% do not find destinations which are connected with default call
stream_node_json(Key, KeyType, IndexName, SelectedPaths, IsConcurrent) ->
    stream_node_json(Key, KeyType, IndexName, SelectedPaths, IsConcurrent, 0).

stream_node_json(Key, KeyType, IndexName, SelectedPaths, IsConcurrent, MaxDepth) ->
    Ids = search_id(Key, KeyType, IndexName),
    stream_selected_node_json(Ids, [], SelectedPaths, IsConcurrent, MaxDepth).

stream_selected_node_json(Ids, Filters, SelectedPaths, IsConcurrent, MaxDepth) ->
    %% content type must be managed here instead of egraph
    http_stream_reply(200, <<"application/json">>),
    http_stream_body(<<"[">>, nofin),

    %% Note that IndexJsonPath is of type [binary()]
    %% and Key is of type [key_type()] | key_type(), where
    %% key_type() :: binary() | integer() | float() | geo_type()
    %% and geo_type() :: #{<<"type">> := <<"Point">>, <<"coordinates">> := [float(), float()]}
    ProcessedFilters = lists:foldr(fun(#{<<"key">> := Key,
                                         <<"key_type">> := KeyType,
                                         <<"index_json_path">> := IndexJsonPath}, AccIn) ->
                                           [{Key, KeyType, IndexJsonPath} | AccIn]
                                   end, [], Filters),

    Fun = fun(Info, _AccIn) ->
                  case is_filtered(ProcessedFilters, Info) of
                      true ->
                          Proplists = maps:fold(fun(AsName, JsonPath, AccIn3) ->
                                       %% NestedKey = iolist_to_binary(lists:join(<<".">>, JsonPath)),
                                       %% NestedKey = lists:last(JsonPath),
                                       [{AsName, nested:get(JsonPath, Info, null)} | AccIn3]
                                              end, [], SelectedPaths),
                          Info2 = maps:from_list(Proplists),
                          SourceId = maps:get(<<"source">>, Info),
                          Info3 = case MaxDepth >= 0 of
                                      false ->
                                          Info2;
                                      true ->
                                          Info2#{
                                            <<"__destinations">> =>
                                            recursive_get_destination(
                                              SourceId, 1, MaxDepth)}
                                  end,
                          Serialized = jiffy:encode(Info3),
                          http_stream_body([iolist_to_binary(Serialized), <<",">>], nofin),
                          [];
                      false ->
                          []
                  end
          end,

    case IsConcurrent of
        true -> get_detail_concurrent_fold(Fun, Ids);
        false -> get_detail_fold(Fun, [], Ids)
    end,

    %% Note: The last map in response list is empty, so that
    %% all the others can just attach "{...}," and not worry
    %% about being last one (which must not have a comma at the end).
    http_stream_body(<<"{}]">>, fin),
    ok.

stream_node_x_erlang_stream_binary(Key, KeyType, IndexName, SelectedPaths, IsConcurrent) ->
    Ids = search_id(Key, KeyType, IndexName),
    stream_selected_node_x_erlang_stream_binary(
      Ids, [], SelectedPaths, IsConcurrent).

stream_selected_node_x_erlang_stream_binary(Ids, Filters, SelectedPaths, IsConcurrent) ->
    %% Note that IndexJsonPath is of type [binary()]
    %% and Key is of type [key_type()] | key_type(), where
    %% key_type() :: binary() | integer() | float() | geo_type()
    %% and geo_type() :: #{<<"type">> := <<"Point">>, <<"coordinates">> := [float(), float()]}
    ProcessedFilters = lists:foldr(fun(#{<<"key">> := Key,
                                         <<"key_type">> := KeyType,
                                         <<"index_json_path">> := IndexJsonPath}, AccIn) ->
                                           [{Key, KeyType, IndexJsonPath} | AccIn]
                                   end, [], Filters),

    %% validate content type
    %%A = http_client_accept_content_type(<<"*/*">>),
    %%B = http_client_accept_content_type(<<"application/x-erlang-stream-binary">>),
    %%true = (A orelse B),

    %% content type must be managed here instead of egraph
    %% IMPORTANT: x-erlang-stream-binary is different from x-erlang-binary
    %%            wherein the former has a 16 bit length encoded before
    %%            the bytes which must be erlang term decoded.
    http_stream_reply(200, <<"application/x-erlang-stream-binary">>),
    StreamHeader = maps:fold(fun(K, _, AccIn) -> [K | AccIn] end, [], SelectedPaths),
    http_stream_body(encode_erlang_stream_binary(StreamHeader), nofin),

    Fun = fun(Info, _AccIn) ->
                  case is_filtered(ProcessedFilters, Info) of
                      true ->
                          Cols = maps:fold(fun(_AsName, JsonPath, AccIn3) ->
                              [nested:get(JsonPath, Info, null) | AccIn3]
                                           end, [], SelectedPaths),
                          Serialized = encode_erlang_stream_binary(Cols),
                          http_stream_body(Serialized, nofin),
                          [];
                      false ->
                          []
                  end
           end,

    case IsConcurrent of
        true -> get_detail_concurrent_fold(Fun, Ids);
        false -> get_detail_fold(Fun, [], Ids)
    end,

    http_stream_body(<<>>, fin),
    ok.


search_id(Key, KeyType, IndexName) ->
     case Key of
         [KeyStart, KeyEnd] ->
             case egraph_index_model:search({KeyStart, KeyEnd}, KeyType, IndexName) of
                 {ok, FoundIds} -> FoundIds;
                 _ -> []
             end;
         _ ->
             case egraph_index_model:search(Key, KeyType, IndexName) of
                 {ok, FoundIds} -> FoundIds;
                 _ -> []
             end
     end.

search_id(Conditions) ->
    AllIds = lists:foldl(fun(#{<<"key">> := Key,
                               <<"key_type">> := KeyType,
                               <<"index_name">> := IndexName} = _Criteria, AccIn) ->
                                 FoundIds = search_id(Key, KeyType, IndexName),
                                 [FoundIds | AccIn]
                         end, [], Conditions),
    lists:usort(lists:flatten(AllIds)).

-spec encode_erlang_stream_binary(term()) -> binary().
encode_erlang_stream_binary(Term) ->
    EncodingOpts = [compressed],
    V = erlang:term_to_binary(Term, EncodingOpts),
    Size = byte_size(V),
    <<Size:16, V/binary>>.

-spec decode_erlang_stream_binary(binary()) -> {term(), binary()} | partial.
decode_erlang_stream_binary(<<Size:16, V:Size/binary, Rest/binary>> = _Bin) ->
    {erlang:binary_to_term(V), Rest};
decode_erlang_stream_binary(_Bin) ->
    partial.



%% TODO: This will not work for KeyType == <<"geo">>
is_filtered([], _Info) ->
    true;
is_filtered([{[KeyStart, KeyEnd], KeyType, IndexJsonPath} | Rest], Info) ->
    StartV1 = egraph_shard_util:convert_key_to_datatype(KeyType, KeyStart),
    EndV1 = egraph_shard_util:convert_key_to_datatype(KeyType, KeyEnd),
    Value = nested:get(IndexJsonPath, Info),
    V2 = egraph_shard_util:convert_key_to_datatype(KeyType, Value),
    case (V2 >= StartV1) andalso (V2 =< EndV1) of
        true -> is_filtered(Rest, Info);
        false -> false
    end;
is_filtered([{Key, KeyType, IndexJsonPath} | Rest], Info) ->
    V1 = egraph_shard_util:convert_key_to_datatype(KeyType, Key),
    Value = nested:get(IndexJsonPath, Info),
    V2 = egraph_shard_util:convert_key_to_datatype(KeyType, Value),
    case V2 == V1 of
        true -> is_filtered(Rest, Info);
        false -> false
    end.

