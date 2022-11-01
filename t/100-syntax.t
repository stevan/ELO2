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

{
    my $curr_machine;
    my $curr_state;

    sub defer ($event_type) {
        $curr_state->defer( $event_type );
        return;
    }

    sub entry ($entry) {
        $curr_state->entry( $entry );
        return;
    }

    sub on ($event_type, $handler) {
        $curr_state->add_handler_for( $event_type->name, $handler );
        return;
    }

    sub start ($name, $body) {
        $curr_state = $curr_machine
            ->start_state
            ->name($name);

        $body->();
        undef $curr_state;
        return;
    }

    sub handle ($name, $body) {
        $curr_state = $curr_machine
            ->add_state
            ->name($name);

        $body->();
        undef $curr_state;
        return;
    }

    sub machine ($name, $protocol, $body) {
        $curr_machine = ELO::Machine::Builder
            ->new
            ->name($name)
            ->protocol($protocol);

        $body->();
        my $machine = $curr_machine;
        undef $curr_machine;
        return $machine;
    }
}

my $B = machine 'WebClient' => [ $eRequest, $eResponse ] => sub {

    start Init => sub {
        defer $eRequest;
        defer $eResponse;

        entry sub ($self) {
            $self->machine->GOTO('WaitingForRequest');
        };
    };

    handle WaitingForRequest => sub {
        defer $eResponse;

        on $eRequest => sub ($self, $e) {
            warn "  GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";
            $self->machine->GOTO('WaitingForResponse');
        };
    };

    handle WaitingForResponse => sub {
        defer $eRequest;

        on $eResponse => sub ($self, $e) {
            warn "  GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
            $self->machine->GOTO('WaitingForRequest');
        };
    };

};

=pod

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

=cut

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



