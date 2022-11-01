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

my $eConnectionRequest = ELO::Core::EventType->new( name => 'eConnectionRequest' );

## Machines

my %ENDPOINTS = (
    '/'    => [ 200, 'OK  .oO( ~ )' ],
    '/foo' => [ 300, '>>> .oO(foo)' ],
    '/bar' => [ 404, ':-| .oO(bar)' ],
    '/baz' => [ 500, ':-O .oO(baz)' ],
);

my $ServerBuilder = ELO::Machine::Builder
    ->new
    ->name('WebServer')
    ->protocol([ $eConnectionRequest ])
    ->start_state
        ->name('Init')
        ->entry(
            sub ($self) {
                $self->machine->GOTO('WaitingForConnectionRequest');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForConnectionRequest')
        ->add_handler_for(
            eConnectionRequest => sub ($self, $e) {
                my ($client, $request) = $e->payload->@*;
                warn "SERVER GOT: eConnectionRequest: " . Dumper [$client, $request];
                $self->machine->loop->send_to(
                    $client => ELO::Core::Event->new(
                        type    => $eResponse,
                        payload => $ENDPOINTS{ $request->[1] }
                    )
                );
            }
        )
        ->end
;

my $ClientBuilder = ELO::Machine::Builder
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
                warn "CLIENT GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";
                $self->machine->loop->send_to(
                    'WebServer:001' => ELO::Core::Event->new(
                        type    => $eConnectionRequest,
                        payload => [ $self->machine->pid, $e->payload ]
                    )
                );
                $self->machine->GOTO('WaitingForResponse');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForResponse')
        ->deferred($eRequest)
        ->add_handler_for(
            eResponse => sub ($self, $e) {
                warn "CLIENT GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                $self->machine->GOTO('WaitingForRequest');
            }
        )
        ->end
;

my $L = ELO::Core::Loop->new(
    builders => [
        $ServerBuilder,
        $ClientBuilder,
    ]
);

## manual testing ...

my $server_pid = $L->spawn('WebServer');
my $client_pid = $L->spawn('WebClient');

$L->send_to($client_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '/']
));
$L->send_to($client_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '/foo']
));
$L->send_to($client_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '/bar']
));
$L->send_to($client_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '/baz']
));

$L->LOOP( 20 );


done_testing;



