#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO::Core;

## Event Types

my $eRequest  = ELO::Core::EventType->new( name => 'eRequest'  );
my $eResponse = ELO::Core::EventType->new( name => 'eResponse' );

my $eConnectionRequest = ELO::Core::EventType->new( name => 'eConnectionRequest' );

my $eServiceLookupRequest  = ELO::Core::EventType->new( name => 'eServiceLookupRequest' );
my $eServiceLookupResponse = ELO::Core::EventType->new( name => 'eServiceLookupResponse' );

## Machines

my $ServiceRegistry = ELO::Core::Machine->new(
    name     => 'ServiceRegistry',
    protocol => [ $eServiceLookupRequest, $eServiceLookupResponse ],
    start    => ELO::Core::State->new(
        name     => 'WaitingForLookupRequest',
        handlers => {
            eServiceLookupRequest => sub ($self, $e) {
                my ($requestor, $service_name) = $e->payload->@*;
                warn "LOCATOR(".$self->machine->pid.") GOT: eServiceLookupRequest: " . Dumper [$requestor, $service_name];
                $self->machine->send_to(
                    $requestor => ELO::Core::Event->new(
                        type    => $eServiceLookupResponse,
                        payload => [ $self->machine->env->{registry}->{ $service_name } ]
                    )
                );
            }
        }
    )
);

my $Server = ELO::Core::Machine->new(
    name     => 'WebService',
    protocol => [ $eConnectionRequest, $eResponse ],
    start    => ELO::Core::State->new(
        name  => 'Init',
        entry => sub ($self) {
            $self->machine->context->{stats} = { counter => 0 };
            $self->machine->GOTO('WaitingForConnectionRequest');
        }
    ),
    states => [
        ELO::Core::State->new(
            name     => 'WaitingForConnectionRequest',
            handlers => {
                eConnectionRequest => sub ($self, $e) {
                    my ($client, $request) = $e->payload->@*;
                    warn "SERVER(".$self->machine->pid.") GOT: eConnectionRequest: " . Dumper [$client, $request];

                    $self->machine->context->{stats}->{counter}++;

                    my $request_id = $request->[0];
                    my $endpoint   = $request->[-1];

                    my $response;
                    if ( $endpoint eq '/stats' ) {
                        $response = [ $request_id, 200, 'CNT .oO( '.$self->machine->context->{stats}->{counter}.' )' ];
                    }
                    else {
                        $response = [ $request_id, $self->machine->env->{endpoints}->{ $endpoint }->@* ];
                    }

                    push @$response => '<<'.$self->machine->pid.'>>';

                    $self->machine->send_to(
                        $client => ELO::Core::Event->new(
                            type    => $eResponse,
                            payload => $response
                        )
                    );
                }
            }
        )
    ]
);

my $Client = ELO::Core::Machine->new(
    name     => 'WebClient',
    protocol => [ $eRequest, $eResponse ],
    start    => ELO::Core::State->new(
        name  => 'Init',
        entry => sub ($self) {
            $self->machine->env->{service_lookup_cache} = +{};
            $self->machine->GOTO('WaitingForRequest');
        }
    ),
    states => [
        ELO::Core::State->new(
            name     => 'WaitingForRequest',
            deferred => [ $eResponse ],
            handlers => {
                eRequest => sub ($self, $e) {
                    warn "CLIENT(".$self->machine->pid.") GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";

                    my ($method, $url ) = $e->payload->@*;
                    my ($server, $path) = ($url =~ /^\/\/([a-z.]+)(.*)$/);

                    $self->machine->context->%* = ();
                    $self->machine->context->{server}  = $server;
                    $self->machine->context->{request} = [
                        $self->machine->env->{next_request_id}->(),
                        $method,
                        $path
                    ];

                    #warn Dumper $self->machine->env->{service_lookup_cache};

                    if ( exists $self->machine->env->{service_lookup_cache}->{$server} ) {
                        warn "CLIENT(".$self->machine->pid.") CACHE: using service-lookup-cache for ($server)\n";
                        my $server_pid = $self->machine->env->{service_lookup_cache}->{$server};
                        $self->machine->context->{server_pid} = $server_pid;
                        $self->machine->GOTO('SendConnectionRequest');
                    }
                    else {
                        $self->machine->GOTO('SendLookupRequest');
                    }
                }
            }
        ),
        ELO::Core::State->new(
            name     => 'SendLookupRequest',
            deferred => [ $eRequest, $eResponse ],
            entry    => sub ($self) {
                warn "CLIENT(".$self->machine->pid.") SENDING: eServiceLookupRequest to ".$self->machine->env->{registry}."\n";
                $self->machine->send_to(
                    $self->machine->env->{registry},
                    ELO::Core::Event->new(
                        type    => $eServiceLookupRequest,
                        payload => [ $self->machine->pid, $self->machine->context->{server} ]
                    )
                );
            },
            handlers => {
                eServiceLookupResponse => sub ($self, $e) {
                    warn "CLIENT(".$self->machine->pid.") GOT: eServiceLookupResponse  : >> " . join(' ', $e->payload->@*) . "\n";
                    my ($server_pid) = $e->payload->@*;
                    $self->machine->context->{server_pid} = $server_pid;
                    $self->machine->env->{service_lookup_cache}->{ $self->machine->context->{server} } = $server_pid;
                    $self->machine->GOTO('SendConnectionRequest');
                }
            }
        ),
        ELO::Core::State->new(
            name     => 'SendConnectionRequest',
            deferred => [ $eRequest ],
            entry    => sub ($self) {
                warn "CLIENT(".$self->machine->pid.") SENDING: eConnectionRequest to ".$self->machine->context->{server_pid}."\n";
                $self->machine->send_to(
                    $self->machine->context->{server_pid},
                    ELO::Core::Event->new(
                        type    => $eConnectionRequest,
                        payload => [
                            $self->machine->pid,
                            $self->machine->context->{request}
                        ]
                    )
                );
            },
            handlers => {
                eResponse => sub ($self, $e) {
                    warn "CLIENT(".$self->machine->pid.") GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                    $self->machine->GOTO('WaitingForRequest');
                }
            }
        )
    ]
);

