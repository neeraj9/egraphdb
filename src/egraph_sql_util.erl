%%%-------------------------------------------------------------------
%%% @author Neeraj Sharma
%%% @copyright (C) 2018, Neeraj Sharma
%%% @doc
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
-module(egraph_sql_util).
-author("neerajsharma").

-include("egraph_constants.hrl").

-export([mysql_query/5, mysql_write_query/4]).
-export([run_sql_read_query_for_shard/9,
         run_sql_read_query_for_shard/10]).
-export([try_convert_sql_result/3]).

-define(LAGER_ATTRS, [{type, sql}]).


%% @doc Run a generic MySQL query and get the result from a palma pool
-spec mysql_query(Poolnames :: [atom()],
                  Query :: binary(),
                  Params :: list(),
                  TimeoutMsec :: non_neg_integer(),
                  ConvertToMap :: boolean()) ->
    ok | {ok, {Columns :: list(), Rows :: list()} | [map()]} |
    {error, disconnected | not_found | term()}.
mysql_query(Poolnames, Query, Params, TimeoutMsec, ConvertToMap) ->
    {SelectedPoolname, RemainingAlternatePools} = load_balance_readonly_pool(Poolnames),
    mysql_query(SelectedPoolname, Query, Params, TimeoutMsec, ConvertToMap, RemainingAlternatePools).


mysql_query(Poolname, Query, Params, TimeoutMsec, ConvertToMap, AlternatePools) ->
    try
        case palma:pid(Poolname) of
            Pid when is_pid(Pid) ->
                lager:debug(?LAGER_ATTRS,
                            "[~p] ~p Query=~p, Params=~p, TimeoutMsec=~p",
                            [self(), ?MODULE, Query, Params, TimeoutMsec]),
                Resp = run_mysql_query(Pid, Query, Params, TimeoutMsec),
                case Resp of
                    ok ->
                        ok;
                    {ok, _ColumnNames, []} ->
                        {error, not_found};
                    {ok, ColumnNames, MultileRowValues}
                      when is_list(MultileRowValues) ->
                        R = try_convert_sql_result(
                              ColumnNames, MultileRowValues, ConvertToMap),
                        {ok, R};
                    {error, _} ->
                        case AlternatePools of
                            [] ->
                                Resp;
                            [H | Rest] ->
                                mysql_query(H, Query, Params, TimeoutMsec, ConvertToMap, Rest)
                        end
                end;
            _ ->
                case AlternatePools of
                    [] ->
                        {error, disconnected};
                    [H | Rest] ->
                        mysql_query(H, Query, Params, TimeoutMsec, ConvertToMap, Rest)
                end
        end
    catch
        exit: {noproc, _} ->
            case AlternatePools of
                [] ->
                    {error, disconnected};
                [H2 | Rest2] ->
                    mysql_query(H2, Query, Params, TimeoutMsec, ConvertToMap,
                                Rest2)
            end
    end.

%% @doc Run a generic MySQL insert or update and get the result from a palma pool
-spec mysql_write_query(Poolname :: atom(), Query :: binary(),
                        Params :: list(),
                        TimeoutMsec :: non_neg_integer()) ->
    {ok, Count :: integer(), LastInsertId :: integer()} |
    {error, disconnected | not_found | term()}.
mysql_write_query(Poolname, Query, Params, TimeoutMsec) ->
    mysql_write_retry(Poolname, Query, Params, TimeoutMsec, ?EGRAPH_WRITE_RETRY).

-spec mysql_write_retry(Poolname :: atom(), Query :: binary(),
                        Params :: list(),
                        TimeoutMsec :: non_neg_integer(),
                        Count :: integer()) ->
    {ok, Count :: integer(), LastInsertId :: integer()} |
    {error, disconnected | not_found | term()}.
mysql_write_retry(_Poolname, _Query, _Params, _TimeoutMsec, 0) ->
    {error, disconnected};
mysql_write_retry(Poolname, Query, Params, TimeoutMsec, Count) ->
    case mysql_write_query_internal(Poolname, Query, Params, TimeoutMsec) of
        {error, disconnected} ->
            mysql_write_retry(Poolname, Query, Params, TimeoutMsec, Count - 1);
        R ->
            R
    end.

