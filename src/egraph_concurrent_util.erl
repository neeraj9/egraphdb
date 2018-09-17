%%%
%%% Taken from the BeamParticle opensource project.
%%%
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
-module(egraph_concurrent_util).


-export([run_concurrent/2]).

%% @doc Run concurrent tasks in parallel and collect all results
-spec run_concurrent(Tasks :: [{F :: function(), Args :: list()}],
                     TimeoutMsec :: non_neg_integer()) ->
    list().
run_concurrent(Tasks, TimeoutMsec) when TimeoutMsec >= 0 ->
    ParentPid = self(),
    Ref = erlang:make_ref(),
    %% TODO: only pass from process dict what is required
    ProcessDictProplist = erlang:get(),
    Pids = lists:foldl(fun(E, AccIn) ->
                               WPid = erlang:spawn_link(
                                 fun() ->
                                         %% pass process dict to child workers
                                         lists:foreach(fun({X,Y}) -> erlang:put(X, Y) end, ProcessDictProplist),
                                         R = case E of
                                                 {F, A} ->
                                                     apply(F, A);
                                                 {M, F, A} ->
                                                     apply(M, F, A)
                                              end,
                                         ParentPid ! {Ref, self(), R}
                                 end),
                               [WPid | AccIn]
                       end, [], Tasks),
    OldTrapExitFlag = erlang:process_flag(trap_exit, true),
    Result = receive_concurrent_tasks(Ref, Pids, TimeoutMsec, []),
    erlang:process_flag(trap_exit, OldTrapExitFlag),
    Result.

receive_concurrent_tasks(_Ref, [], _TimeoutMsec, AccIn) ->
    AccIn;
receive_concurrent_tasks(Ref, Pids, TimeoutMsec, AccIn) ->
    T1 = erlang:system_time(millisecond),
    receive
        {Ref, Pid, R} ->
            %% This is time consuming since it is O(N),
            %% but this interface shall not be invoked for very high
            %% concurrency.
            RemainingPids = Pids -- [Pid],
            T2 = erlang:system_time(millisecond),
            %% Notice that some time has elapsed, so account for that
            receive_concurrent_tasks(Ref, RemainingPids,
                                     TimeoutMsec - (T2 - T1),
                                     [R | AccIn])
    after
        TimeoutMsec ->
            lists:foreach(fun(P) ->
                                  erlang:exit(P, kill)
                          end, Pids),
            {error, {timeout, AccIn}}
    end.


