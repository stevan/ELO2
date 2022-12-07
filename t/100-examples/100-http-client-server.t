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

my $eRequest  = ELO::Machine::Event::Type->new( name => 'eRequest'  );
my $eResponse = ELO::Machine::Event::Type->new( name => 'eResponse' );

my $eConnectionRequest = ELO::Machine::Event::Type->new( name => 'eConnectionRequest' );

my $eServiceLookupRequest  = ELO::Machine::Event::Type->new( name => 'eServiceLookupRequest' );
my $eServiceLookupResponse = ELO::Machine::Event::Type->new( name => 'eServiceLookupResponse' );

=pod

protocol SERVICE_REGISTRY {
    type eServiceLookupRequest  = ( caller : PID, name : Str );
    type eServiceLookupResponse = ( address : PID );

    pair eServiceLookupRequest, eServiceLookupResponse;
}

machine ServiceRegistry : SERVICE_REGISTRY {
    state WaitingForLookupRequest {
        on eServiceLookupRequest ($requestor, $service_name) {
            send_to $requestor =>
                $eServiceLookupResponse->new_event([
                    env->{registry}->{ $service_name }
                ])
        }
    }
}

protocol WEB_SERVER {
    type eConnectionRequest  = (
        caller  : PID,
        request : (
            id     : Int,
            method : HTTP_Method,
            url    : Uri
        )
    );

    type eConnectionResponse = (
        id       : Int,
        response : (
            status : HTTP_Status,
            body   : Str
        )
    );

    pair eConnectionRequest, eConnectionResponse;
}

protocol WEB_CLIENT {
    uses SERVICE_REGISTRY, WEB_SERVER;

    type eRequest  = ( method : HTTP_Method, url  : Uri );
    type eResponse = ( status : HTTP_Status, body : Str );

    pair eRequest, eResponse;
}

=cut

my $pServiceRegistry = ELO::Protocol->new(
    name => 'SERVICE_REGISTRY',
    pair => [
        $eServiceLookupRequest,
        $eServiceLookupResponse
    ]
);

my $pWebServer = ELO::Protocol->new(
    name => 'WEB_SERVER',
    pair => [
        $eConnectionRequest,
        $eResponse
    ]
);

my $pWebClient = ELO::Protocol->new(
    name => 'WEB_CLIENT',
    pair => [
        $eRequest,
        $eResponse
    ],
    uses => [
        $pServiceRegistry,
        $pWebServer
    ]
);

## Machines

=pod


=cut

my $ServiceRegistry = ELO::Machine->new(
    name     => 'ServiceRegistry',
    protocol => $pServiceRegistry,
    start    => ELO::Machine::State->new(
        name     => 'WaitingForLookupRequest',
        handlers => {
            eServiceLookupRequest => sub ($m, $e) {
                my ($requestor, $service_name) = $e->payload->@*;
                DEBUG "LOCATOR(".$m->pid.") GOT: eServiceLookupRequest: " . Dumper [$requestor, $service_name];
                $m->send_to(
                    $requestor => ELO::Machine::Event->new(
                        type    => $eServiceLookupResponse,
                        payload => [ $m->env->{registry}->{ $service_name } ]
                    )
                );
            }
        }
    )
);

my $Server = ELO::Machine->new(
    name     => 'WebService',
    protocol => $pWebServer,
    start    => ELO::Machine::State->new(
        name  => 'Init',
        entry => sub ($m) {
            $m->context->{stats} = { counter => 0 };
            $m->GOTO('WaitingForConnectionRequest');
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'WaitingForConnectionRequest',
            handlers => {
                eConnectionRequest => sub ($m, $e) {
                    my ($client, $request) = $e->payload->@*;
                    DEBUG "SERVER(".$m->pid.") GOT: eConnectionRequest: " . Dumper [$client, $request];

                    $m->context->{stats}->{counter}++;

                    my $request_id = $request->[0];
                    my $endpoint   = $request->[-1];

                    my $response;
                    if ( $endpoint eq '/stats' ) {
                        $response = [ $request_id, 200, 'CNT .oO( '.$m->context->{stats}->{counter}.' )' ];
                    }
                    else {
                        $response = [ $request_id, $m->env->{endpoints}->{ $endpoint }->@* ];
                    }

                    push @$response => '<<'.$m->pid.'>>';

                    $m->send_to(
                        $client => ELO::Machine::Event->new(
                            type    => $eResponse,
                            payload => $response
                        )
                    );
                }
            }
        )
    ]
);

