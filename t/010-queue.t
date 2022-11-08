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
            my $queue_pid = $self->machine->loop->spawn('Queue');
            $self->machine->context->{start} = 0;
            $self->machine->context->{queue_pid} = $queue_pid;
            $self->machine->GOTO('Load');
        }
    ),
    states => [
        ELO::Core::State->new(
            name     => 'Load',
            entry    => sub ($self) {
                $self->machine->send_to(
                    $self->machine->context->{queue_pid},
                    ELO::Core::Event->new( type => $eEnqueueRequest, payload => [ $_ ] )
                ) foreach (10, 20, 30, 40);
                $self->machine->GOTO('Unload');
            }
        ),
        ELO::Core::State->new(
            name     => 'Unload',
            entry    => sub ($self) {
                $self->machine->send_to(
                    $self->machine->context->{queue_pid},
                    ELO::Core::Event->new( type => $eDequeueRequest, payload => [ $self->machine->pid ] )
                );
            },
            handlers => {
                eDequeueResponse => sub ($self, $e) {
                    warn Dumper $e;
                    $self->machine->GOTO('Unload');
                }
            },
            on_error => {
                E_EMPTY_QUEUE => sub ($self, $e) {
                    warn Dumper $e;
                    $self->machine->GOTO('Load');
                }
            }
        ),
    ]
);


my $L = ELO::Core::Loop->new(
    machines => [
        $Main,
        $Queue
    ]
);

## manual testing ...

my $main_pid  = $L->spawn('Main');

$L->LOOP(20);


done_testing;



