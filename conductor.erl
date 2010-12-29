-module(conductor).
-export([start/0,conductor_function/0,philosopher/1]).

%% solve dining philosophers with a conductor solution:
%% http://en.wikipedia.org/wiki/Dining_philosophers_problem#Conductor_solution
%% all philosophers talk to a central conductor when they want to grab a fork
%% philosophers grab left fork first, right fork afterwards
%% conductor checks that neighbors are ok with the grab,
%% and does not let 5 left forks be grabbed at once to prevent a live lock

%% usage:
%% issue "conductor:start()." to setup the conductor, philosopher processes and start dining
%% issue "conductor_atom ! die." to instruct all the processes to die

%% NOTES:

%% the conductor sends tick messages to tell philosophers to go to the next stage:
%% it picks the philosopher to tick next at random, which lets us represent random thinking/eating delays
%% this way we can simulate as fast as the platform allows and stress out concurrency issues

%% philosophers wait for a tick in the following situations:
%% when they are thinking
%% when they are dining
%% if a philosopher goes hungry, he tries to grab a left fork first, then a right fork
%% if he is able to do that, he goes thinking to dining without waiting for another tick
%% otherwise he will wait for another tick while hungry, or while hungry and holding a left fork to try again

%% left/right and table orientation convention: direct, counter clockwise orientation

%% we verify that we are not in an impossible state at each tick to have some assurance that our solution is correct (verify_philosopher)

%% http://www.erlang.org/doc/reference_manual/macros.html
-define(PHILOSOPHERS,5).
-define(TICK_COUNT,1000).

start() ->
    %% spin the conductor
    register( conductor_atom, spawn( conductor, conductor_function, [] ) ),
    %% spin the philosophers, they link to the conductor and wait to be ticked
    spawn_philosopher( 0 ),
    %% let the conductor start ticking
    conductor_atom ! go.

spawn_philosopher( ?PHILOSOPHERS ) ->
    ok;
spawn_philosopher( Index ) ->
    PhilosopherName = list_to_atom( lists:flatten( io_lib:format( "philo~b", [ Index ] ) ) ),
    io:format( "Starting ~p~n", [ PhilosopherName ] ),
    register( PhilosopherName, spawn( conductor, philosopher, [ Index ] ) ),
    spawn_philosopher( Index + 1 ).

%%
%% conductor
%%

conductor_function() ->
    receive
        go ->
            conductor_tick_loop( 0, 0 );
        die ->
            exit( shutdown )
    end.

conductor_tick_loop( _, ?TICK_COUNT ) ->
    io:format( "end~n", [] ),
    exit( shutdown );
conductor_tick_loop( BusyForks, TickCount ) ->
    %% verbose and verify the state, abort if an impossible state is detected
    verify_philosopher( 0 ),
    %% pick which philosopher we will tick
    RandomPhilo = list_to_atom( lists:flatten( io_lib:format( "philo~b", [ random:uniform( ?PHILOSOPHERS ) - 1 ] ) ) ),
    io:format( "tick ~p: ~p~n", [ TickCount, RandomPhilo ] ),
    RandomPhilo ! tick,
    conductor_receive_loop( BusyForks, TickCount ).

%% each tick can lead to multiple requests:
%% exhaust and process all messages between each tick
%% otherwise the message queue would grow forever
conductor_receive_loop( BusyForks, TickCount ) ->
    receive
        { grab_left_fork, Pid, Index } ->
            io:format( "conductor: ~p wants left fork~n", [ Index ] ),
            NewBusyForks = conductor_check_fork( left, Pid, Index, BusyForks ),
            conductor_receive_loop( NewBusyForks, TickCount );
        { grab_right_fork, Pid, Index } ->
            io:format( "conductor: ~p wants right fork~n", [ Index ] ),
            NewBusyForks = conductor_check_fork( right, Pid, Index, BusyForks ),
            conductor_receive_loop( NewBusyForks, TickCount );
        { done_eating, _, Index } ->
            io:format( "conductor: ~p is done eating~n", [ Index ] ),
            conductor_receive_loop( BusyForks - 2, TickCount );
        die ->
            exit( shutdown )
    after
        0 ->
            io:format( "no messages, tick again~n", [] ),
            conductor_tick_loop( BusyForks, TickCount + 1 )
    end.

