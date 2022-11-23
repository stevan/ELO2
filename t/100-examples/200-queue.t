#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO;

## Event Types

my $eEnqueueRequest = ELO::Machine::Event::Type->new( name => 'eEnqueueRequest' );
my $eDequeueRequest = ELO::Machine::Event::Type->new( name => 'eDequeueRequest' );

my $eDequeueResponse = ELO::Machine::Event::Type->new( name => 'eDequeueResponse' );

my $E_EMPTY_QUEUE = ELO::Machine::Error::Type->new( name => 'E_EMPTY_QUEUE' );

## Machines

my $Queue = ELO::Machine->new(
    name     => 'Queue',
    protocol => [ $eEnqueueRequest, $eDequeueRequest, $eDequeueResponse ],
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            warn "INIT : entry ".$m->pid."\n";
            $m->context->{Q} = ELO::Machine::EventQueue->new;
            $m->GOTO('Empty');
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'Empty',
            deferred => [ $eDequeueRequest ],
            entry    => sub ($m) { warn "EMPTY : entry ".$m->pid."\n" },
            handlers => {
                eEnqueueRequest => sub ($m, $e) {
                    warn "EMPTY : eEnqueueRequest ".$m->pid."\n";
                    $m->context->{Q}->enqueue( $e );
                    $m->GOTO('Ready');
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'Ready',
            entry    => sub ($m) { warn "READY : entry ".$m->pid."\n" },
            handlers => {
                eEnqueueRequest => sub ($m, $e) {
                    warn "READY : eEnqueueRequest ".$m->pid."\n";
                    $m->context->{Q}->enqueue( $e );
                },
                eDequeueRequest => sub ($m, $e) {
                    my ($caller, $deferred) = $e->payload->@*;
                    warn "READY : eDequeueRequest ".$m->pid."\n";
                    if ($m->context->{Q}->is_empty) {
                        $m->send_to(
                            $caller,
                            ELO::Machine::Error->new( type => $E_EMPTY_QUEUE )
                        );
                        $m->GOTO('Empty');
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


my $Main = ELO::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            warn "INIT : ".$m->pid."\n";
            my $queue_pid = $m->container->spawn('Queue');
            $m->context->{id} = 0;
            $m->context->{queue_pid} = $queue_pid;
            $m->send_to(
                $m->context->{queue_pid},
                ELO::Machine::Event->new(
                    type    => $eDequeueRequest,
                    payload => [ $m->pid ]
                )
            );
            $m->GOTO('Pump');
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'Pump',
            entry    => sub ($m) {
                warn "PUMP : ".$m->pid."\n";
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
                $m->GOTO('Consume');
            }
        ),
        ELO::Machine::State->new(
            name     => 'Consume',
            entry    => sub ($m) {
                warn "CONSUME : ".$m->pid."\n";
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
                    warn "CONSUMED : ".$m->pid."\n";
                    warn Dumper $e;
                    $m->GOTO('Consume');
                }
            },
            on_error => {
                E_EMPTY_QUEUE => sub ($m, $e) {
                    warn "EMPTY QUEUE : ".$m->pid."\n";
                    warn Dumper $e;
                    $m->GOTO('Pump');
                }
            }
        ),
    ]
);

my $IdsAreIncreasing = ELO::Machine->new(
    name     => 'IdsAreIncreasing',
    protocol => [ $eDequeueResponse ],
    start    => ELO::Machine::State->new(
        name     => 'CheckIds',
        entry    => sub ($m) {
            warn "!!! MONITOR(".$m->pid.") ENTERING\n";
            $m->context->{last_id} = 0;
        },
        handlers => {
            eDequeueResponse => sub ($m, $e) {
                warn "!!! MONITOR(".$m->pid.") GOT : eDequeueResponse => " . Dumper $e->payload->[0];
                my $id = $e->payload->[0]->payload->[0]->{id};
                if ( $id > $m->context->{last_id} ) {
                    $m->context->{last_id} = $id;
                }
                else {
                    die ELO::Machine::Error->new(
                        type    => ELO::Machine::Error::Type->new( name => 'E_ID_IS_NOT_INCREASING' ),
                        payload => [ { last_id => $m->context->{last_id}, id => $id } ],
                    );
                }
            }
        },
        on_error => {
            E_ID_IS_NOT_INCREASING => sub ($m, $s, $e) {
                warn "!!! MONITOR(".$m->pid.") GOT: E_ID_IS_NOT_INCREASING => " . Dumper $e->payload->[0];
            }
        }
    )
);


my $L = ELO::Container->new(
    monitors => [ $IdsAreIncreasing ],
    entry    => 'Main',
    machines => [
        $Main,
        $Queue
    ]
);

## manual testing ...

$L->LOOP(20);


done_testing;



