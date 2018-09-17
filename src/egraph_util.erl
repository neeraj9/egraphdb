%%%-------------------------------------------------------------------
%%% @author Neeraj Sharma
%%% @copyright (C) 2016, Neeraj Sharma
%%% @doc
%%% A collection of generic utilities which are generally useful.
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
-module(egraph_util).
-author("Neeraj Sharma").

-include("egraph_constants.hrl").

%% dont need traceability for these functions
%%-compile([native, {hipe, [o3]}]).

%% API
-export([get_utc_date/0, get_utc_datetime/0, get_utc_seconds/0,
         get_utc_microseconds/0, get_utc_milliseconds/0]).
-export([extract_qs_val/2]).
-export([epoch_now_printable_binary/0]).

-export([bin_to_hex_binary/1,
         bin_to_hex_binary_slow/1,
         create_salt/1,
         hash_password/2,
         hash_password_hmac/3]).

-export([map_has_keys/2, map_has_any_key/2, map_multiple_put/3]).

-export([is_an_integer/1, convert_to_integer/1]).

-export([convert_to_float/1]).

-export([convert_to_boolean/1]).

-export([convert_to_binary/1, convert_to_list/1]).

-export([convert_to_lower/1]).

-export([join_list_of_binary/2]).

-export([round/1]).

-export([
    get_custom_uuid/0,
    get_custom_uuid/1,
    get_custom_uuid/2,
    get_custom_uuid/4,
    extract_tsmicro_from_uuid/1,
    extract_datetime_from_uuid/1,
    epoc_tsmicro_to_datetime/1,
    datetime_to_epoc_tsmicro/1,
    extract_data_from_uuid/1,
    get_custom_id/0, get_custom_id/1,
    extract_datetime_from_id/1,
    extract_partial_node_crc32/1,
    extract_partial_crc32node_from_uuid/1]).

-export([hexstr_to_binary/1]).
-export([merge_map_recursive/3,
         merge_map_recursive_ignore_undefined/3,
         maps_keys_to_remove/2,
         deep_merge/3,
    update_list_with_list_of_keys/4]).

-export([construct_bit_flag/1]).

-export([convert_if_not_list/1]).

-export([is_undefined/1, is_undefined_or_empty/1]).
-export([is_nil_or_empty/1, remove_nil_map_keys_recursively/1]).
-export([remove_null_map_keys_recursively/1]).
-export([validate_map_recursive/2]).

-export([convert_datetime_for_json_encoding/1,
         convert_uuid_for_json_encoding/2,
         convert_uuid_for_json_encoding/3,
         convert_from_json_to_uuid_binary/2]).

-export([hex_binary_to_bin/1]).

-export([convert_to_map/1]).

-export([convert_first_char_to_lowercase/1]).

-export([get_first_field/1, get_first_field/2]).

-export([pack_contents/1, unpack_contents/2]).

-export([add_version_into_details/2, get_version/1]).

-export([mget/3, nmget/3]).

-export([minus_hours/2, minus_minutes/2, minus_months/2]).

-export([tz_datetime_to_epoc/4,
         tz_datetime_to_utc/3,
         tz_datetime_to_utc/2,
         utc_to_tz_datetime/2]).

-export([convert_map_values/2]).

-export([epochsec_to_date_time/1,
         get_day_granular_intervals_between/2,
        epochmsec_to_date_time/1,
        date_time_to_json_string/1]).

-export([convert_for_csv_value/1]).
-export([convert_for_json_encoding/1,
         convert_xml_to_json_map/1]).

-export([node_uptime/1
  , log_info/2
  , log_debug/2
  , db_mysql_query/8
  , db_redis_query/4
  , transport_make_http_get/4
  , diff/2
  , segments/2
  , convert_binary_to_datetime/1
  , convert_binary_to_date/1
  , convert_datetime_to_binary/1
  , convert_date_to_binary/1]).

-export([generate_hash_binary/1]).
-export([generate_xxhash_binary/1]).
-export([encode_json/1]).


-export_type([omega_uuid/0]).

-type omega_uuid() :: <<_:128>>.

%% calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
-define(GREGORIAN_SECONDS_EPOC_START, 62167219200).

%%--------------------------------------------------------------------
%% @doc Get current unixtime (time since epoch)
-spec get_utc_date() -> calendar:date().
get_utc_date() ->
    {Date, _} = get_utc_datetime(),
    Date.

%%--------------------------------------------------------------------
%% @doc Get current unixtime (time since epoch)
-spec get_utc_datetime() -> calendar:datetime().
get_utc_datetime() ->
    Seconds = egraph_util:get_utc_seconds(),
    GregorianSeconds = Seconds + ?GREGORIAN_SECONDS_EPOC_START,
    calendar:gregorian_seconds_to_datetime(GregorianSeconds).

%%--------------------------------------------------------------------
%% @doc Get current unixtime (time since epoch) as seconds.
%% @todo look at time-wrap
%% http://erlang.org/doc/apps/erts/time_correction.html#Time_Warp
-spec get_utc_seconds() -> pos_integer().
get_utc_seconds() ->
    erlang:system_time(second).

%%--------------------------------------------------------------------
%% @doc Get current unixtime (time since epoch) as microseconds.
%% @todo look at time-wrap
%% http://erlang.org/doc/apps/erts/time_correction.html#Time_Warp
-spec get_utc_microseconds() -> pos_integer().
get_utc_microseconds() ->
    erlang:system_time(microsecond).

%%--------------------------------------------------------------------
%% @doc Get current unixtime (time since epoch) as milliseconds.
%% @todo look at time-wrap
%% http://erlang.org/doc/apps/erts/time_correction.html#Time_Warp
-spec get_utc_milliseconds() -> pos_integer().
get_utc_milliseconds() ->
    erlang:system_time(millisecond).

%%--------------------------------------------------------------------
%% @doc
%% Extract a value within a list of tuples stored as [{Key, Value},...]
-spec extract_qs_val(binary(), list({binary(), binary() | true})) ->
    undefined | binary() | true.
extract_qs_val(_Key, []) ->
    undefined;
extract_qs_val(Key, [{Key, V} | _T] = _QsVals) ->
    V;
extract_qs_val(Key, [{_K, _V} | T] = _QsVals) ->
    extract_qs_val(Key, T).

%%--------------------------------------------------------------------
%% @doc
%% Get current timestamp as a printable binary.
%% @see os:timestamp/0
epoch_now_printable_binary() ->
    {Mega, Sec, _} = os:timestamp(),
    CurrentTimeSeconds = (Mega * 1000000 + Sec),
    list_to_binary(integer_to_list(CurrentTimeSeconds)).

%%--------------------------------------------------------------------
%% @doc
%% Convert a binary to textual representation of the same in hexadecimal
%% (small case) notation.
%% Prefer this instead of egraph_util:bin_to_hex_binary_slow/1 which is a
%% slower version.
bin_to_hex_binary(X) when is_binary(X) ->
    H = hex_combinations(),
    <<<<(element(V + 1, H)):16>> || <<V:8>> <= X>>.

