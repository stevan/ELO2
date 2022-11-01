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

my $eServiceLookupRequest  = ELO::Core::EventType->new( name => 'eServiceLookupRequest' );
my $eServiceLookupResponse = ELO::Core::EventType->new( name => 'eServiceLookupResponse' );

## Machines

my $ServiceRegistryBuilder = ELO::Machine::Builder
    ->new
    ->name('ServiceRegistry')
    ->protocol([ $eServiceLookupRequest, $eServiceLookupResponse ])
    ->start_state
        ->name('WaitingForLookupRequest')
        ->add_handler_for(
            eServiceLookupRequest => sub ($self, $e) {
                my ($requestor, $service_name) = $e->payload->@*;
                warn "LOCATOR(".$self->machine->pid.") GOT: eServiceLookupRequest: " . Dumper [$requestor, $service_name];
                $self->machine->loop->send_to(
                    $requestor => ELO::Core::Event->new(
                        type    => $eServiceLookupResponse,
                        payload => [ $self->machine->env->{registry}->{ $service_name } ]
                    )
                );
            }
        )
        ->end
;

my $ServerBuilder = ELO::Machine::Builder
    ->new
    ->name('WebService')
    ->protocol([ $eConnectionRequest ])
    ->start_state
        ->name('Init')
        ->entry(
            sub ($self) {
                $self->machine->context->{stats} = { counter => 0 };
                $self->machine->GOTO('WaitingForConnectionRequest');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForConnectionRequest')
        ->add_handler_for(
            eConnectionRequest => sub ($self, $e) {
                my ($client, $request) = $e->payload->@*;
                warn "SERVER(".$self->machine->pid.") GOT: eConnectionRequest: " . Dumper [$client, $request];

                $self->machine->context->{stats}->{counter}++;

                my $endpoint = $request->[1];

                my $response;
                if ( $endpoint eq '/stats' ) {
                    $response = [ 200, 'CNT .oO( '.$self->machine->context->{stats}->{counter}.' )' ];
                }
                else {
                    $response = [ $self->machine->env->{endpoints}->{ $endpoint }->@* ];
                }

                push @$response => '<<'.$self->machine->pid.'>>';

                $self->machine->loop->send_to(
                    $client => ELO::Core::Event->new(
                        type    => $eResponse,
                        payload => $response
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
                $self->machine->env->{service_lookup_cache} = +{};
                $self->machine->GOTO('WaitingForRequest');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForRequest')
        ->deferred($eResponse)
        ->add_handler_for(
            eRequest => sub ($self, $e) {
                warn "CLIENT(".$self->machine->pid.") GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";

                my ($method, $url ) = $e->payload->@*;
                my ($server, $path) = ($url =~ /^\/\/([a-z.]+)(.*)$/);

                $self->machine->context->%* = ();
                $self->machine->context->{server}  = $server;
                $self->machine->context->{request} = [ $method, $path ];

                if ( exists $self->machine->env->{service_lookup_cache}->{$server} ) {
                    warn "CLIENT(".$self->machine->pid.") using service-lookup-cache for ($server)\n";
                    my $server_pid = $self->machine->env->{service_lookup_cache}->{$server};
                    $self->machine->context->{server_pid} = $server_pid;
                    $self->machine->GOTO('SendConnectionRequest');
                }
                else {
                    $self->machine->GOTO('SendLookupRequest');
                }
            }
        )
        ->end
    ->add_state
        ->name('SendLookupRequest')
        ->deferred($eRequest, $eResponse)
        ->entry(
            sub ($self) {
                warn "CLIENT(".$self->machine->pid.") SENDING: eServiceLookupRequest to ".$self->machine->env->{registry}."\n";
                $self->machine->loop->send_to(
                    $self->machine->env->{registry},
                    ELO::Core::Event->new(
                        type    => $eServiceLookupRequest,
                        payload => [ $self->machine->pid, $self->machine->context->{server} ]
                    )
                );
                $self->machine->GOTO('WaitingForLookupResponse');
            }
        )
        ->end

    ->add_state
        ->name('WaitingForLookupResponse')
        ->deferred($eRequest, $eResponse)
        ->add_handler_for(
            eServiceLookupResponse => sub ($self, $e) {
                warn "CLIENT(".$self->machine->pid.") GOT: eServiceLookupResponse  : >> " . join(' ', $e->payload->@*) . "\n";
                my ($server_pid) = $e->payload->@*;
                $self->machine->context->{server_pid} = $server_pid;
                $self->machine->context->{service_lookup_cache}->{ $self->machine->context->{server} } = $server_pid;
                $self->machine->GOTO('SendConnectionRequest');
            }
        )
        ->end

    ->add_state
        ->name('SendConnectionRequest')
        ->deferred($eRequest, $eResponse)
        ->entry(
            sub ($self) {
                warn "CLIENT(".$self->machine->pid.") SENDING: eConnectionRequest to ".$self->machine->context->{server_pid}."\n";
                $self->machine->loop->send_to(
                    $self->machine->context->{server_pid},
                    ELO::Core::Event->new(
                        type    => $eConnectionRequest,
                        payload => [
                            $self->machine->pid,
                            $self->machine->context->{request}
                        ]
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
                warn "CLIENT(".$self->machine->pid.") GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                $self->machine->GOTO('WaitingForRequest');
            }
        )
        ->end
;

my $L = ELO::Core::Loop->new(
    builders => [
        $ServerBuilder,
        $ClientBuilder,
        $ServiceRegistryBuilder,
    ]
);

## manual testing ...

my $server001_pid = $L->spawn('WebService' => ( endpoints => {
    '/'    => [ 200, 'OK  .oO( ~ )' ],
    '/foo' => [ 300, '>>> .oO(foo)' ],
    '/bar' => [ 404, ':-| .oO(bar)' ],
    '/baz' => [ 500, ':-O .oO(baz)' ],
}));

my $server002_pid = $L->spawn('WebService' => ( endpoints => {
    '/'    => [ 200, 'OK  .oO( ~ )' ],
    '/foo' => [ 300, '>>> .oO(foo)' ],
    '/bar' => [ 404, ':-| .oO(bar)' ],
    '/baz' => [ 500, ':-O .oO(baz)' ],
}));

my $service_registry_pid = $L->spawn('ServiceRegistry' => (
    registry => {
        'server.one' => $server001_pid,
        'server.two' => $server002_pid,
    }
));

my $client001_pid = $L->spawn('WebClient' => ( registry => $service_registry_pid ));
my $client002_pid = $L->spawn('WebClient' => ( registry => $service_registry_pid ));

$L->send_to($client001_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '//server.one/']
));
$L->send_to($client002_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '//server.two/foo']
));
$L->send_to($client001_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '//server.two/bar']
));
$L->send_to($client002_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '//server.one/baz']
));

$L->send_to($client001_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '//server.one/stats']
));
$L->send_to($client001_pid => ELO::Core::Event->new(
    type => $eRequest, payload => ['GET', '//server.two/stats']
));

$L->LOOP( 20 );


done_testing;