%% left fork is picked up first, never allow the last one to be grabbed
conductor_check_fork( left, Pid, _, ?PHILOSOPHERS - 1 ) ->
    Pid ! deny_fork,
    ?PHILOSOPHERS - 1;
conductor_check_fork( left, Pid, Index, BusyForks ) ->
    %% left neighbor
    NIndex = ( Index + ?PHILOSOPHERS - 1 ) rem ?PHILOSOPHERS,
    NAtom = list_to_atom( lists:flatten( io_lib:format( "philo~b", [ NIndex ] ) ) ),
    io:format( "ask ~p about forks~n", [ NAtom ] ),
    NPid = whereis( NAtom ),
    NPid ! { get_fork_state, self() },
    receive
        { no_fork, SenderPid } when SenderPid == NPid ->            
            Pid ! ok_fork,
            BusyForks + 1;
        { left_fork, SenderPid } when SenderPid == NPid ->
            Pid ! ok_fork,
            BusyForks + 1;
        { both_forks, SenderPid } when SenderPid == NPid ->
            Pid ! deny_fork,
            BusyForks
    end;
conductor_check_fork( right, Pid, Index, BusyForks ) ->
    %% right neighbor
    NIndex = ( Index + 1 ) rem ?PHILOSOPHERS,
    NAtom = list_to_atom( lists:flatten( io_lib:format( "philo~b", [ NIndex ] ) ) ),
    io:format( "ask ~p about forks~n", [ NAtom ] ),
    NPid = whereis( NAtom ),
    NPid ! { get_fork_state, self() },
    receive
        { no_fork, SenderPid } when SenderPid == NPid ->
            Pid ! ok_fork,
            BusyForks + 1;
        { left_fork, SenderPid } when SenderPid == NPid ->
            Pid ! deny_fork,
            BusyForks;
        { both_forks, SenderPid } when SenderPid == NPid ->
            Pid ! deny_fork,
            BusyForks
    end.

%%
%% philosopher process
%%

philosopher( Index ) ->
    link( whereis( conductor_atom ) ),
    io:format( "~p starts dining~n", [ Index ] ),
    philosopher_thinking( Index ).

philosopher_thinking( Index ) ->
    io:format( "~p is thinking~n", [ Index ] ),
    philosopher_wait_tick( Index, no_fork ),
    philosopher_hungry( Index ).

philosopher_wait_tick( Index, ForkState ) ->
    receive
        { get_fork_state, Pid } ->
            philosopher_fork_reply( Index, Pid, ForkState ),
            philosopher_wait_tick( Index, ForkState );
        tick ->
            ok
    end.

philosopher_fork_reply( _, Pid, ForkState ) ->
%%philosopher_fork_reply( Index, Pid, ForkState ) ->
%%    io:format( "~p receives get_fork_state from ~p, state is ~p~n", [ Index, Pid, ForkState ] ),
    Pid ! { ForkState, self() }.

philosopher_hungry( Index ) ->
    io:format( "~p is hungry~n", [ Index ] ),
    conductor_atom ! { grab_left_fork, self(), Index },
    philosopher_hungry_reply_loop( Index ).

philosopher_hungry_reply_loop( Index ) ->
    receive
        ok_fork ->            
            philosopher_hungry_left_fork( Index );
        deny_fork ->
            philosopher_wait_tick( Index, no_fork ),
            philosopher_hungry( Index );
        { get_fork_state, Pid } ->
            philosopher_fork_reply( Index, Pid, no_fork ),
            philosopher_hungry_reply_loop( Index )
    end.

