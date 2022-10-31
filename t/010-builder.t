#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;
use Test::More;

use ELO::Core;

use ELO::Machine::Builder;

## Event Types

my $eRequest  = ELO::Core::EventType->new( name => 'eRequest'  );
my $eResponse = ELO::Core::EventType->new( name => 'eResponse' );

## Machine

my $B = ELO::Machine::Builder
    ->new
    ->name('WebClient')
    ->protocol([ $eRequest, $eResponse ])

    ->start_state
        ->name('Init')
        ->deferred($eRequest, $eResponse)
        ->entry(
            sub ($self) {
                $self->machine->GOTO('WaitingForRequest');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForRequest')
        ->deferred($eResponse)
        ->add_handler_for(
            eRequest => sub ($self, $e) {
                warn "  GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";
                $self->machine->GOTO('WaitingForResponse');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForResponse')
        ->deferred($eRequest)
        ->add_handler_for(
            eResponse => sub ($self, $e) {
                warn "  GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                $self->machine->GOTO('WaitingForRequest');
            }
        )
        ->end
;

my $M = $B->build;

$M->assign_pid('WebClient:001');

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

=cut

done_testing;



