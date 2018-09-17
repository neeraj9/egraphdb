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
-module(egraph_dfs_algo).
-author("neerajsharma").

-export([dfs/3]).


-spec dfs(TraverseFun :: fun((binary()) -> [binary()]),
          Source :: binary(),
          Destination :: binary()) -> [binary()].
dfs(_TraverseFun, Source, Source) ->
    [Source];
dfs(TraverseFun, Source, Destination) ->
    Stack = [{Source, 0}],
    State = #{},
    Parents = #{Source => {0, root}},
    Parents2 = dfs_next(TraverseFun, Stack, State, Parents, Destination),
    %% traverse back
    traverse_path(Parents2, Destination, [Destination]).

%%%===================================================================
%%% Internal
%%%===================================================================

-spec dfs_next(TraverseFun :: fun((binary()) -> [binary()]),
               Stack :: [binary()],
               State :: map(),
               Parents :: map(),
               Destination :: binary()) -> [binary()].
dfs_next(_TraverseFun, [], _State, Parents, _Destination) ->
    lager:debug("[~p] ~p Parents = ~p", [self(), ?MODULE, Parents]),
    Parents;
dfs_next(TraverseFun, Stack, State, Parents, Destination) ->
    lager:debug("[~p] ~p Stack = ~p, State = ~p, Parents = ~p, Destination = ~p",
               [self(), ?MODULE, Stack, State, Parents, Destination]),
    [{Vertix, Cost} | RestStack] = Stack,
    Neighbours = TraverseFun(Vertix),
    %% break when reached destination rather than running
    %% through the complete graph. This may not give the
    %% shortest path for a weighted graph but will give a path.
    case lists:member(Destination, Neighbours) of
        false ->
            {NParents, NStack} = lists:foldl(fun(E, {Parents2, Stack2} = _AccIn) ->
                                                     case maps:get(E, State, undefined) of
                                                         undefined ->
                                                             UpdatedCost = Cost + 1,
                                                             Stack3 = [{E, UpdatedCost} | Stack2],
                                                             Parents3 = Parents2#{E => {UpdatedCost, Vertix}},
                                                             {Parents3, Stack3};
                                                         _ ->
                                                             {Parents2, Stack2}
                                                     end
                                             end, {Parents, RestStack}, Neighbours),
            NState = State#{Vertix => traversed},
            dfs_next(TraverseFun, NStack, NState, NParents, Destination);
        true ->
            UpdatedCost = Cost + 1,
            Parents#{Destination => {UpdatedCost, Vertix}}
    end.

traverse_path(Parents, Destination, AccIn) ->
    lager:debug("[~p] ~p Parents = ~p, Destination = ~p, AccIn = ~p",
               [self(), ?MODULE, Parents, Destination, AccIn]),
    case maps:get(Destination, Parents, undefined) of
        undefined ->
            %% not found
            [];
        {_, root} ->
            %% found
            AccIn;
        {_OldCost, Previous} ->
            traverse_path(Parents, Previous, [Previous | AccIn])
    end.

