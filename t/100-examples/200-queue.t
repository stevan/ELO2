#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO;

sub DEBUG ($msg) {
    warn $msg if $ENV{DEBUG};
}

## Event Types

my $eEnqueueRequest = ELO::Machine::Event::Type->new( name => 'eEnqueueRequest' );
my $eDequeueRequest = ELO::Machine::Event::Type->new( name => 'eDequeueRequest' );

my $eDequeueResponse = ELO::Machine::Event::Type->new( name => 'eDequeueResponse' );

my $E_EMPTY_QUEUE = ELO::Machine::Event::Type->new( name => 'E_EMPTY_QUEUE' );
my $E_FULL_QUEUE  = ELO::Machine::Event::Type->new( name => 'E_FULL_QUEUE' );

## Protocols


my $pDequeue = ELO::Protocol->new(
    name => 'Dequeue',
    pair => [
        $eDequeueRequest,
        $eDequeueResponse
    ],
    raises => [ $E_EMPTY_QUEUE ]
);

# while enquee is just an accepted message
# which means that it expects no response
# and also an error here

my $pEnqueue = ELO::Protocol->new(
    name    => 'Enqueue',
    accepts => [ $eEnqueueRequest ],
    raises  => [ $E_FULL_QUEUE ]
);

# the Queue protocol is a union of both of these

my $pQueue = ELO::Protocol->new(
    name => 'Queue',
    uses => [ $pEnqueue, $pDequeue ]
);

## Machines

my $Queue = ELO::Machine->new(
    name     => 'Queue',
    protocol => $pQueue,
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            DEBUG  "INIT : entry ".$m->pid."\n";
            pass('... Queue->Init : entered Queue machine');
            $m->context->{Q} = ELO::Machine::EventQueue->new;
            $m->go_to('Empty');
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'Empty',
            deferred => [ $eDequeueRequest ],
            entry    => sub ($m) {
                DEBUG  "EMPTY : entry ".$m->pid."\n";
                pass('... Queue->Empty : the queue is empty');
            },
            handlers => {
                eEnqueueRequest => sub ($m, $e) {
                    DEBUG  "EMPTY : eEnqueueRequest ".$m->pid."\n";
                    pass('... Queue->Empty : got enqueue request');
                    $m->context->{Q}->enqueue( $e );
                    $m->go_to('Ready');
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'Ready',
            entry    => sub ($m) {
                DEBUG  "READY : entry ".$m->pid."\n";
                pass('... Queue->Ready : the queue is ready');
            },
            handlers => {
                eEnqueueRequest => sub ($m, $e) {
                    DEBUG  "READY : eEnqueueRequest ".$m->pid."\n";
                    pass('... Queue->Ready : got enqueue request');
                    $m->context->{Q}->enqueue( $e );
                },
                eDequeueRequest => sub ($m, $e) {
                    my ($caller, $deferred) = $e->payload->@*;
                    DEBUG  "READY : eDequeueRequest ".$m->pid."\n";
                    pass('... Queue->Ready : got dequeue request from '.$caller);
                    if ($m->context->{Q}->is_empty) {
                        $m->send_to(
                            $caller,
                            ELO::Machine::Event->new( type => $E_EMPTY_QUEUE )
                        );
                        $m->go_to('Empty');
                    }
                    else {
                        $m->send_to(
                            $caller,
                            ELO::Machine::Event->new(
                                type    => $eDequeueResponse,
                                payload => [ $m->context->{Q}->dequeue ]
                            )
                        );
                    }
                },
            }
        )
    ]
);
isa_ok($Queue, 'ELO::Machine');