my $Client = ELO::Machine->new(
    name     => 'WebClient',
    protocol => $pWebClient,
    start    => ELO::Machine::State->new(
        name  => 'Init',
        entry => sub ($m) {
            $m->env->{service_lookup_cache} = +{};
            $m->GOTO('WaitingForRequest');
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'WaitingForRequest',
            deferred => [ $eResponse ],
            handlers => {
                eRequest => sub ($m, $e) {
                    DEBUG "CLIENT(".$m->pid.") GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";

                    my ($method, $url ) = $e->payload->@*;
                    my ($server, $path) = ($url =~ /^\/\/([a-z.]+)(.*)$/);

                    $m->context->%* = ();
                    $m->context->{server}  = $server;
                    $m->context->{request} = [
                        $m->env->{next_request_id}->(),
                        $method,
                        $path
                    ];

                    #DEBUG Dumper $m->env->{service_lookup_cache};

                    if ( exists $m->env->{service_lookup_cache}->{$server} ) {
                        DEBUG "CLIENT(".$m->pid.") CACHE: using service-lookup-cache for ($server)\n";
                        my $server_pid = $m->env->{service_lookup_cache}->{$server};
                        $m->context->{server_pid} = $server_pid;
                        $m->GOTO('SendConnectionRequest');
                    }
                    else {
                        $m->GOTO('SendLookupRequest');
                    }
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'SendLookupRequest',
            deferred => [ $eRequest, $eResponse ],
            entry    => sub ($m) {
                DEBUG "CLIENT(".$m->pid.") SENDING: eServiceLookupRequest to ".$m->env->{registry}."\n";
                $m->send_to(
                    $m->env->{registry},
                    ELO::Machine::Event->new(
                        type    => $eServiceLookupRequest,
                        payload => [ $m->pid, $m->context->{server} ]
                    )
                );
            },
            handlers => {
                eServiceLookupResponse => sub ($m, $e) {
                    DEBUG "CLIENT(".$m->pid.") GOT: eServiceLookupResponse  : >> " . join(' ', $e->payload->@*) . "\n";
                    my ($server_pid) = $e->payload->@*;
                    $m->context->{server_pid} = $server_pid;
                    $m->env->{service_lookup_cache}->{ $m->context->{server} } = $server_pid;
                    $m->GOTO('SendConnectionRequest');
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'SendConnectionRequest',
            deferred => [ $eRequest ],
            entry    => sub ($m) {
                DEBUG "CLIENT(".$m->pid.") SENDING: eConnectionRequest to ".$m->context->{server_pid}."\n";
                $m->send_to(
                    $m->context->{server_pid},
                    ELO::Machine::Event->new(
                        type    => $eConnectionRequest,
                        payload => [
                            $m->pid,
                            $m->context->{request}
                        ]
                    )
                );
            },
            handlers => {
                eResponse => sub ($m, $e) {
                    DEBUG "CLIENT(".$m->pid.") GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                    $m->GOTO('WaitingForRequest');
                }
            }
        )
    ]
);

my $AllRequestAreSatisfied = ELO::Machine->new(
    name     => 'AllRequestAreSatisfied',
    protocol => $pWebServer,
    start    => ELO::Machine::State->new(
        name     => 'CheckRequests',
        entry    => sub ($m) {
            pass('... AllRequestAreSatisfied entered OK');
            $m->context->{seen_requests} = {};
        },
        exit     => sub ($m) {
            if ((scalar keys $m->context->{seen_requests}->%*) == 0) {
                pass('... AllRequestAreSatisfied exited OK');
            }
            else {
                fail('... AllRequestAreSatisfied exited ERROR');
                diag ">>> MONITOR(".$m->pid.") has pending requests!!" . Dumper $m->context->{seen_requests};
            }
        },
        handlers => {
            eConnectionRequest => sub ($m, $e) {
                pass('... AllRequestAreSatisfied got eConnectionRequest OK');
                my $request_id = $e->payload->[1]->[0];
                DEBUG ">>> MONITOR(".$m->pid.") GOT: eConnectionRequest id: $request_id\n";
                $m->context->{seen_requests}->{ $request_id }++;
                $m->RAISE(
                    ELO::Machine::Event->new(
                        type    => ELO::Machine::Event::Type->new( name => 'E_MORE_THAN_TWO_REQUESTS_PENDING' ),
                        payload => [ keys $m->context->{seen_requests}->%* ],
                    )
                ) if (scalar keys $m->context->{seen_requests}->%*) > 2;
            },
            eResponse => sub ($m, $e) {
                pass('... AllRequestAreSatisfied got eResponse OK');
                my $request_id = $e->payload->[0];
                DEBUG ">>> MONITOR(".$m->pid.") GOT: eResponse request-id: $request_id\n";
                delete $m->context->{seen_requests}->{ $request_id };
            },
            # errors ...
            E_MORE_THAN_TWO_REQUESTS_PENDING => sub ($m, $e) {
                pass('... AllRequestAreSatisfied got E_MORE_THAN_TWO_REQUESTS_PENDING OK');
                DEBUG "!!! MONITOR(".$m->pid.") GOT: E_MORE_THAN_TWO_REQUESTS_PENDING => " . Dumper $e->payload;
            }
        }
    )
);

my $Main = ELO::Machine->new(
    name     => 'Main',
    protocol => ELO::Protocol->new,
    start    => ELO::Machine::State->new(
        name  => 'Init',
        entry => sub ($m) {

            my $container = $m->container;

            my $server001_pid = $container->spawn('WebService' => ( endpoints => {
                '/'    => [ 200, 'OK  .oO( ~ )' ],
                '/foo' => [ 300, '>>> .oO(foo)' ],
                '/bar' => [ 404, ':-| .oO(bar)' ],
                '/baz' => [ 500, ':-O .oO(baz)' ],
            }));

            my $server002_pid = $container->spawn('WebService' => ( endpoints => {
                '/'    => [ 200, 'OK  .oO( ~ )' ],
                '/foo' => [ 300, '>>> .oO(foo)' ],
                '/bar' => [ 404, ':-| .oO(bar)' ],
                '/baz' => [ 500, ':-O .oO(baz)' ],
            }));

            my $service_registry_pid = $container->spawn('ServiceRegistry' => (
                registry => {
                    'server.one' => $server001_pid,
                    'server.two' => $server002_pid,
                }
            ));

            my sub request_id_generator {
                state $current_request_id = 0;
                sprintf 'req:%d' => ++$current_request_id;
            }

            my $client001_pid = $container->spawn('WebClient' => (
                registry        => $service_registry_pid,
                next_request_id => \&request_id_generator,
            ));

            my $client002_pid = $container->spawn('WebClient' => (
                registry        => $service_registry_pid,
                next_request_id => \&request_id_generator,
            ));

            my $client003_pid = $container->spawn('WebClient' => (
                registry        => $service_registry_pid,
                next_request_id => \&request_id_generator,
            ));

            $m->context->{clients} = [
                $client001_pid,
                $client002_pid,
                $client003_pid
            ];

            $m->GOTO('Pump');
        },
    ),
    states => [
        ELO::Machine::State->new(
            name  => 'Pump',
            entry => sub ($m) {
                my ($client001_pid,
                    $client002_pid,
                    $client003_pid) = $m->context->{clients}->@*;

                $m->send_to(
                    $client001_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.one/'] )
                );
                $m->send_to(
                    $client002_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.two/foo'] )
                );
                $m->send_to(
                    $client003_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.one/'] )
                );
                $m->send_to(
                    $client001_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.one/bar'] )
                );
                $m->send_to(
                    $client002_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.one/baz'] )
                );
                $m->send_to(
                    $client003_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.one/foo'] )
                );
                $m->send_to(
                    $client003_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.two/foo'] )
                );

                $m->send_to(
                    $client001_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.one/stats'] )
                );
                $m->send_to(
                    $client001_pid,
                    ELO::Machine::Event->new( type => $eRequest, payload => ['GET', '//server.two/stats'] )
                );
            }
        )
    ]
);

my $L = ELO::Container->new(
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