-spec mysql_write_query_internal(Poolname :: atom(), Query :: binary(),
                                 Params :: list(),
                                 TimeoutMsec :: non_neg_integer()) ->
    {ok, Count :: integer(), LastInsertId :: integer()} |
    {error, disconnected | not_found | term()}.
mysql_write_query_internal(Poolname, Query, Params, TimeoutMsec) ->
    case palma:pid(Poolname) of
        Pid when is_pid(Pid) ->
            lager:debug(?LAGER_ATTRS,
                        "[~p] ~p Query=~p, Params=~p, TimeoutMsec=~p",
                        [self(), ?MODULE, Query, Params, TimeoutMsec]),
            run_mysql_query(Pid, Query, Params, TimeoutMsec);
        _ ->
            {error, disconnected}
    end.

%% @private Run a MySQL query within a safety net
-spec run_mysql_query(Pid :: pid(),
                      Query :: binary(),
                      Params :: list(),
                      TimeoutMsec :: non_neg_integer()) ->
    ok | {ok, Cols :: list(), Rows :: list()} | {error, term()}.
run_mysql_query(Pid, Query, Params, TimeoutMsec) ->
    try
        R = mysql:query(Pid, Query, Params, TimeoutMsec),
        lager:debug(?LAGER_ATTRS, "[~p] ~p Result = ~p", [self(), ?MODULE, R]),
        R
    catch
        exit:{noproc, _} ->
            {error, disconnected}
    end.

%% @private convert sql result to map if required
-spec try_convert_sql_result(list(), list(), boolean()) ->
    list() | {list(), list()}.
try_convert_sql_result(ColumnNames, [RowValues], true)
  when is_list(RowValues) ->
    Combined = lists:zip(ColumnNames, RowValues),
    [maps:from_list(Combined)];
try_convert_sql_result(ColumnNames, [_ | _] = MultipleRowValues, true) ->
    Fn = fun (RowValues) ->
                 Combined = lists:zip(ColumnNames, RowValues),
                 maps:from_list(Combined)
         end,
    [Fn(X) || X <- MultipleRowValues];
try_convert_sql_result(ColumnNames, MultipleRowValues, false)
  when is_list(MultipleRowValues) ->
    {ColumnNames, MultipleRowValues}.

%% @doc run read query for shard, which can create shard when not present
run_sql_read_query_for_shard(WritePoolName, BaseTableName,
                             PoolNames, TableName, Query, Params, TimeoutMsec,
                             IsRetry, IsReadOnly) ->
    ConvertToMap = false,
    run_sql_read_query_for_shard(WritePoolName, BaseTableName,
                                 PoolNames, TableName, Query, Params, TimeoutMsec,
                                 IsRetry, IsReadOnly, ConvertToMap).

%% @doc run read query for shard, which can create shard when not present
run_sql_read_query_for_shard(WritePoolName, BaseTableName,
                             PoolNames, TableName, Query, Params, TimeoutMsec,
                             IsRetry, IsReadOnly, ConvertToMap) ->
    case egraph_sql_util:mysql_query(
           PoolNames, Query, Params, TimeoutMsec, ConvertToMap) of
        {ok, _} = R ->
            R;
        {error, {_MySQLCode, <<"42S02">>, _}} = E ->
            case {IsRetry, IsReadOnly} of
                {false, false} ->
                    CreateQuery = iolist_to_binary(
                                    [<<"CREATE TABLE ">>,
                                     TableName,
                                     <<" LIKE ">>,
                                     BaseTableName]),
                    ok = egraph_sql_util:mysql_write_query(WritePoolName,
                                                          CreateQuery,
                                                          [],
                                                          TimeoutMsec),
                    {error, not_found};
                _ ->
                    E
            end;
        E ->
            E
    end.

load_balance_readonly_pool([PoolName]) ->
    {PoolName, []};
load_balance_readonly_pool(AllPools) ->
    NumPools = length(AllPools),
    Index = rand:uniform(NumPools),
    SelectedPoolname = lists:nth(Index, AllPools),
    RemainingAlternatePools = lists:filter(fun(E) -> E =/= SelectedPoolname end , AllPools),
    {SelectedPoolname, RemainingAlternatePools}.

