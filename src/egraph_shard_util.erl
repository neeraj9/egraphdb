%%%-------------------------------------------------------------------
%%% @author Neeraj Sharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
%%% A collection of shard utilities which are generally useful.
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
-module(egraph_shard_util).
-author("Neeraj Sharma").

-include("egraph_constants.hrl").

%% dont need traceability for these functions
%%-compile([native, {hipe, [o3]}]).

%% API

-export([
        convert_xxhash_bin_to_integer/1
        ,convert_integer_to_xxhash_bin/1
        ,sharded_id/2
        ,sharded_tablename/2
        ,sharded_tablename/3
        ,base_table_name/1
        ,key_datatype/1
        ,convert_key_to_datatype/2
        ,convert_dbkey_to_datatype_json/1
        ]).


convert_xxhash_bin_to_integer(V) ->
    <<IntValue:64>> = V,
    IntValue.

convert_integer_to_xxhash_bin(V) ->
    <<V:64>>.

sharded_tablename(IndexName, BaseTableName) ->
    iolist_to_binary([BaseTableName, <<"_">>, IndexName]).

sharded_id(key, Key) ->
    <<_:53, ShardKey:11>> = Key,
    ShardKey.

sharded_tablename(key, Key, BaseTableName) ->
    <<_:53, ShardKey:11>> = Key,
    Suffix = integer_to_binary(ShardKey),
    iolist_to_binary([BaseTableName, <<"_">>, Suffix]);
sharded_tablename(shard_id, ShardKey, BaseTableName) ->
    Suffix = integer_to_binary(ShardKey),
    iolist_to_binary([BaseTableName, <<"_">>, Suffix]).

base_table_name(<<"text">>) -> ?EGRAPH_TABLE_LOOKUP_TEXT_BASE;
base_table_name(<<"int">>) -> ?EGRAPH_TABLE_LOOKUP_INT_BASE;
base_table_name(<<"geo">>) -> ?EGRAPH_TABLE_LOOKUP_GEO_BASE;
base_table_name(<<"double">>) -> ?EGRAPH_TABLE_LOOKUP_DOUBLE_BASE;
base_table_name(<<"datetime">>) -> ?EGRAPH_TABLE_LOOKUP_DATETIME_BASE;
base_table_name(<<"date">>) -> ?EGRAPH_TABLE_LOOKUP_DATE_BASE.

key_datatype(#{
  <<"type">> := <<"Point">>,
  <<"coordinates">> := [_Lon, _Lat]}) ->
    <<"geo">>;
key_datatype(K) when is_binary(K) ->
    try
        case byte_size(K) == 10 of
            true ->
                egraph_util:convert_binary_to_date(K),
                <<"date">>;
            false ->
                egraph_util:convert_binary_to_datetime(K),
                <<"datetime">>
        end
    catch
        _:_ ->
            <<"text">>
    end;
key_datatype(K) when is_integer(K) ->
    <<"int">>;
key_datatype(K) when is_float(K) ->
    <<"double">>;
key_datatype({{_, _, _}, {_, _, _}} =  _K) ->
    <<"datetime">>;
key_datatype({_, _, _} =  _K) ->
    <<"date">>.

convert_key_to_datatype(<<"text">>, K) ->
    egraph_util:convert_to_binary(K);
convert_key_to_datatype(<<"int">>, K) ->
    egraph_util:convert_to_integer(K);
convert_key_to_datatype(<<"geo">>,
                        #{
                            <<"type">> := <<"Point">>,
                            <<"coordinates">> := [_Lon, _Lat]} = K) ->
    jiffy:encode(K);
convert_key_to_datatype(<<"double">>, K) ->
    egraph_util:convert_to_float(K);
convert_key_to_datatype(<<"datetime">>, K) ->
    egraph_util:convert_binary_to_datetime(K);
convert_key_to_datatype(<<"date">>, K) ->
    egraph_util:convert_binary_to_date(K).

convert_dbkey_to_datatype_json({{_, _, _}, {_, _, _}} = K) ->
    egraph_util:convert_datetime_to_binary(K);
convert_dbkey_to_datatype_json({_, _, _} = K) ->
    egraph_util:convert_date_to_binary(K);
convert_dbkey_to_datatype_json(K) ->
    K.

