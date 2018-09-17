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
-module(egraph_compression_util).
-author("neerajsharma").

-export([serialize_data/2,
         deserialize_data/1]).


serialize_data(Details, PreferredCompressionId) ->
    Data = erlang:term_to_binary(Details),
    serialize_data_internal(Data, PreferredCompressionId).

%% TODO: Optimize and cache the max dictionary key instead
%% of retrieving this info from database each time. Note that
%% approprate TTL must be associated with the data though.
serialize_data_internal(Data, undefined) ->
    case egraph_dictionary_model:read_max_resource() of
        {ok, M} ->
            #{ <<"id">> := Key,
               <<"dictionary">> := Dictionary } = M,
            compress_data(Data, Key, Dictionary);
        _ ->
            %% no compression
            %% TODO: What if the database connection is down then we'll land here
            %% as well, but then there are other issues to tackle.
            R3 = egraph_zlib_util:dict_deflate(0, Data),
            iolist_to_binary(R3)
    end;
serialize_data_internal(Data, PreferredCompressionId) ->
    case egraph_zlib_util:dict_deflate(PreferredCompressionId, Data) of
        {error, _} ->
            case egraph_dictionary_model:read_resource(PreferredCompressionId) of
                {ok, [M]} ->
                    #{ <<"id">> := Key,
                       <<"dictionary">> := Dictionary } = M,
                    egraph_zlib_util:load_dicts([{Key, Dictionary}]),
                    R = egraph_zlib_util:dict_deflate(Key, Data),
                    iolist_to_binary(R);
                _ ->
                    serialize_data_internal(Data, undefined)
            end;
        R2 ->
            iolist_to_binary(R2)
    end.

compress_data(Data, Key, Dictionary) ->
    case egraph_zlib_util:dict_deflate(Key, Data) of
        {error, _} ->
            egraph_zlib_util:load_dicts([{Key, Dictionary}]),
            R = egraph_zlib_util:dict_deflate(Key, Data),
            iolist_to_binary(R);
        R2 ->
            iolist_to_binary(R2)
    end.

deserialize_data(Data) ->
    case egraph_zlib_util:dict_inflate(Data) of
        {error, _} ->
            Key = egraph_zlib_util:extract_key(Data),
            case egraph_dictionary_model:read_resource(Key) of
                {ok, [M]} ->
                    #{ <<"id">> := Key,
                       <<"dictionary">> := Dictionary } = M,
                    egraph_zlib_util:load_dicts([{Key, Dictionary}]),
                    {ok, {_, UncompressedData}} = egraph_zlib_util:dict_inflate(Data),
                    erlang:binary_to_term(iolist_to_binary(UncompressedData));
                E ->
                    E
            end;
        {ok, {_, UncompressedData2}} ->
            erlang:binary_to_term(iolist_to_binary(UncompressedData2))
    end.


