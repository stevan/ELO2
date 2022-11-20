#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO;

## Event Types

my $eRequest  = ELO::Event::Type->new( name => 'eRequest'  );
my $eResponse = ELO::Event::Type->new( name => 'eResponse' );

my $eConnectionRequest = ELO::Event::Type->new( name => 'eConnectionRequest' );

my $eServiceLookupRequest  = ELO::Event::Type->new( name => 'eServiceLookupRequest' );
my $eServiceLookupResponse = ELO::Event::Type->new( name => 'eServiceLookupResponse' );

## Machines

my $ServiceRegistry = ELO::Machine->new(
    name     => 'ServiceRegistry',
    protocol => [ $eServiceLookupRequest, $eServiceLookupResponse ],
    start    => ELO::Machine::State->new(
        name     => 'WaitingForLookupRequest',
        handlers => {
            eServiceLookupRequest => sub ($m, $e) {
                my ($requestor, $service_name) = $e->payload->@*;
                warn "LOCATOR(".$m->pid.") GOT: eServiceLookupRequest: " . Dumper [$requestor, $service_name];
                $m->send_to(
                    $requestor => ELO::Event->new(
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
    protocol => [ $eConnectionRequest, $eResponse ],
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
                    warn "SERVER(".$m->pid.") GOT: eConnectionRequest: " . Dumper [$client, $request];

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
                        $client => ELO::Event->new(
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
    protocol => [ $eRequest, $eResponse ],
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
                    warn "CLIENT(".$m->pid.") GOT: eRequest  : >> " . join(' ', $e->payload->@*) . "\n";

                    my ($method, $url ) = $e->payload->@*;
                    my ($server, $path) = ($url =~ /^\/\/([a-z.]+)(.*)$/);

                    $m->context->%* = ();
                    $m->context->{server}  = $server;
                    $m->context->{request} = [
                        $m->env->{next_request_id}->(),
                        $method,
                        $path
                    ];

                    #warn Dumper $m->env->{service_lookup_cache};

                    if ( exists $m->env->{service_lookup_cache}->{$server} ) {
                        warn "CLIENT(".$m->pid.") CACHE: using service-lookup-cache for ($server)\n";
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
                warn "CLIENT(".$m->pid.") SENDING: eServiceLookupRequest to ".$m->env->{registry}."\n";
                $m->send_to(
                    $m->env->{registry},
                    ELO::Event->new(
                        type    => $eServiceLookupRequest,
                        payload => [ $m->pid, $m->context->{server} ]
                    )
                );
            },
            handlers => {
                eServiceLookupResponse => sub ($m, $e) {
                    warn "CLIENT(".$m->pid.") GOT: eServiceLookupResponse  : >> " . join(' ', $e->payload->@*) . "\n";
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
                warn "CLIENT(".$m->pid.") SENDING: eConnectionRequest to ".$m->context->{server_pid}."\n";
                $m->send_to(
                    $m->context->{server_pid},
                    ELO::Event->new(
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
                    warn "CLIENT(".$m->pid.") GOT: eResponse : << " . join(' ', $e->payload->@*) . "\n";
                    $m->GOTO('WaitingForRequest');
                }
            }
        )
    ]
);

my $AllRequestAreSatisfied = ELO::Machine->new(
    name     => 'AllRequestAreSatisfied',
    protocol => [ $eConnectionRequest, $eResponse ],
    start    => ELO::Machine::State->new(
        name     => 'CheckRequests',
        entry    => sub ($m) {
            $m->context->{seen_requests} = {};
        },
        exit     => sub ($m) {
            warn ">>> MONITOR(".$m->pid.") has pending requests!!" . Dumper $m->context->{seen_requests}
                unless (scalar keys $m->context->{seen_requests}->%*) == 0;
        },
        handlers => {
            eConnectionRequest => sub ($m, $e) {
                my $request_id = $e->payload->[1]->[0];
                warn ">>> MONITOR(".$m->pid.") GOT: eConnectionRequest id: $request_id\n";
                $m->context->{seen_requests}->{ $request_id }++;
                $m->RAISE(
                    ELO::Error->new(
                        type    => ELO::Error::Type->new( name => 'E_MORE_THAN_TWO_REQUESTS_PENDING' ),
                        payload => [ keys $m->context->{seen_requests}->%* ],
                    )
                ) if (scalar keys $m->context->{seen_requests}->%*) > 2;
            },
            eResponse => sub ($m, $e) {
                my $request_id = $e->payload->[0];
                warn ">>> MONITOR(".$m->pid.") GOT: eResponse request-id: $request_id\n";
                delete $m->context->{seen_requests}->{ $request_id };
            },
        },
        on_error => {
            E_MORE_THAN_TWO_REQUESTS_PENDING => sub ($m, $e) {
                warn "!!! MONITOR(".$m->pid.") GOT: E_MORE_THAN_TWO_REQUESTS_PENDING => " . Dumper $e->payload;
            }
        }
    )
);

my $Main = ELO::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Machine::State->new(
        name  => 'Init',
        entry => sub ($m) {

            my $loop = $m->loop;

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
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.one/'] )
                );
                $m->send_to(
                    $client002_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.two/foo'] )
                );
                $m->send_to(
                    $client003_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.one/'] )
                );
                $m->send_to(
                    $client001_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.one/bar'] )
                );
                $m->send_to(
                    $client002_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.one/baz'] )
                );
                $m->send_to(
                    $client003_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.one/foo'] )
                );
                $m->send_to(
                    $client003_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.two/foo'] )
                );

                $m->send_to(
                    $client001_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.one/stats'] )
                );
                $m->send_to(
                    $client001_pid,
                    ELO::Event->new( type => $eRequest, payload => ['GET', '//server.two/stats'] )
                );
            }
        )
    ]
);

my $L = ELO::Loop->new(
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