%%--------------------------------------------------------------------
%% @doc
%% Convert a binary to a textual representation of the binary in
%% hexadecimal (small case) notation.
%% For better (faster) approach @see bin_to_hex_binary/1
bin_to_hex_binary_slow(B) when is_binary(B) ->
    T = {$0, $1, $2, $3, $4, $5, $6, $7, $8, $9, $a, $b, $c, $d, $e, $f},
    <<<<(element(X bsr 4 + 1, T)), (element(X band 16#0F + 1, T))>>
      || <<X:8>> <= B>>.

%%--------------------------------------------------------------------
%% @doc
%% convert a hex (in binary format) to binary while assuming that the
%% size of the hex binary must be a multiple of 2, where each
%% byte is represented by two characters.
%% This function uses fun hex_binary_to_bin_internal/2 internally,
%% which throws an exception when the input hex is not a valid
%% but this function catches exception and gives back error.
-spec hex_binary_to_bin(H :: binary()) -> binary() | undefined | error.
hex_binary_to_bin(H) when is_binary(H) andalso (byte_size(H) rem 2 == 0) ->
    %% Note that fun hex_binary_to_bin_internal/2 is tail recursive,
    %% but since that is a different function than the current, so
    %% tail call optimization should still happen even in protected
    %% portion of try..of..catch.
    %% It is important to note that we are not having recursion
    %% to fun hex_binary_to_bin/1 here, which would otherwise
    %% be not tail call optimized (due to need for keeping
    %% reference in case of exception).
    try
        list_to_binary(lists:reverse(hex_binary_to_bin_internal(H, [])))
    catch
        error:function_clause -> error
    end;
hex_binary_to_bin(undefined) ->
    undefined;
hex_binary_to_bin(_H) ->
    error.

%%--------------------------------------------------------------------
%% @doc
%% Create salt of N bytes, which tries to generate strong random bytes
%% for cryptography, but when the entropy is not good enough this
%% function falls back on creating uniform random number (which is
%% less secure).
-spec create_salt(N :: integer()) ->
    {ok, {strong, binary()}} |
    {ok, {uniform, binary()}}.
create_salt(N) ->
    %% fallback to uniform random number when entropy is not good enough
    %% although that is not a very good idea
    try
        {ok, {strong, crypto:strong_rand_bytes(N)}}
    catch
        _ -> {ok, {uniform, create_salt_uniform(N)}}
    end.


%%--------------------------------------------------------------------
%% @doc
%% Hash password via pbkdf2, with 128 iterations and SHA-256.
%% For less secure but faster version @see egraph_util:hash_password_hmac/3
-spec hash_password(binary(), binary()) -> {ok, binary()}.
hash_password(Password, Salt) ->
    Iterations = 128,
    DerivedLength = 32, % for SHA256
    {ok, _PasswordHash} =
    pbkdf2:pbkdf2(sha256, Password, Salt, Iterations, DerivedLength).

%%--------------------------------------------------------------------
%% @doc
%% Hash password via SHA-1 HMAC, which is very fast but less secure.
%% There are better ways of hashing password, one of them being
%% using the erlang-pbkdf2, erlang-bcrypt or erl-scrypt project.
%%
%% For more secure version @see egraph_util:hash_password/2
-spec hash_password_hmac(Key :: binary(), Password :: binary(),
                         Salt :: binary()) ->
                            {ok, binary()}.
hash_password_hmac(Key, Password, Salt) ->
    {ok, crypto:hmac(sha, Key, <<Password/binary, Salt/binary>>)}.

%%--------------------------------------------------------------------
%% @doc
%% Validates whether all the Keys provided exist in a Map.
-spec map_has_keys(Keys :: iolist(), Map :: map()) ->
    true |
    {false, binary()}.
map_has_keys([], Map) when is_map(Map) ->
    true;
map_has_keys([H | T] = _Keys, Map) when is_map(Map) ->
    case maps:is_key(H, Map) of
        false -> {false, H};
        true -> map_has_keys(T, Map)
    end.

map_multiple_put([], [], Map) when is_map(Map)->
    Map;
map_multiple_put([Key|RestKey], [Value|RestValue], Map) when is_map(Map) ->
    UpdatedMap = maps:put(Key, Value, Map),
    map_multiple_put(RestKey, RestValue, UpdatedMap).

%% @doc
%% Validates whether any Keys provided exist in a Map.
-spec map_has_any_key(Keys :: iolist(), Map :: map()) ->
    true |
    {false, binary()}.
map_has_any_key([], Map) when is_map(Map) ->
    false;
map_has_any_key([H | T] = _Keys, Map) when is_map(Map) ->
    case maps:is_key(H, Map) of
        true -> true;
        false -> map_has_any_key(T, Map)
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private
create_salt_uniform(N) ->
    <<<<(rand:uniform(255))>> || _X <- lists:seq(1, N)>>.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Find all possible combinations (sorted) of hexadecimal as a list
%% of integers (ordinal value of hex characters) from 0x00 till 0xff.
hex_combinations() ->
    H = [$0, $1, $2, $3, $4, $5, $6, $7, $8, $9, $a, $b, $c, $d, $e, $f],
    %<< <<((V1 bsl 8) + V2):16>> || V1 <- H, V2 <- H >>.
    list_to_tuple([((V1 bsl 8) + V2) || V1 <- H, V2 <- H]).


%%--------------------------------------------------------------------
%% @doc
%% Validate that the given input is either an integer or can be
%% converted to an integer.
-spec is_an_integer(X :: integer() | binary() | list()) -> boolean().
is_an_integer(X) when is_integer(X) ->
    true;
is_an_integer(X) when is_binary(X) ->
    try
        _ = binary_to_integer(X),
        true
    catch
        _Class:_Exception ->
            false
    end;
is_an_integer(X) when is_list(X) ->
    try
        _ = list_to_integer(X),
        true
    catch
        _Class:_Exception ->
            false
    end.

%%--------------------------------------------------------------------
%% @doc
%% Convert a given input to an integer in case it is not one
%% already. Only binary() and list are supported at present.
-spec convert_to_integer(X :: integer() | binary() | list()) -> integer().
convert_to_integer(X) when is_integer(X) ->
    X;
convert_to_integer(X) when is_binary(X) ->
    binary_to_integer(X);
convert_to_integer(X) when is_list(X) ->
    list_to_integer(X).

%%
%% @doc
-spec convert_to_float(X :: integer() | binary() | list() | float()) -> float().
convert_to_float(X) when is_integer(X) ->
    float(X);
convert_to_float(X) when is_binary(X) ->
    try
        binary_to_float(X)
    catch
        error:badarg -> float(binary_to_integer(X))
    end;
convert_to_float(X) when is_list(X) ->
    try
        list_to_float(X)
    catch
        error:badarg -> float(list_to_integer(X))
    end;
convert_to_float(X) when is_float(X) ->
    X.

%%--------------------------------------------------------------------
%% @doc
%% Convert a given input to boolean, which is basically an Erlang atom
%% or true or false. Although, the input could be a binary, list or
%% an atom.
convert_to_boolean(<<"true">>) ->
    true;
convert_to_boolean(<<"false">>) ->
    false;
convert_to_boolean(<<"TRUE">>) ->
    true;
convert_to_boolean(<<"FALSE">>) ->
    false;
convert_to_boolean(<<"True">>) ->
    true;
convert_to_boolean(<<"False">>) ->
    false;
convert_to_boolean("TRUE") ->
    true;
convert_to_boolean("FALSE") ->
    false;
convert_to_boolean("True") ->
    true;
convert_to_boolean("False") ->
    false;
convert_to_boolean("true") ->
    true;
convert_to_boolean("false") ->
    false;
convert_to_boolean(true) ->
    true;
convert_to_boolean(false) ->
    false.


%%--------------------------------------------------------------------
%% @doc
%% Join a list of binary to a single binary separated by Sep.
-spec join_list_of_binary(L :: list(binary()), Sep :: binary()) -> binary().
join_list_of_binary([], _Sep) ->
    <<>>;
join_list_of_binary([X], _Sep) ->
    X;
join_list_of_binary(L, Sep) when is_list(L) ->
    lists:foldr(fun(V1, V2) ->
        case bit_size(V2) of
            Val when Val > 0 -> <<V1/binary, Sep/binary, V2/binary>>;
            _ -> V1
        end
                end, <<>>, L).

%%--------------------------------------------------------------------
%% @doc
%% Generate a custom uuid, which has the following components not
%% available in standard UUID specification.
%% * Timestamp in microseconds
%% * CRC32 of Erlang node name
%% * Erlang Scheduler Id
%% * Two octets worth of user provided data
%%
%% Note that the intent of having a user provided data is to
%% enable segregation of UUID based on application specific
%% namespaces.
-spec get_custom_uuid(SchedulerId :: integer(), NodeNameCrc32 :: integer(),
                      TsMicro :: integer(), Data :: <<_:24>>) -> omega_uuid().
get_custom_uuid(SchedulerId, NodeNameCrc32,
                TsMicro, <<D1, D2, D3>> = _Data) when is_integer(TsMicro) ->
    <<S1>> = <<SchedulerId:8>>, % only take lower 8 bits
    %% generic way of encoding unknown bits is via binary:encode_unsigned/1
    <<C1, C2, C3, C4>> = extract_partial_node_crc32(NodeNameCrc32),
    %% Note that anything after 5236-03-31 21:21:00 will exceed 60 bits
    <<T1:12, T2:16, T3:32>> = <<TsMicro:60>>,
    <<T3:32, T2:16,
      1:1, 1:1, 1:1, 1:1,  % Custom version bits
      T1:12,
      C4, C3, C2, C1,
      S1,
      D3, D2, D1>>.

%%--------------------------------------------------------------------
%% @doc Get custom uuid based on given nodename, time in microseconds
%% and 24 bits worth of data.
-spec get_custom_uuid(NodeNameCrc32 :: integer(),
                      TsMicro :: integer(), Data :: <<_:24>>) -> omega_uuid().
get_custom_uuid(NodeNameCrc32, TsMicro, Data) when is_integer(TsMicro) ->
    SchedulerId = erlang:system_info(scheduler_id),
    get_custom_uuid(SchedulerId, NodeNameCrc32, TsMicro, Data).

%%--------------------------------------------------------------------
%% @doc Get custom uuid based on given time in microseconds
%% and 24 bits worth of data.
-spec get_custom_uuid(TsMicro :: integer(), Data :: <<_:24>>) -> omega_uuid().
get_custom_uuid(TsMicro, Data) when is_integer(TsMicro) ->
    NodeNameCrc32 = crc32_erlang_node(),
    get_custom_uuid(NodeNameCrc32, TsMicro, Data).

%%--------------------------------------------------------------------
%% @doc Get custom uuid based on current system time in microseconds
%% and given custom 24 bits.
-spec get_custom_uuid(Data :: <<_:24>>) -> omega_uuid().
get_custom_uuid(Data) when byte_size(Data) == 3 ->
    TsMicro = erlang:system_time(micro_seconds),
    get_custom_uuid(TsMicro, Data).

%%--------------------------------------------------------------------
%% @doc Get custom uuid based on current system time in microseconds.
-spec get_custom_uuid() -> omega_uuid().
get_custom_uuid() ->
    TsMicro = erlang:system_time(micro_seconds),
    get_custom_uuid(TsMicro, <<0, 0, 0>>).

%%--------------------------------------------------------------------
%% @doc Get custom id in integer
-spec get_custom_id(TsMicro :: integer()) -> integer().
get_custom_id(TsMicro) ->
    SchedulerId = erlang:system_info(scheduler_id),
    %% have timestamp on higher bit position, so that sorting based
    %% on timestamp is possible
    ((TsMicro band 16#0fffffffffffffff) bsl 3) bor (SchedulerId band 16#07).

%%--------------------------------------------------------------------
%% @doc
-spec get_custom_id() -> integer().
get_custom_id() ->
    TsMicro = erlang:system_time(micro_seconds),
    get_custom_id(TsMicro).

%%--------------------------------------------------------------------
%% @doc
%% Extract timestamp in micro seconds from custom Uuid created
%% via get_custom_uuid function.
-spec extract_tsmicro_from_uuid(Uuid :: omega_uuid()) -> integer().
extract_tsmicro_from_uuid(Uuid) when is_binary(Uuid) ->
    <<T3:32, T2:16,
      1:1, 1:1, 1:1, 1:1,
      T1:12, _/binary>> = Uuid,
    <<TsMicro:60>> = <<T1:12, T2:16, T3:32>>,
    TsMicro.

%%--------------------------------------------------------------------
%% @doc
%% Extract datetime from custom Uuid created
%% via get_custom_uuid function.
-spec extract_datetime_from_uuid(Uuid :: omega_uuid()) -> calendar:datetime().
extract_datetime_from_uuid(Uuid) when is_binary(Uuid) ->
    TsMicro = extract_tsmicro_from_uuid(Uuid),
    Seconds = TsMicro div 1000000,
    GregorianSeconds = Seconds + ?GREGORIAN_SECONDS_EPOC_START,
    calendar:gregorian_seconds_to_datetime(GregorianSeconds).

%%--------------------------------------------------------------------
%% @doc
%% Convert epoc timestamp in microsecond to datetime.
-spec epoc_tsmicro_to_datetime(TsMicro :: integer()) -> calendar:datetime().
epoc_tsmicro_to_datetime(TsMicro) ->
    Seconds = TsMicro div 1000000,
    GregorianSeconds = Seconds + ?GREGORIAN_SECONDS_EPOC_START,
    calendar:gregorian_seconds_to_datetime(GregorianSeconds).

%%--------------------------------------------------------------------
%% @doc
%% Convert datetime to epoc timestamp in microsecond.
-spec datetime_to_epoc_tsmicro(DateTime :: calendar:datetime()) -> integer().
datetime_to_epoc_tsmicro(DateTime) ->
    GregorianSeconds = calendar:datetime_to_gregorian_seconds(DateTime),
    Seconds = GregorianSeconds - ?GREGORIAN_SECONDS_EPOC_START,
    Seconds * 1000000.

%%--------------------------------------------------------------------
%% @doc
%% Extract custom data from uuid.
-spec extract_data_from_uuid(Uuid :: omega_uuid()) -> binary().
extract_data_from_uuid(Uuid) when is_binary(Uuid) ->
    <<_T3:32, _T2:16,
      1:1, 1:1, 1:1, 1:1,  % Custom version bits
      _T1:12,
      _C4, _C3, _C2, _C1,
      _S1,
      D3, D2, D1>> = Uuid,
    <<D1, D2, D3>>.

%%--------------------------------------------------------------------
%% @doc
%% Extract partial crc32 node name from uuid.
-spec extract_partial_crc32node_from_uuid(Uuid :: omega_uuid()) -> binary().
extract_partial_crc32node_from_uuid(Uuid) when is_binary(Uuid) ->
    <<_T3:32, _T2:16,
      1:1, 1:1, 1:1, 1:1,  % Custom version bits
      _T1:12,
      C4, C3, C2, C1,
      _S1,
      _D3, _D2, _D1>> = Uuid,
    <<C1, C2, C3, C4>>.
%%--------------------------------------------------------------------
%% @doc
-spec extract_datetime_from_id(integer()) -> calendar:datetime().
extract_datetime_from_id(Id) when is_integer(Id) ->
    TsMicro = (Id bsr 3) band 16#0fffffffffffffff,
    EpocSeconds = TsMicro div 1000000,
    GregorianSeconds = EpocSeconds + ?GREGORIAN_SECONDS_EPOC_START,
    calendar:gregorian_seconds_to_datetime(GregorianSeconds).

%%--------------------------------------------------------------------
%% @doc
hexstr_to_binary(HexStr) ->
    hexstr_to_binary_r(lists:reverse(HexStr), <<>>).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This in an internal function which operates on reversed hex string
%% hence the suffix as _r. Since, the hex string is reversed, so
%% that the list append reverses the originally reversed hex string
%% giving the expected result out.
%% For sample usage where the original
%% hex string is revered while passed to this function.
%% @see hexstr_to_binary/1
hexstr_to_binary_r([] = _HexStr, Acc) ->
    list_to_binary(Acc);
hexstr_to_binary_r([H] = _HexStr, Acc) ->
    hexstr_to_binary_r([], [hex_ascii_to_int(H)] ++ Acc);
hexstr_to_binary_r([H1, H2 | T] = _HexStr, Acc) ->
    hexstr_to_binary_r(T, [
                              (hex_ascii_to_int(H2) bsl 8)
                              bor
                              hex_ascii_to_int(H1)
                          ] ++ Acc).

%%--------------------------------------------------------------------
%% @private
%% @doc
hex_ascii_to_int(H) when H >= $a andalso H =< $f ->
    H - $a + 10;
hex_ascii_to_int(H) when H >= $A andalso H =< $F ->
    H - $A + 10;
hex_ascii_to_int(H) when H >= $0 andalso H =< $9 ->
    H - $0.

%%--------------------------------------------------------------------
%% @private
%% @doc
crc32_erlang_node() ->
    erlang:crc32(erlang:atom_to_binary(node(), utf8)).


%%--------------------------------------------------------------------
%% @doc
merge_map_recursive(_Key, V1, V2) when is_map(V1) andalso is_map(V2) ->
    mapsd:merge(V1, V2);
merge_map_recursive(_Key, _V1, V2) ->
    V2.

%%--------------------------------------------------------------------
%% @doc
%% This function must be used for case where some of the values might
%% be undefined, in which case pick the older value. Having said that
%% this is useful for example in SOAP inteface where mandatory
%% fields are not populated by the client, hence set as undefined
%% by the underlying soap library.
merge_map_recursive_ignore_undefined(_Key, V1, V2)
    when is_map(V1) andalso is_map(V2) ->
    mapsd:merge(V1, V2);
merge_map_recursive_ignore_undefined(_Key, V1, V2) ->
    case V2 of
        undefined ->
            V1;
        _ ->
            V2
    end.
%%--------------------------------------------------------------------
%% @doc
%% This function will merge N levels of nested maps.
%%
-spec deep_merge(V1 :: map(), V2 :: map(), N :: integer()) -> map().
deep_merge(V1, V2, _N)
    when not is_map(V1) andalso not is_map(V2) ->
    V2;
deep_merge(Map1, Map2, N) when N =:= 0 ->
    maps:merge(Map1, Map2);
deep_merge(Map1, Map2, N) when is_map(Map1) andalso is_map(Map2) ->
    mapsd:merge(fun(_K, V1, V2) ->
        deep_merge(V1, V2, N - 1)
                end, Map1, Map2).

%%--------------------------------------------------------------------
%% @doc
maps_keys_to_remove([], M) ->
    M;
maps_keys_to_remove([H | T] = _K, M) ->
    M2 = maps:remove(H, M),
    maps_keys_to_remove(T, M2).


%%--------------------------------------------------------------------
%% @doc
convert_if_not_list(V) when is_list(V) ->
    V;
convert_if_not_list(V) ->
    [V].

%%--------------------------------------------------------------------
%% @doc
%% Is the value undefined as atom or binary or list
is_undefined(undefined)       -> true;
is_undefined(<<"undefined">>) -> true;
is_undefined("undefined")     -> true;
is_undefined(_)               -> false.

is_undefined_or_empty(undefined)       -> true;
is_undefined_or_empty(<<"undefined">>) -> true;
is_undefined_or_empty("undefined")     -> true;
is_undefined_or_empty(<<"">>)          -> true;
is_undefined_or_empty(_)               -> false.


%%--------------------------------------------------------------------
%% @doc
%% Certian soap clients fill empty as a map where @nil is true
%% and other nuances require the existence of this function.
is_nil_or_empty(#{<<"@nil">> := <<"true">>}) -> true;
is_nil_or_empty(<<"@nil">>)                  -> true;
is_nil_or_empty(<<"">>)                      -> true;
is_nil_or_empty(<<"null">>)                  -> true;
is_nil_or_empty(<<"undefined">>)             -> true;
is_nil_or_empty(undefined)                   -> true;
is_nil_or_empty(null)                        -> true;
is_nil_or_empty(_)                           -> false.

%%--------------------------------------------------------------------
%% @doc
%% Remove keys whose value is a special map indicating nil values,
%% by recursively going through the complete map tree.
%%
%% ```
%%     #{ <<"@nil">> => <<"true">> }
%% '''
%%
remove_nil_map_keys_recursively(Map) when is_map(Map) ->
    maps:fold(
        fun(K, V1, M) ->
            case V1 of
                #{<<"@nil">> := <<"true">>} -> maps:remove(K, M);
                V1 when is_map(V1) ->
                    maps:update(K, remove_nil_map_keys_recursively(V1), M);
                _ -> M
            end
        end, Map, Map).

%%--------------------------------------------------------------------
%% @doc
%% Remove keys whose value is null by recursively going through
%% the complete map tree.
%%
%% ```
%%     #{ <<"somekey">> => null }
%% '''
%%
remove_null_map_keys_recursively(Map) when is_map(Map) ->
    maps:fold(
        fun(K, V1, M) ->
            case V1 of
                null -> maps:remove(K, M);
                V1 when is_map(V1) orelse is_list(V1) ->
                    maps:update(K, remove_null_map_keys_recursively(V1), M);
                _ -> M
            end
        end, Map, Map);
remove_null_map_keys_recursively(List) when is_list(List) ->
    [remove_null_map_keys_recursively(X) || X <- List];
remove_null_map_keys_recursively(Item) ->
    Item.


%%--------------------------------------------------------------------
%% @doc
%% Validates a given map with respect to a reference map,
%% which must specify existence of a key with a value of true as
%% shown in the following example usage:
%%
%% M1 = #{"a" => 1, "b" => #{"c" => 2, "d" => #{"e" => 3, "f" => 4}, "g" => 5}},
%% Mref = #{"a" => true, "b"=> #{"d"=> #{"f" => true}}},
%% egraph_util:validate_map_recursive(M1, Mref).
-spec validate_map_recursive(Map :: map(), RefMap :: map()) ->
    ok |
    {error, MissingFields :: list()}.
validate_map_recursive(Map, RefMap) ->
    {_, _, AccOut} = validate_map_recursive_internal(Map, RefMap, [], []),
    case AccOut of
        [] -> ok;
        _ -> {error, [lists:reverse(A) || A <- AccOut]}
    end.

%% @doc
%% Convert any value (n-th level) within the map
%% which follows the datetime format {date(), time()}
%% to a binary with textual representation of the same.
%%
%% ```
%%     A = #{ "a" => {{2010,1,2}, {1,2,3}},
%%            "b" => #{ "c" => {{2011, 2, 3}, {2,3,4}}}
%%          }.
%%     egraph_util:convert_datetime_for_json_encoding(A) =
%%         #{"a" => <<"2010-01-02 01:02:03">>,
%%           "b" => #{"c" => <<"2011-02-03 02:03:04">>}}
%% '''
-spec convert_datetime_for_json_encoding(map()) -> map().
convert_datetime_for_json_encoding(Map) when is_map(Map) ->
    maps:fold(fun(K, V, AccIn) ->
        case V of
            V1 when is_map(V1) ->
                V2 = convert_datetime_for_json_encoding(V),
                AccIn#{K => V2};
            {{Y, Month, D}, {H, Min, S}} when
                is_integer(Y) andalso
                is_integer(Month) andalso
                    is_integer(D) andalso
                    is_integer(H) andalso
                    is_integer(Min) andalso
                    is_integer(S) ->
                %% see http://php.net/manual/en/function.date.php
                %% for format characters as per qdate doc it
                %% follows PHP date function formatting rules.
                AccIn#{K => qdate:to_string(<<"Y-m-d\\TH:i:s">>, V)};
            _ -> AccIn#{K => V}
        end
              end, #{}, Map).

%% @doc
%% convert the map (nth-level) such that any binary values
%% with key matches any of the given fields is automatically
%% converted to hex (though again storing in binary).
%%
%% ```
%%     A = #{"a" => <<1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16>>,
%%           "b" => #{"c" => <<2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7>>}}
%%     egraph_util:convert_uuid_for_json_encoding(["a","c"], A).
%%     #{"a" => <<"0102030405060708090a0b0c0d0e0f10">>,
%%       "b" => #{"c" => <<"02030405060708090001020304050607">>}}
%%
%%     egraph_util:convert_uuid_for_json_encoding(["a"], A).
%%     #{"a" => <<"0102030405060708090a0b0c0d0e0f10">>,
%%       "b" => #{"c" => <<2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7>>}}
%% '''
-spec convert_uuid_for_json_encoding(list(), map()) -> map().
convert_uuid_for_json_encoding(Fields, Map)
    when is_list(Fields) andalso is_map(Map) ->
    {ResultMap, _, _} =
    maps:fold(fun encode_uuid_to_json/3, {#{}, Fields, true}, Map),
    ResultMap.

-spec convert_uuid_for_json_encoding(list(), map(), boolean()) -> map().
convert_uuid_for_json_encoding(Fields, Map, IsRecursive)
    when is_list(Fields) andalso is_map(Map) ->
    {ResultMap, _, _} =
    maps:fold(fun encode_uuid_to_json/3, {#{}, Fields, IsRecursive}, Map),
    ResultMap.

%% @private
%% @doc
%% Given a key and a uuid value convert that in
%% AccIn to hex binary format, which is encodable
%% by json encoder and understood by peers.
encode_uuid_to_json(K, V, {AccIn, Fields, IsRecursive}) ->
    case lists:any(fun(E) -> K =:= E end, Fields) of
        true when is_binary(V) ->
            {AccIn#{K => bin_to_hex_binary(V)}, Fields, IsRecursive};
        _ when is_map(V) andalso IsRecursive == true ->
            V2 = convert_uuid_for_json_encoding(Fields, V, IsRecursive),
            {AccIn#{K => V2}, Fields, IsRecursive};
        _ -> {AccIn#{K => V}, Fields, IsRecursive}
    end.

-spec convert_from_json_to_uuid_binary(list(), map() | list()) -> map().
convert_from_json_to_uuid_binary(Fields, Map)
    when is_list(Fields) andalso is_map(Map) ->
    {Map2, _Fields2} =
    maps:fold(fun decode_uuid_from_json/3, {#{}, Fields}, Map),
    Map2;
convert_from_json_to_uuid_binary(_, X) ->
    X.


%% @private
%% @doc
%% Decode uuid from json value which is in hex binary
%% format.
decode_uuid_from_json(K, V, {AccIn, Fields}) ->
    case lists:any(fun(E) -> K =:= E end, Fields) of
        true when is_binary(V) ->
            {AccIn#{K => hex_binary_to_bin(V)}, Fields};
        _ when is_map(V) ->
            V2 = convert_from_json_to_uuid_binary(Fields, V),
            {AccIn#{K => V2}, Fields};
        _ -> {AccIn#{K => V}, Fields}
    end.

-spec convert_to_map(V :: map() | [{Key :: term(), Value :: term()}]) -> map().
convert_to_map(V) when is_map(V) ->
    V;
convert_to_map(V) when is_list(V) ->
    maps:from_list(V).

convert_to_binary(V) when is_binary(V) ->
    V;
convert_to_binary(V) when is_list(V) ->
    unicode:characters_to_binary(V, utf8);
convert_to_binary(V) when is_atom(V) ->
    atom_to_binary(V, utf8);
convert_to_binary(V) when is_integer(V) ->
    integer_to_binary(V);
convert_to_binary(V) when is_float(V) ->
    float_to_binary(V, [{decimals, 2}]);
convert_to_binary(V) when is_tuple(V) ->
    list_to_binary(io_lib:format("~p", [V])).

%% @doc Convert types to list.
convert_to_list(V) when is_list(V) ->
    V;
convert_to_list(V) when is_binary(V) ->
    binary_to_list(V);
convert_to_list(V) when is_atom(V) ->
    atom_to_list(V);
convert_to_list(V) when is_integer(V) ->
    integer_to_list(V);
convert_to_list(V) when is_float(V) ->
    float_to_list(V).

%% @doc Convert text to lower case.
%% @todo It do not work for utf8, but only for latin-1
convert_to_lower(Value) when is_binary(Value) ->
    Str = binary_to_list(Value),
    unicode:characters_to_binary(string:to_lower(Str), utf8);
convert_to_lower(Value) when is_list(Value) ->
    string:to_lower(Value).

convert_first_char_to_lowercase(<<H, Rest/binary>> = V) when is_binary(V) ->
    H2 = string:to_lower(H),
    <<H2, Rest/binary>>;
convert_first_char_to_lowercase([H | T] = V) when is_list(V) ->
    H2 = string:to_lower(H),
    [H2] ++ T.

get_first_field([H | _]) ->
    H;
get_first_field(V) ->
    V.
get_first_field([], Default) ->
    Default;
get_first_field([H | _], _) ->
    H.

%% @doc Pack contents in reverse
%% Truncate the content when going beyond length of 2^16 - 1
%% and append "..." at the end to indicate the same.
-spec pack_contents(Fields :: [binary()]) -> binary().
pack_contents(Fields) ->
    Result = lists:foldl(fun(E, AccIn) ->
        Bytes = byte_size(E),
        %% truncate when going beyond 16 bits of length
        case Bytes of
            L when L > 65535 ->
                [<<65535:16>>,
                 binary:part(E, 0, 65532),
                 <<$., $., $.>> | AccIn];
            _ ->
                [<<Bytes:16>>, E | AccIn]
        end
                         end,
                         [],
                         Fields),
    iolist_to_binary(Result).

%% @doc Unpack in reverse
%% unpack in reverse so that the reverse packing
%% will undo itself and we get back the same message.
%% Alternatively,
%%
%% ```Fields = unpack_contents(pack_contents(Fields))
%% '''
-spec unpack_contents(binary(), AccIn :: [binary()]) -> [binary()].
unpack_contents(<<>>, AccIn) ->
    AccIn;
unpack_contents(
    <<Length:16, Msg:Length/binary,
      Rest/binary>> = _Message,
    AccIn) ->
    unpack_contents(Rest, [Msg | AccIn]).

%% @doc
%% add version data in to additionaldetails
-spec add_version_into_details(AdditionalDetailsMap :: map(),
                               Version :: list()) -> map().
add_version_into_details(AdditionalDetailsMap, Version)
    when is_map(AdditionalDetailsMap) and is_list(Version) ->
    Meta = maps:get(<<"_meta">>, AdditionalDetailsMap, #{}),
    MergedMeta = Meta#{<<"version">> => Version},
    AdditionalDetailsMap#{
        <<"_meta">> => MergedMeta
    }.

get_version(AdditionalDetailsMap) when is_map(AdditionalDetailsMap) ->
    Meta = maps:get(<<"_meta">>, AdditionalDetailsMap, #{}),
    maps:get(<<"version">>, Meta).

%% @doc Get value of a key, but throw {error, ErrorIfNotFound} if not found.
-spec mget(Key :: binary(), Map :: map(),
           ErrorIfNotFound :: map() | binary()) -> term().
mget(Key, Map, ErrorIfNotfound) ->
    try
        maps:get(Key, Map)
    catch
        error:{badkey, E} ->
            lager:debug("Key not found : ~p ; badkey : ~p", [Key, E]),
            erlang:throw(ErrorIfNotfound)
    end.

%% @doc Get value of a nested key, but throw {error, ErrorIfNotFound} if not found.
-spec nmget(Key :: [binary(),...], Map :: map(),
           ErrorIfNotFound :: map() | binary()) -> term().
nmget(NestedKey, Map, ErrorIfNotfound) ->
    try
        nested:get(NestedKey, Map)
    catch
        error:{badkey, E} ->
            lager:debug("Key not found : ~p ; badkey : ~p", [NestedKey, E]),
            erlang:throw(ErrorIfNotfound)
    end.

%% @doc Get first 32 bits from crc32 of node name.
-spec extract_partial_node_crc32(NodeNameCrc32 :: binary()) -> binary().
extract_partial_node_crc32(NodeNameCrc32) ->
    <<NodeNameCrc32:32>>.

%% @doc convert a specific timezone datetime to utc epoc in microsecond.
%%
%% For IST the value of TzUtcHour is 5 and TzUtcMin is 30.
-spec tz_datetime_to_epoc(TzDateTime :: calendar:datetime(),
                          TzUtcHour :: integer(),
                          TzUtcMin :: integer(),
                          TimeUnit :: microsecond | millisecond | second)
                         -> integer().
tz_datetime_to_epoc(TzDateTime, TzUtcHour, TzUtcMin, microsecond) ->
    egraph_util:datetime_to_epoc_tsmicro(TzDateTime) -
    (((TzUtcHour * 60) + TzUtcMin) * 60 * 1000 * 1000);
tz_datetime_to_epoc(TzDateTime, TzUtcHour, TzUtcMin, millisecond) ->
    (egraph_util:datetime_to_epoc_tsmicro(TzDateTime) div 1000) -
    (((TzUtcHour * 60) + TzUtcMin) * 60 * 1000);
tz_datetime_to_epoc(TzDateTime, TzUtcHour, TzUtcMin, second) ->
    (egraph_util:datetime_to_epoc_tsmicro(TzDateTime) div 1000000) -
    (((TzUtcHour * 60) + TzUtcMin) * 60).

-spec tz_datetime_to_utc(TzDateTime :: calendar:datetime(),
                         TzUtcHour :: integer(),
                         TzUtcMin :: integer()) -> calendar:datetime().
tz_datetime_to_utc(TzDateTime, TzUtcHour, TzUtcMin) ->
    epoc_tsmicro_to_datetime(
        tz_datetime_to_epoc(TzDateTime, TzUtcHour, TzUtcMin, microsecond)).

-spec tz_datetime_to_utc(TzDateTime :: calendar:datetime(), ist)
                        -> calendar:datetime().
tz_datetime_to_utc(TzDateTime, ist) ->
    tz_datetime_to_utc(TzDateTime, 5, 30).

-spec utc_to_tz_datetime(DateTime :: calendar:datetime(), ist)
                        -> calendar:datetime().
utc_to_tz_datetime(DateTime, ist) ->
    calendar:gregorian_seconds_to_datetime(
        calendar:datetime_to_gregorian_seconds(DateTime) +
        (((5 * 60) + 30) * 60)).

convert_map_values(Map, MapRef) ->
    maps:fold(fun(K, V, AccIn) ->
        {Errors, OldMap} = AccIn,
        try
            NewMap = case maps:get(K, MapRef, undefined) of
                         undefined -> OldMap#{K => V};
                         integer -> OldMap#{
                             K => egraph_util:convert_to_integer(V)
                         };
                         float -> OldMap#{K => egraph_util:convert_to_float(V)};
                         binary -> OldMap#{K => egraph_util:convert_to_binary(V)}
                     end,
            {Errors, NewMap}
        catch
            _:_ ->
                {[K | Errors], OldMap}
        end
              end,
              {[], #{}},
              Map).

%% @doc convert to a csv value, where string must be within double quotes.
%%
%% Note that if the value contains double quotes then it is escaped.
-spec convert_for_csv_value(term()) -> binary().
convert_for_csv_value(<<",">>) ->
    %% seperators are left as-is
    <<",">>;
convert_for_csv_value(X) when is_binary(X) ->
    Y = binary:replace(X, <<"\"">>, <<"\\\"">>, [global]),
    Z = binary:replace(Y, <<",">>, <<"\\\:">>, [global]),
    <<$", Z/binary, $">>;
convert_for_csv_value(X) when is_list(X) ->
    BinValue = convert_to_binary(X),
    convert_for_csv_value(BinValue);
convert_for_csv_value(X) ->
    convert_to_binary(X).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
-spec validate_map_recursive_internal(Map :: map(),
                                      RefMap :: map(), list(), list())
                                     -> {map(), list(), list()}.
validate_map_recursive_internal(Map, RefMap, AccIn, AccTotalIn) ->
    maps:fold(fun(K, V1, {M, Acc, AccTotal}) ->
        case {V1, maps:get(K, M, undefined)} of
            {_, undefined} -> {M, Acc, [[K] ++ Acc] ++ AccTotal};
            {true, _} -> {M, Acc, AccTotal};
            {V1, V2} when is_map(V1) andalso is_map(V2) ->
                {_, _AccWithK, NewAccTotal} =
                validate_map_recursive_internal(
                    V2, V1, [K] ++ Acc, AccTotal),
                {M, Acc, NewAccTotal}

        end
              end, {Map, AccIn, AccTotalIn}, RefMap).

%% @private
%% @doc
%% convert a hex binary to a binary with the help of an accumulator
%% while this is an internal function to be used by the publically
%% exposed fun hex_binary_to_bin/1.
-spec hex_binary_to_bin_internal(Bin :: binary(), AccIn :: list()) -> list().
hex_binary_to_bin_internal(<<>>, AccIn) ->
    AccIn;
hex_binary_to_bin_internal(<<A:8, B:8, Rest/binary>>, AccIn) ->
    Msb = hex_to_int(A),
    Lsb = hex_to_int(B),
    hex_binary_to_bin_internal(Rest, [(Msb bsl 4) bor (Lsb band 15)] ++ AccIn).

%% @private
%% @doc
%% convert a hex character to integer range [0,15] and
%% throw exception when not a valid hex character.
-spec hex_to_int(V :: byte()) -> 0..15.
hex_to_int(V) when V >= $a andalso V =< $f ->
    V - $a + 10;
hex_to_int(V) when V >= $A andalso V =< $F ->
    V - $A + 10;
hex_to_int(V) when V >= $0 andalso V =< $9 ->
    V - $0.

minus_months(Months, Date) ->
    {{Y, M, D}, Time} = qdate:to_date(Date),
    {TargetYear, TargetMonth} = fix_year_month({Y, M - Months}),
    DaysInMonth = calendar:last_day_of_the_month(TargetYear, TargetMonth),
    NewD = lists:min([DaysInMonth, D]),
    qdate:to_unixtime({{TargetYear, TargetMonth, NewD}, Time}).

fix_year_month({Y, M}) when (M =:= 1) ->
    YearsOver = Y - 1,
    {YearsOver, 12};
fix_year_month({Y, M}) when (M < 1) ->
    YearsOver = Y - 1,
    {YearsOver, 12};
fix_year_month({Y, M}) ->
    {Y, M}.

minus_hours(Hours, Date) ->
    minus_minutes(Hours * 60, Date).

minus_minutes(Minutes, Date) ->
    Seconds = Minutes * 60,
    qdate:to_unixtime(Date) - Seconds.

%% This rounding does floor.
%% for 0.068 it will give 0.06
round(Number) ->
    P1 = math:pow(10, ?DECIMAL_PRECISION + 1),
    P = math:pow(10, ?DECIMAL_PRECISION),
    (erlang:trunc(Number * P1) div 10) / P.

epochsec_to_date_time(Seconds) ->
    epoc_tsmicro_to_datetime(Seconds * 1000000).

-spec epochmsec_to_date_time(MilliSeconds :: integer()) -> calendar:datetime().
epochmsec_to_date_time(MilliSeconds)->
    epochsec_to_date_time(MilliSeconds div 1000).

-spec date_time_to_json_string(DateTime :: calendar:date()) -> string().
date_time_to_json_string(DateTime) ->
    qdate:to_string(<<"Y-m-d\\TH:i:s">>, DateTime).

%% @doc
%% Returns the {@type list()} of {calendar:datetime(), calendar:datetime()}
%% one per day that corresponds to the start date and end date which inclusively
%% (i.e. can be used for inclusive between queries)
%% identifies one day interval that lies between the specified StartDate
%% and EndDate. In case both the dates are
%% within the same day than the returned list would be [{StartDate, EndDate}].
-spec get_day_granular_intervals_between(StartDate :: calendar:datetime(),
                                         EndDate :: calendar:datetime()) ->
    [{calendar:datetime(), calendar:datetime()}, ...].
get_day_granular_intervals_between(StartDate, EndDate) ->
    true = (StartDate =< EndDate),
    get_day_granular_intervals_between(StartDate, EndDate, []).

get_day_granular_intervals_between({{Y, M, D}, _} = StartDate,
                                   {{Y, M, D}, _} = EndDate, AccList) ->
    [{StartDate, EndDate} | AccList];
get_day_granular_intervals_between(StartDate,
                                   {{EY, EM, ED}, _} = EndDate, AccList) ->
    NewEndDate =
    case ED - 1 of
        0 ->
            case EM - 1 of
                0 ->
                    {EY - 1, 12, 31};
                NEM ->
                    {EY, NEM, calendar:last_day_of_the_month(EY, NEM)}
            end;
        NED ->
            {EY, EM, NED}
    end,
    NewDate = {{EY, EM, ED}, {0, 0, 0}},
    get_day_granular_intervals_between(StartDate,
                                       {NewEndDate, {23, 59, 59}},
                                       [{NewDate, EndDate} | AccList]).

%% @doc
%% This utility function constructs a bit flag from a list of booleans or functions that produces a
%% boolean. The boolean() corresponding to the top most element in the list occupies the most
%% significant bit in the returned bit flag. This allows building the list efficiently by adding new
%% bits added to the bit flag (which would typically be added to the most significant bit side) to
%% the top of the list. The list can contain functions that take no arguments and returns a boolean
%% to facilitate lazy evaluation to get the bits for the bit flag being constructed.
%% @returns decimal representation of the bit flag.
%% @end
-spec construct_bit_flag([boolean()|fun(() -> boolean())]) -> number().
construct_bit_flag(InputList) when is_list(InputList) ->
    construct_bit_flag(InputList, 0).


construct_bit_flag([], BitFlag) ->
    BitFlag;
construct_bit_flag([true | Rest], BitFlag) ->
    construct_bit_flag(Rest, (BitFlag bsl 1) bor 1);
construct_bit_flag([false | Rest], BitFlag) ->
    construct_bit_flag(Rest, (BitFlag bsl 1) bor 0);
construct_bit_flag([Function | Rest], BitFlag) when is_function(Function, 0) ->
    construct_bit_flag([Function() | Rest], BitFlag).


update_list_with_list_of_keys([], _, _, UpdatedList) ->
    UpdatedList;
update_list_with_list_of_keys(_, [], _, UpdatedList) ->
    UpdatedList;
update_list_with_list_of_keys([Map|RestMap], [Value|RestValue], Key, UpdatedList)->
AppendedList = lists:append(UpdatedList, [maps:merge(Map, #{Key => Value})]),
    update_list_with_list_of_keys(RestMap, RestValue, Key, AppendedList).


%% The following two functions call each other making a recursive loop
%%
%%
%% The following should succeed for any map no matter the nesting.
%%
%% ```
%%   A = #{ <<"a">> => [#{<<"b">> => {1,2,3}}, 1, 2, 3] },
%%   jsx:encode(beamparticle_util:convert_for_json_encoding(A)).
%% ```
%% TODO handle uuid or binaries which are not printable
%% NOTE: tuple are converted to list
-spec convert_for_json_encoding(term()) -> map().
convert_for_json_encoding(Map) when is_map(Map) ->
    maps:fold(fun encode_for_json/3, #{}, Map);
convert_for_json_encoding(V) when is_tuple(V) ->
    convert_for_json_encoding(tuple_to_list(V));
convert_for_json_encoding(V) when is_list(V) ->
    V2 = lists:foldl(fun(E, AccIn) ->
                        [convert_for_json_encoding(E) | AccIn]
                end, [], V),
    lists:reverse(V2);
convert_for_json_encoding(V) ->
    V.

encode_for_json(K, V, AccIn) ->
        AccIn#{K => convert_for_json_encoding(V)}.


%% @doc Convert XML to json map recursively even within text
%%
%% Taken from github.com/beamparticle/beamparticle
%%
%% This function (on best effort basis) tries to convert xml
%% to Erlang map (json serializable), while throwing away the
%% xml attributes. Note that the content within the tags are
%% tried for json decoding and done whenever possible.
%%
%% beamparticle_util:convert_xml_to_json_map(<<"<string>{\"a\": 1}</string>">>).
%% beamparticle_util:convert_xml_to_json_map(<<"<r><string>{\"a\": 1}</string><a>1\n2</a><a>4</a></r>">>).
convert_xml_to_json_map(Content) when is_binary(Content) ->
    case erlsom:simple_form(binary_to_list(Content)) of
        {ok, {XmlNode, _XmlAttribute, XmlValue}, _} ->
            XmlNode2 = case is_list(XmlNode) of
                           true ->
                               unicode:characters_to_binary(XmlNode, utf8);
                           false ->
                               XmlNode
                       end,
            #{XmlNode2 => xml_to_json_map(XmlValue, #{})};
        Error ->
            Error
    end.

xml_to_json_map([], AccIn) ->
    AccIn;
xml_to_json_map([{Node, _Attribute, Value} | Rest], AccIn) ->
    Node2 = case is_list(Node) of
                true ->
                    unicode:characters_to_binary(Node, utf8);
                false ->
                    Node
            end,
    AccIn2 = case maps:get(Node2, AccIn, undefined) of
                 undefined ->
                     AccIn#{Node2 => xml_to_json_map(Value, #{})};
                 OldValue when is_list(OldValue) ->
                     AccIn#{Node2 => [xml_to_json_map(Value, #{}) | OldValue]};
                 OldValue ->
                     AccIn#{Node2 => [xml_to_json_map(Value, #{}), OldValue]}
             end,
    xml_to_json_map(Rest, AccIn2);
xml_to_json_map([V], _AccIn) ->
    case is_list(V) of
        true ->
            try_decode_json(unicode:characters_to_binary(V, utf8));
        false ->
            V
    end;
xml_to_json_map(V, _AccIn) ->
    try_decode_json(V).

try_decode_json(V) ->
    try
        jiffy:decode(V, [return_maps])
    catch
        _:_ ->
            V
    end.


%% @doc get node uptime in millisecond or second.
-spec node_uptime(millisecond | second) -> integer().
node_uptime(millisecond) ->
  {TotalTimeMsec, _TimeSinceLastCallMsec} = erlang:statistics(wall_clock),
  TotalTimeMsec;
node_uptime(second) ->
  node_uptime(millisecond) div 1000.


-spec log_info(Format :: string(), Args :: list()) -> ok.
log_info(Format, Args) ->
  lager:info(Format, Args).

-spec log_debug(Format :: string(), Args :: list()) -> ok.
log_debug(Format, Args) ->
  lager:debug(Format, Args).


%% @doc Run general query on MySQL
%% @author Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%
%% This function connects to MySQL database, runs the query
%% and then disconnects.
%%
%% @todo The MySQL pid is terminated with a kill signal, but
%%       is there any other way to terminate it?
%%
%% @todo Information like last insert id, affected rows,
%%       and warning count needs to be returned back.
%%
%% Note that timeout is 5000 millisecond in the following queries
%%
%% run db_mysql_query("localhost", 3306, "dbname", "root",
%% "root", <<"SELECT 1">>, [], 5000)
%%
%% see https://github.com/mysql-otp/mysql-otp
%%
%% fun(Host :: string(), Port :: integer(), Database :: string(),
%%     Username :: string(), Password :: string(),
%%     Query ::  binary(),
%%     Params :: [binary()|integer()|float()],
%%     TimeoutMsec :: integer()) ->
%%         {ok, ColumnNames :: [binary()], Rows :: [ [term()] ]}
%%         | ok
%%         | {error, term()}.
db_mysql_query(Host, Port, Database, Username, Password, Query, Params,
               TimeoutMsec) when
  is_list(Host) andalso is_integer(Port) andalso
    is_list(Username) andalso is_list(Password) andalso
    is_binary(Query) andalso is_list(Params) andalso is_integer(TimeoutMsec) ->

  {ok, Pid} = mysql:start_link([{host, Host}, {port, Port},
    {user, Username},
    {password, Password}, {database, Database},
    {query_timeout, TimeoutMsec},
    {connect_timeout, TimeoutMsec}]),
  Result = mysql:query(Pid, Query, Params),

  %% fetch more info about the last query
  %% TODO: They are not used at present, so
  %%       should we start using them?
  %%LastInsertId = mysql:insert_id(Pid),
  %%AffectedRows = mysql:affected_rows(Pid),
  %%WarningCount = mysql:warning_count(Pid),

  %% TODO is there any other way to terminate it?
  erlang:exit(Pid, kill),
  Result.

%% @doc Run general query on redis
%% @author Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%
%% Note that timeout is 5000 millisecond in the following queries
%%
%% run db_redis_query("localhost", 6379, ["GET", "somekey"], 5000)
%%
%% see https://github.com/wooga/eredis
%%
%% fun(Host :: string(), Port :: integer(),
%%     Command :: [iodata()], TimeoutMsec :: integer()) ->
%%         {ok, binary() | undefined} | {error, term()}.
db_redis_query(Host, Port, Command, TimeoutMsec) when
  is_list(Host) andalso is_integer(Port) andalso
    is_list(Command) andalso is_integer(TimeoutMsec) ->

  Database = 0,
  Password = "",
  ReconnectSleep = 100,
  ConnectTimeout = TimeoutMsec,
  {ok, Client} = eredis:start_link(
                   Host, Port, Database, Password, ReconnectSleep,
                   ConnectTimeout),
  Result = eredis:q(Client, Command),
  eredis:stop(Client),
  Result.


%% @doc HTTP GET on the given url with headers and return results
%% @author Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
%%
%% Issue HTTP GET and return success on http code 200.
%%
%% fun(binary() | string(), [{binary(), binary()}], integer(), integer()) ->
%%   {ok, binary()} | {error, term()}.
transport_make_http_get(Url, Headers, ConnectTimeoutMsec, TimeoutMsec)
when (is_binary(Url) orelse is_list(Url)) andalso is_list(Headers)
andalso is_integer(ConnectTimeoutMsec)
andalso is_integer(TimeoutMsec) ->
  HttpOptions = [{timeout, TimeoutMsec}, {connect_timeout, ConnectTimeoutMsec}],
  UrlStr = case is_binary(Url) of
             true ->
               binary_to_list(Url);
             false ->
               Url
           end,
  case httpc:request(get, {UrlStr, Headers}, HttpOptions,
                     [{body_format, binary}]) of
    {ok, {{_, 200, _}, _Headers, Body}} ->
      {ok, Body};
    Resp ->
      {error, Resp}
  end.



diff(From, To) ->
  lists:reverse(diff(From, To, [], [])).

diff(From, To, Path, Log) when is_map(From), is_map(To) ->
  FromKeys = maps:keys(From),
  NewPairs = maps:to_list(maps:without(FromKeys, To)),
  {Log2, NewPairs2} = maps:fold(
    fun(K, FromV, {L, New}) ->
      case maps:find(K, To) of
        {ok, ToV} -> {diff(FromV, ToV, [K|Path], L), New};
        error -> maybe_moved(K, FromV, NewPairs, Path, L)
      end
    end, {Log, NewPairs}, From),
  lists:foldl(fun({K, V}, L) ->
    [#{op => add, path => path([K|Path]), value => V}|L]
              end, Log2, NewPairs2);
diff(From, To, Path, Log) when is_list(From), is_list(To) ->
  list_diff(From, To, Path, Log, 0);
diff(From, To, _Path, Log) when From =:= To -> Log;
diff(_From, To, Path, Log) ->
  [#{op => replace, path => path(Path), value => To}|Log].

maybe_moved(K, FromV, Pairs, Path, L) ->
  maybe_moved_(K, FromV, Pairs, Path, L, []).
maybe_moved_(K, _V, [], Path, Log, Acc) ->
  {[#{op => remove, path => path([K|Path])}|Log], Acc};
maybe_moved_(K, V, [{NewK, V}|Rest], Path, Log, Acc) ->
  {[#{op => move, path => path([NewK|Path]), from => path([K|Path])}|Log],
      Acc ++ Rest};
maybe_moved_(K, V, [Other|Rest], Path, Log, Acc) ->
  maybe_moved_(K, V, Rest, Path, Log, [Other|Acc]).

list_diff([From|RestF], [To|RestT], Path, Log, Cnt) ->
  list_diff(RestF, RestT, Path, diff(From, To, [Cnt|Path], Log), Cnt+1);
list_diff([_|Rest], [], Path, Log, Cnt) ->
  NewLog = [#{op => remove, path => path([Cnt|Path])}|Log],
  list_diff(Rest, [], Path, NewLog, Cnt+1);
list_diff([], Rest, Path, Log, _Cnt) ->
  lists:foldl(fun(V, L) ->
    [#{op => add, path => path(["-"|Path]), value => V}|L]
              end, Log, Rest).

path(Path) ->
  iolist_to_binary([["/", to_iodata(P)] || P <- lists:reverse(Path)]).

to_iodata(P) when is_atom(P) -> atom_to_list(P);
to_iodata(P) when is_integer(P) -> integer_to_list(P);
to_iodata(P) -> P.

%% @doc create segments of a list such that each segment is at most N elements
%%
%% This is very useful when creating fixed sized parts of a list
%% for job scheduling.
%% A sample test is as follows:
%%
%% ```
%% egraph_util:segments(12, lists:seq(1, 14))
%% '''
-spec segments(pos_integer(), list()) -> [list()].
segments(N, L) when is_list(L) ->
    lists:reverse(segments_internal(N, L, [])).

-spec segments_internal(pos_integer(), list(), [list()]) -> [list()].
segments_internal(_N, [], AccIn) ->
    AccIn;
segments_internal(N, L, AccIn) ->
    try
        {L2, L3} = lists:split(N, L),
        segments_internal(N, L3, [L2 | AccIn])
    catch
        _:_ ->
            %% it is possible that length(L) < N
            [L | AccIn]
    end.


convert_binary_to_datetime(<<>>) ->
  calendar:universal_time();
convert_binary_to_datetime(<<Y1, Y2, Y3, Y4, "-", M1, M2, "-", D1, D2>>) ->
    Year = (((Y1 - $0) * 10 + (Y2 - $0)) * 10 + (Y3 - $0)) * 10 + (Y4 - $0),
    Month = (M1 - $0) * 10 + (M2 - $0),
    Day = (D1 - $0) * 10 + (D2 - $0),
    {{Year, Month, Day}, {0, 0, 0}};
convert_binary_to_datetime(<<Y1, Y2, Y3, Y4, "-", M1, M2, "-", D1, D2, _, H1, H2, ":", MM1, MM2, ":", S1, S2>>) ->
    Year = (((Y1 - $0) * 10 + (Y2 - $0)) * 10 + (Y3 - $0)) * 10 + (Y4 - $0),
    Month = (M1 - $0) * 10 + (M2 - $0),
    Day = (D1 - $0) * 10 + (D2 - $0),
    Hour = (H1 - $0) * 10 + (H2 - $0),
    Min = (MM1 - $0) * 10 + (MM2 - $0),
    Sec = (S1 - $0) * 10 + (S2 - $0),
    {{Year, Month, Day}, {Hour, Min, Sec}};
convert_binary_to_datetime(DateTimeBin) ->
  [DateBin, TimeBin] = case binary:split(DateTimeBin, <<" ">>, [global]) of
                           [P1, P2] -> [P1, P2];
                           [P1] -> [P1, <<"0:0:0">>]
                       end,
  [Ybin, Mbin, Dbin] = binary:split(DateBin, <<"-">>, [global]),
  [Hrbin, Minbin, Secbin] = binary:split(TimeBin, <<":">>, [global]),
  DateTime = {{binary_to_integer(Ybin), binary_to_integer(Mbin),
    binary_to_integer(Dbin)},
    {binary_to_integer(Hrbin), binary_to_integer(Minbin),
      binary_to_integer(Secbin)}},
  DateTime.

convert_binary_to_date(DateTimeBin) ->
    {{Y, M, D}, _} = convert_binary_to_datetime(DateTimeBin),
    {Y, M, D}.

-spec generate_hash_binary(Content :: binary()) -> binary().
generate_hash_binary(Content) ->
    integer_to_binary(xxhash:hash64(Content)).

-spec generate_xxhash_binary(Content :: binary()) -> binary().
generate_xxhash_binary(Content) ->
    egraph_shard_util:convert_integer_to_xxhash_bin(xxhash:hash64(Content)).

encode_json(Info) ->
    iolist_to_binary(jiffy:encode(Info)).

convert_datetime_to_binary(D) ->
    qdate:to_string(<<"Y-m-d H:i:s">>, D).

convert_date_to_binary(D) ->
    qdate:to_string(<<"Y-m-d">>, D).

