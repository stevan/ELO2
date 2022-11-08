#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO::Core;

## Event Types

my $eEnqueueRequest = ELO::Core::EventType->new( name => 'eEnqueueRequest' );
my $eDequeueRequest = ELO::Core::EventType->new( name => 'eDequeueRequest' );

my $eDequeueResponse = ELO::Core::EventType->new( name => 'eDequeueResponse' );

my $E_EMPTY_QUEUE = ELO::Core::ErrorType->new( name => 'E_EMPTY_QUEUE' );

## Machines

my $Queue = ELO::Core::Machine->new(
    name     => 'Queue',
    protocol => [ $eEnqueueRequest, $eDequeueRequest, $eDequeueResponse ],
    start    => ELO::Core::State->new(
        name     => 'Init',
        entry    => sub ($self) {
            warn "INIT : entry ".$self->machine->pid."\n";
            $self->machine->context->{Q} = [];
            $self->machine->GOTO('Empty');
        }
    ),
    states => [
        ELO::Core::State->new(
            name     => 'Empty',
            deferred => [ $eDequeueRequest ],
            entry    => sub ($self) { warn "EMPTY : entry ".$self->machine->pid."\n" },
            handlers => {
                eEnqueueRequest => sub ($self, $e) {
                    warn "EMPTY : eEnqueueRequest ".$self->machine->pid."\n";
                    push $self->machine->context->{Q}->@*, $e->payload->@*;
                    $self->machine->GOTO('Ready');
                }
            }
        ),
        ELO::Core::State->new(
            name     => 'Ready',
            entry    => sub ($self) { warn "READY : entry ".$self->machine->pid."\n" },
            handlers => {
                eEnqueueRequest => sub ($self, $e) {
                    warn "READY : eEnqueueRequest ".$self->machine->pid."\n";
                    push $self->machine->context->{Q}->@*, $e->payload->@*;
                },
                eDequeueRequest => sub ($self, $e) {
                    warn "READY : eDequeueRequest ".$self->machine->pid."\n";
                    if (scalar $self->machine->context->{Q}->@* == 0) {
                        $self->machine->send_to(
                            $e->payload->@*,
                            ELO::Core::Error->new( type => $E_EMPTY_QUEUE )
                        );
                        $self->machine->GOTO('Empty');
                    }
                    else {
                        $self->machine->send_to(
                            $e->payload->@*,
                            ELO::Core::Event->new(
                                type    => $eDequeueResponse,
                                payload => [ shift $self->machine->context->{Q}->@* ]
                            )
                        );
                    }
                },
            }
        )
    ]
);

my $Main = ELO::Core::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Core::State->new(
        name     => 'Init',
        entry    => sub ($self) {
            warn "INIT : ".$self->machine->pid."\n";
            my $queue_pid = $self->machine->loop->spawn('Queue');
            $self->machine->context->{id} = 0;
            $self->machine->context->{queue_pid} = $queue_pid;
            $self->machine->send_to(
                $self->machine->context->{queue_pid},
                ELO::Core::Event->new(
                    type    => $eDequeueRequest,
                    payload => [ $self->machine->pid ]
                )
            );
            $self->machine->GOTO('Pump');
        }
    ),
    states => [
        ELO::Core::State->new(
            name     => 'Pump',
            entry    => sub ($self) {
                warn "PUMP : ".$self->machine->pid."\n";
                $self->machine->send_to(
                    $self->machine->context->{queue_pid},
                    ELO::Core::Event->new(
                        type    => $eEnqueueRequest,
                        payload => [
                            {
                                id  => ++$self->machine->context->{id},
                                val => $_,
                            }
                        ]
                    )
                ) foreach (1 .. 5);
                $self->machine->GOTO('Consume');
            }
        ),
        ELO::Core::State->new(
            name     => 'Consume',
            entry    => sub ($self) {
                warn "CONSUME : ".$self->machine->pid."\n";
                $self->machine->send_to(
                    $self->machine->context->{queue_pid},
                    ELO::Core::Event->new(
                        type    => $eDequeueRequest,
                        payload => [ $self->machine->pid ]
                    )
                );
            },
            handlers => {
                eDequeueResponse => sub ($self, $e) {
                    warn "CONSUMED : ".$self->machine->pid."\n";
                    warn Dumper $e;
                    $self->machine->GOTO('Consume');
                }
            },
            on_error => {
                E_EMPTY_QUEUE => sub ($self, $e) {
                    warn "EMPTY QUEUE : ".$self->machine->pid."\n";
                    warn Dumper $e;
                    $self->machine->GOTO('Pump');
                }
            }
        ),
    ]
);

my $IdsAreIncreasing = ELO::Core::Machine->new(
    name     => 'IdsAreIncreasing',
    protocol => [ $eDequeueResponse ],
    start    => ELO::Core::State->new(
        name     => 'CheckIds',
        entry    => sub ($self) {
            warn "!!! MONITOR(".$self->machine->pid.") ENTERING\n";
            $self->machine->context->{last_id} = 0;
        },
        handlers => {
            eDequeueResponse => sub ($self, $e) {
                warn "!!! MONITOR(".$self->machine->pid.") GOT : eDequeueResponse => " . Dumper $e->payload->[0];
                my $id = $e->payload->[0]->{id};
                if ( $id > $self->machine->context->{last_id} ) {
                    $self->machine->context->{last_id} = $id;
                }
                else {
                    die ELO::Core::Error->new(
                        type    => ELO::Core::ErrorType->new( name => 'E_ID_IS_NOT_INCREASING' ),
                        payload => [ { last_id => $self->machine->context->{last_id}, id => $id } ],
                    );
                }
            }
        },
        on_error => {
            E_ID_IS_NOT_INCREASING => sub ($self, $e) {
                warn "!!! MONITOR(".$self->machine->pid.") GOT: E_ID_IS_NOT_INCREASING => " . Dumper $e->payload->[0];
            }
        }
    )
);


my $L = ELO::Core::Loop->new(
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



