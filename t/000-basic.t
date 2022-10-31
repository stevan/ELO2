#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;
use Test::More;

use ELO::Core;

## Event Types

my $eRequest  = ELO::Core::EventType->new( name => 'eRequest'  );
my $eResponse = ELO::Core::EventType->new( name => 'eResponse' );

## Machine

my $M = ELO::Core::Machine->new(
    pid      => 'init<001>',
    protocol => [ $eRequest, $eResponse ],
    start    => ELO::Core::State->new(
        name     => 'Init',
        deferred => [ $eRequest, $eResponse ],
        entry    => sub ($self) {
            $self->machine->GOTO('WaitingForRequest');
        },
    ),
    states   => [
        ELO::Core::State->new(
            name     => 'WaitingForRequest',
            deferred => [ $eResponse ],
            handlers => {
                eRequest => sub ($self, $e) {
                    warn "  GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";
                    $self->machine->GOTO('WaitingForResponse');
                }
            }
        ),
        ELO::Core::State->new(
            name     => 'WaitingForResponse',
            deferred => [ $eRequest ],
            handlers => {
                eResponse => sub ($self, $e) {
                    warn "  GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                    $self->machine->GOTO('WaitingForRequest');
                }
            }
        ),
    ]
);

## manual testing ...

$M->START;

$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/'   ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  200, 'OK  .oO( ~ )'  ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/foo'] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/bar'] ));
#warn Dumper
$M->RUN;


$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  300, '>>> .oO(foo)' ] ));
#warn Dumper
$M->RUN;

$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/baz'] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  404, ':-| .oO(bar)' ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  500, ':-O .oO(baz)' ] ));
#warn Dumper
$M->RUN;

#warn Dumper
$M->STOP;


done_testing;