my $AllRequestAreSatisfied = ELO::Core::Machine->new(
    name     => 'AllRequestAreSatisfied',
    protocol => [ $eConnectionRequest, $eResponse ],
    start    => ELO::Core::State->new(
        name     => 'CheckRequests',
        entry    => sub ($self) {
            $self->machine->context->{seen_requests} = {};
        },
        exit     => sub ($self) {
            warn ">>> MONITOR(".$self->machine->pid.") has pending requests!!" . Dumper $self->machine->context->{seen_requests}
                unless (scalar keys $self->machine->context->{seen_requests}->%*) == 0;
        },
        handlers => {
            eConnectionRequest => sub ($self, $e) {
                my $request_id = $e->payload->[1]->[0];
                warn ">>> MONITOR(".$self->machine->pid.") GOT: eConnectionRequest id: $request_id\n";
                $self->machine->context->{seen_requests}->{ $request_id }++;
                die ELO::Core::Error->new(
                    type    => ELO::Core::ErrorType->new( name => 'E_MORE_THAN_TWO_REQUESTS_PENDING' ),
                    payload => [ keys $self->machine->context->{seen_requests}->%* ],
                ) if (scalar keys $self->machine->context->{seen_requests}->%*) > 2;
            },
            eResponse => sub ($self, $e) {
                my $request_id = $e->payload->[0];
                warn ">>> MONITOR(".$self->machine->pid.") GOT: eResponse request-id: $request_id\n";
                delete $self->machine->context->{seen_requests}->{ $request_id };
            },
        },
        on_error => {
            E_MORE_THAN_TWO_REQUESTS_PENDING => sub ($self, $e) {
                warn "!!! MONITOR(".$self->machine->pid.") GOT: E_MORE_THAN_TWO_REQUESTS_PENDING => " . Dumper $e->payload;
            }
        }
    )
);

my $Main = ELO::Core::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Core::State->new(
        name  => 'Init',
        entry => sub ($self) {

            my $loop = $self->machine->loop;

            my $server001_pid = $loop->spawn('WebService' => ( endpoints => {
                '/'    => [ 200, 'OK  .oO( ~ )' ],
                '/foo' => [ 300, '>>> .oO(foo)' ],
                '/bar' => [ 404, ':-| .oO(bar)' ],
                '/baz' => [ 500, ':-O .oO(baz)' ],
            }));

            my $server002_pid = $loop->spawn('WebService' => ( endpoints => {
                '/'    => [ 200, 'OK  .oO( ~ )' ],
                '/foo' => [ 300, '>>> .oO(foo)' ],
                '/bar' => [ 404, ':-| .oO(bar)' ],
                '/baz' => [ 500, ':-O .oO(baz)' ],
            }));

            my $service_registry_pid = $loop->spawn('ServiceRegistry' => (
                registry => {
                    'server.one' => $server001_pid,
                    'server.two' => $server002_pid,
                }
            ));

            my sub request_id_generator {
                state $current_request_id = 0;
                sprintf 'req:%d' => ++$current_request_id;
            }

            my $client001_pid = $loop->spawn('WebClient' => (
                registry        => $service_registry_pid,
                next_request_id => \&request_id_generator,
            ));

            my $client002_pid = $loop->spawn('WebClient' => (
                registry        => $service_registry_pid,
                next_request_id => \&request_id_generator,
            ));

            my $client003_pid = $loop->spawn('WebClient' => (
                registry        => $service_registry_pid,
                next_request_id => \&request_id_generator,
            ));

            $self->machine->context->{clients} = [
                $client001_pid,
                $client002_pid,
                $client003_pid
            ];

            $self->machine->GOTO('Pump');
        },
    ),
    states => [
        ELO::Core::State->new(
            name  => 'Pump',
            entry => sub ($self) {
                my ($client001_pid,
                    $client002_pid,
                    $client003_pid) = $self->machine->context->{clients}->@*;

                $self->machine->send_to(
                    $client001_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.one/'] )
                );
                $self->machine->send_to(
                    $client002_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.two/foo'] )
                );
                $self->machine->send_to(
                    $client003_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.one/'] )
                );
                $self->machine->send_to(
                    $client001_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.one/bar'] )
                );
                $self->machine->send_to(
                    $client002_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.one/baz'] )
                );
                $self->machine->send_to(
                    $client003_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.one/foo'] )
                );
                $self->machine->send_to(
                    $client003_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.two/foo'] )
                );

                $self->machine->send_to(
                    $client001_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.one/stats'] )
                );
                $self->machine->send_to(
                    $client001_pid,
                    ELO::Core::Event->new( type => $eRequest, payload => ['GET', '//server.two/stats'] )
                );
            }
        )
    ]
);

my $L = ELO::Core::Loop->new(
    monitors => [ $AllRequestAreSatisfied ],
    entry    => 'Main',
    machines => [
        $Main,
        $Server,
        $Client,
        $ServiceRegistry,
    ]
);

## manual testing ...

$L->LOOP( 20 ); # 11 leaves us with a pending response


done_testing;