%% *has* left fork, won't let go of it, wants right fork now
philosopher_hungry_left_fork( Index ) ->
    io:format( "~p is hungry and has a left fork~n", [ Index ] ),
    conductor_atom ! { grab_right_fork, self(), Index },
    philosopher_hungry_left_fork_reply_loop( Index ).

%% reply to any number of get_fork_state messages before continuing to the next state and wait tick
philosopher_hungry_left_fork_reply_loop( Index ) ->
    receive
        ok_fork ->
            philosopher_eating( Index );
        deny_fork ->
            philosopher_wait_tick( Index, left_fork ),
            philosopher_hungry_left_fork( Index );
        { get_fork_state, Pid } ->
            philosopher_fork_reply( Index, Pid, left_fork ),
            philosopher_hungry_left_fork_reply_loop( Index )
    end.

philosopher_eating( Index ) ->
    io:format( "~p is eating~n", [ Index ] ),
    philosopher_wait_tick( Index, both_forks ),
    conductor_atom ! { done_eating, self(), Index },
    philosopher_thinking( Index ).

%%
%% state validation
%%

%% state can't change while we are doing this
%% only works because of the centralized monitor approach
verify_philosopher( ?PHILOSOPHERS ) ->
    ok;
verify_philosopher( Index ) ->
    Atom = list_to_atom( lists:flatten( io_lib:format( "philo~b", [ Index ] ) ) ),
    Pid = whereis( Atom ),
    Pid ! { get_fork_state, self() },
    receive
        { no_fork, SenderPid } when SenderPid == Pid ->
            io:format( "~p: no fork~n", [ Atom ] ),
            %% nothing, go directly to the next philosopher
            verify_philosopher( Index + 1 );
        { left_fork, SenderPid } when SenderPid == Pid ->            
            io:format( "~p: left fork~n", [ Atom ] ),
            %% verify that the philosopher on the left does not think he has both forks
            assert_philosopher_state( ( Index + ?PHILOSOPHERS - 1 ) rem ?PHILOSOPHERS, { no_fork, left_fork } ),
            %% verify the next philosopher
            verify_philosopher( Index + 1 );
        { both_forks, SenderPid } when SenderPid == Pid ->
            io:format( "~p: both forks~n", [ Atom ] ),
            %% verify that the philosopher on the left does not think he has both forks
            assert_philosopher_state( ( Index + ?PHILOSOPHERS - 1 ) rem ?PHILOSOPHERS, { no_fork, left_fork } ),
            %% verify that the philosopher on the right does not think he has left fork
            assert_philosopher_state( ( Index + 1 ) rem ?PHILOSOPHERS, { no_fork } ),
            %% verify the next philosopher
            verify_philosopher( Index + 1 )
    end.

assert_philosopher_state( Index, AllowedStates ) ->
    NAtom = list_to_atom( lists:flatten( io_lib:format( "philo~b", [ Index ] ) ) ),
    Pid = whereis( NAtom ),
    Pid ! { get_fork_state, self() },
    receive
        %% see recvtest, couldn't find a way to avoid the 3 handlers
        { no_fork, SenderPid } when SenderPid == Pid ->
            test_philosopher_state( no_fork, AllowedStates );
        { left_fork, SenderPid } when SenderPid == Pid ->
            test_philosopher_state( left_fork, AllowedStates );
        { both_forks, SenderPid } when SenderPid == Pid ->
            test_philosopher_state( both_forks, AllowedStates )
    end.

test_philosopher_state( State, AllowedStates ) ->
    ConditionMet = lists:member( State, tuple_to_list( AllowedStates ) ),
    maybe_abort( not ConditionMet, State, AllowedStates ).

maybe_abort( true, State, AllowedStates ) ->
    io:format( "BAD STATE - ABORTING: ~p ~p~n", [ State, AllowedStates ] ),
    exit( shutdown );
maybe_abort( false, _, _ ) ->
    ok.
