%%%-------------------------------------------------------------------
%%% @author neerajsharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%% Provide very high performance dictionary based compression
%%% utility.
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
-module(egraph_zlib_util).
-author("Neeraj Sharma").

-include("egraph_constants.hrl").

%% do not include the header
-define(WINDOW_BITS, -15).
%% change to best_speed for least cpu intensive
-define(ZLIB_COMPRESSION_LEVEL, best_speed).
%% -define(ZLIB_COMPRESSION_LEVEL, best_compression).
%% use as much memory possible to reduce time taken
-define(MEMORY_LEVEL, 9).

%% API
-export([init_zlib_dictionaries/0,
         load_dicts/1,
         get_zlib_dictionary/1,
         extract_key/1,
         dict_deflate/2,
         dict_inflate/1,
         dict_deflate_open/1]).

-type keys() :: integer().

%% @doc
%% Must be called only once after the application is started.
-spec init_zlib_dictionaries() -> ok.
init_zlib_dictionaries() ->
    ets:new(?EGRAPH_ZLIB_DICTS_TABLE_NAME,
            [set,
             public,
             named_table,
             {write_concurrency, true},
             {read_concurrency, true}]).

load_dicts([]) ->
    ok;
load_dicts([{Key, Dictionary} | Rest]) ->
    true = ets:insert(?EGRAPH_ZLIB_DICTS_TABLE_NAME, {Key, Dictionary}),
    load_dicts(Rest).

%% @doc
%% Get zlib dictionary for a given key.
-spec get_zlib_dictionary(Key :: keys()) -> binary() | none | {error, not_found}.
get_zlib_dictionary(Key) ->
    %% Drop the most significant bit, which is used for special
    %% purpose to detect content type
    %% Key2 = Key band 16#EF,
    <<_:1, Key2:15>> = <<Key:16>>,
    case Key2 of
        0 ->
            none;
        _ ->
            V = ets:lookup(?EGRAPH_ZLIB_DICTS_TABLE_NAME, Key2),
            case V of
                [{Key2, Dictionary}] -> Dictionary;
                [] -> {error, not_found}
            end
    end.

-spec extract_key(binary()) -> integer().
extract_key(Data) ->
    %% Drop the most significant bit, which is used for special
    %% purpose to detect content type
    %% Key2 = Key band 16#EF,
    <<_:1, Key2:15, _/binary>> = Data,
    Key2.

-spec dict_deflate(Key :: integer(), Data :: iodata()) -> iolist() | {error, not_supported}.
dict_deflate(Key, Data) ->
    case get_zlib_dictionary(Key) of
        none ->
            [<<Key:16>> | Data];
        _ ->
            Resp = dict_deflate_open(Key),
            case Resp of
                Z when is_reference(Z) orelse is_port(Z) ->
                    Compressed = zlib:deflate(Z, Data, finish),
                    ok = zlib:deflateEnd(Z),
                    ok = zlib:close(Z),
                    [<<Key:16>> | Compressed];
                Error -> Error
            end
    end.

-spec dict_inflate(PackedData :: iodata()) -> {ok, {Key :: integer(), Data :: iolist()}} | {error, not_supported}.
dict_inflate(PackedData) ->
    <<Key:16, Compressed/binary>> = PackedData,
    Resp = get_zlib_dictionary(Key),
    case Resp of
        none ->
            %% Data is not compressed
            {ok, {Key, Compressed}};
        Dictionary when is_binary(Dictionary) ->
            Z = zlib:open(),
            ok = zlib:inflateInit(Z, ?WINDOW_BITS),
            zlib:inflateSetDictionary(Z, Dictionary),
            Data = zlib:inflate(Z, Compressed),
            ok = zlib:inflateEnd(Z),
            ok = zlib:close(Z),
            {ok, {Key, Data}};
        Error -> Error
    end.

%% @doc
%% Can use this function to open a single zlib port for
%% deflating multiple items, one after the other thereby
%% saving some micro-seconds. Although its usefulness is
%% arguable considering that it takes a lot more time to
%% deflate data rather than open zlib port and work with
%% it for each of the data independently.
-spec dict_deflate_open(Key :: integer()) -> port() | {error, not_supported}.
dict_deflate_open(Key) ->
    Z = zlib:open(),
    ok = zlib:deflateInit(Z, ?ZLIB_COMPRESSION_LEVEL, deflated, ?WINDOW_BITS, ?MEMORY_LEVEL, default),
    Dictionary = get_zlib_dictionary(Key),
    case is_binary(Dictionary) of
        true ->
            Adler32 = zlib:deflateSetDictionary(Z, Dictionary),
            true = is_integer(Adler32),
            Z;
        false ->
            {error, not_supported}
    end.