my $Main = ELO::Machine->new(
    name     => 'Main',
    protocol => ELO::Protocol->new,
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            DEBUG  "INIT : ".$m->pid."\n";
            pass('... Main->Init : entered Main machine');
            my $queue_pid = $m->spawn('Queue');
            $m->context->{id} = 0;
            $m->context->{queue_pid} = $queue_pid;
            $m->send_to(
                $m->context->{queue_pid},
                ELO::Machine::Event->new(
                    type    => $eDequeueRequest,
                    payload => [ $m->pid ]
                )
            );
            $m->go_to('Pump');
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'Pump',
            entry    => sub ($m) {
                DEBUG  "PUMP : ".$m->pid."\n";
                pass('... Main->Pump : sending 5 items to the queue');
                $m->send_to(
                    $m->context->{queue_pid},
                    ELO::Machine::Event->new(
                        type    => $eEnqueueRequest,
                        payload => [
                            {
                                id  => ++$m->context->{id},
                                val => $_,
                            }
                        ]
                    )
                ) foreach (1 .. 5);
                $m->context->{num_consumed} = 0;
                $m->go_to('Consume');
            }
        ),
        ELO::Machine::State->new(
            name     => 'Consume',
            entry    => sub ($m) {
                DEBUG  "CONSUME : ".$m->pid."\n";
                ok($m->context->{num_consumed} <= 5,
                    '... Main->Consume : entering ... consumed ('
                    .$m->context->{num_consumed}
                    .') so far (max: 5)');
                $m->send_to(
                    $m->context->{queue_pid},
                    ELO::Machine::Event->new(
                        type    => $eDequeueRequest,
                        payload => [ $m->pid ]
                    )
                );
            },
            handlers => {
                eDequeueResponse => sub ($m, $e) {
                    DEBUG  "CONSUMED : ".$m->pid."\n";
                    $m->context->{num_consumed}++;
                    pass('... Main->Consume : '
                        .('nom ' x $m->context->{num_consumed}));
                    #DEBUG  Dumper $e;
                    $m->go_to('Consume');
                },
                # errors ...
                E_EMPTY_QUEUE => sub ($m, $e) {
                    DEBUG  "EMPTY QUEUE : ".$m->pid."\n";
                    pass('... Main->Consume : queue is empty');
                    #DEBUG  Dumper $e;
                    $m->go_to('Pump');
                }
            }
        ),
    ]
);
isa_ok($Main, 'ELO::Machine');

my $IdsAreIncreasing = ELO::Machine->new(
    name     => 'IdsAreIncreasing',
    protocol => ELO::Protocol->new( accepts => [ $eDequeueResponse ] ),
    start    => ELO::Machine::State->new(
        name     => 'CheckIds',
        entry    => sub ($m) {
            DEBUG  "!!! MONITOR(".$m->pid.") ENTERING\n";
            pass('... Monitor->IdsAreIncreasing->CheckIds : entered monitor');
            $m->context->{last_id} = 0;
        },
        handlers => {
            eDequeueResponse => sub ($m, $e) {
                DEBUG  "!!! MONITOR(".$m->pid.") GOT : eDequeueResponse => id: " . $e->payload->[0]->payload->[0]->{id} ."\n";
                my $id = $e->payload->[0]->payload->[0]->{id};
                if ( $id > $m->context->{last_id} ) {
                    pass('... Monitor->IdsAreIncreasing : The id is greater than the previous one');
                    $m->context->{last_id} = $id;
                }
                else {
                    $m->raise(
                        ELO::Machine::Event->new(
                            type    => ELO::Machine::Event::Type->new( name => 'E_ID_IS_NOT_INCREASING' ),
                            payload => [ { last_id => $m->context->{last_id}, id => $id } ],
                        )
                    );
                }
            },
            # errors ...
            E_ID_IS_NOT_INCREASING => sub ($m, $s, $e) {
                DEBUG  "!!! MONITOR(".$m->pid.") GOT: E_ID_IS_NOT_INCREASING => " . Dumper $e->payload->[0];
            }
        }
    )
);
isa_ok($IdsAreIncreasing, 'ELO::Machine');


my $L = ELO::Container->new(
    monitors => [ $IdsAreIncreasing ],
    entry    => 'Main',
    machines => [
        $Main,
        $Queue
    ]
);
isa_ok($L, 'ELO::Container');

## manual testing ...

$L->LOOP(20);
pass('... Container : loop exited successfully');


done_testing;



