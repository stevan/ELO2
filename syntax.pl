use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;

use constant PID => 'PID';
use constant Str => 'Str';

sub type     ($name, $spec) {}
sub accepts  (@events)      {}
sub raises   (@errors)      {}
sub pair     ($in, $out)    {}
sub uses     (@protocols)   {}
sub internal (@protocols)   {}

sub protocol ($body) :prototype(&) {

    my $protocol = {
        types    => [],
        accepts  => [],
        raises   => [],
        pair     => [],
        uses     => [],
        internal => [],
    };

    no strict 'refs';
    no warnings 'redefine';

    local *type = sub ($name, $spec) {
        push $protocol->{types}->@* => {
            name => $name,
            spec => $spec,
        };
    };

    local *raises   = sub (@errors)    { push $protocol->{raises}->@*  => @errors    };
    local *accepts  = sub (@events)    { push $protocol->{accepts}->@* => @events    };
    local *uses     = sub (@protocols) { push $protocol->{uses}->@*    => @protocols };
    local *internal = sub (@protocols) { push $protocol->{accepts}->@* => @protocols };

    local *pair = sub ($in, $out) {
        push $protocol->{pair}->@* => {
            in  => $in,
            out => $out
        };
    };

    $body->();

    return $protocol;
}

sub on_entry ($body) :prototype(&) {}
sub on_exit  ($exit) :prototype(&) {}
sub on       ($event, $handler)    {}
sub defer    (@deferred)           {}
sub ignore   (@ignored)            {}

sub start ($name, @args) {

    my $body = pop @args;

    my $state = {
        name     => $name,
        entry    => undef,
        exit     => undef,
        deferred => [],
        handlers => [],
        args     => \@args,
    };

    no strict 'refs';
    no warnings 'redefine';

    local *on = sub ($event, $handler) {
        push $state->{handlers}->@* => {
            event   => $event,
            handler => $handler,
        };
    };

    local *defer = sub (@deferred) {
        push $state->{deferred}->@* => @deferred;
    };

    local *ignore = sub (@ignored) {
        push $state->{ignored}->@* => @ignored;
    };

    local *entry = sub ($body) { $state->{entry} = $body };
    local *exit  = sub ($body) { $state->{exit}  = $body };

    $body->();

    return $state;
}

warn Dumper(

protocol {
    type eServiceLookupRequest  => { caller => PID, name => Str };
    type eServiceLookupResponse => { address => PID };

    type E_SERVICE_NOT_FOUND => { name => Str };

    raises 'E_SERVICE_NOT_FOUND';

    pair 'eServiceLookupRequest', 'eServiceLookupResponse';
}

);


warn Dumper(

 WaitingForLookupRequest => sub {

    on eServiceLookupRequest => sub ($m, $caller, $name) {

        my $service = $m->{registry}->{ $name };

        $m->throw(
            E_SERVICE_NOT_FOUND => { name => $name }
        ) unless $service;

        $m->send_to($caller,
            eServiceLookupResponse => {
                address => $service
            }
        );
    }
}


);

=pod

# Protocols ...

import PID, Str, Int                 from CORE;
import Uri, HTTP_Method, HTTP_Status from HTTP;

protocol SERVICE_REGISTRY {
    type eServiceLookupRequest  = { caller => PID, name => Str };
    type eServiceLookupResponse = { address => PID };

    type E_SERVICE_NOT_FOUND = { name => Str };

    raises E_SERVICE_NOT_FOUND;

    pair eServiceLookupRequest, eServiceLookupResponse;
}

protocol SERVICE {
    type eConnectionRequest = {
        caller  => PID,
        id      => Int,
        request => { method => HTTP_Method, url => Uri }
    }

    type eConnectionResponse = {
        id       => Int,
        response => { status => HTTP_Status, body => Str }
    }

    type E_ENDPOINT_NOT_FOUND = {
        id  => Int,
        url => Str
    };

    raises E_ENDPOINT_NOT_FOUND;

    pair eConnectionRequest, eConnectionResponse;
}


protocol CLIENT {
    uses SERVICE_REGISTRY, SERVICE;

    type eRequest  = { method => HTTP_Method, url  => Uri };
    type eResponse = { status => HTTP_Status, body => Str };

    type E_TIMEOUT;

    raises E_TIMEOUT;

    pair eRequest, eResponse;
}

# Machines ...

package ServiceRegistry {
    use v5.24;
    use warnings;

    use parent 'UNIVERSAL::Object';
    use slots (
        registry => sub {},
        start    => sub { 'ServiceRegistry::WaitingForLookupRequest' },
        states   => sub { +[] },
        # ...
        _active => sub { +{} },
    );

    sub BUILD ($self, $) {
        push $self->{_active}->@* => $self->{start}->new( machine => $self );

        push $self->{_active}->@* => $_->new( machine => $self )
            foreach $self->{states}->@*;
    }
}

package ServiceRegistry::WaitingForLookupRequest {
    use v5.24;
    use warnings;

    use parent 'UNIVERSAL::Object';
    use slots (
        machine => sub {}
    );

    sub eServiceLookupRequest ($self, $caller, $name) {

        my $service = $self->{machine}->{registry}->{ $name };

        $self->{machine}->throw(
            E_SERVICE_NOT_FOUND => { name => $name }
        ) unless $service;

        $self->{machine}->send_to($caller,
            event eServiceLookupResponse => {
                address => $service
            }
        );
    }
}

machine ServiceRegistry (%registry) : SERVICE_REGISTRY {

    has %.registry = %registry;

    start state WaitingForLookupRequest {
        on eServiceLookupRequest ($caller, $name) {

            my $service = %.registry{ $name };

            throw E_SERVICE_NOT_FOUND => { name => $name }
                unless $service;

            send $caller, event eServiceLookupResponse => {
                address => $service
            };
        }
    }
}

machine Service (%endpoints) : SERVICE {

    has %.endpoints = %endpoints;

    has %!stats;

    start state Init {
        entry {
            %!stats{counter} = 0;
            %!stats{errors}  = 0;

            goto WaitingForConnectionRequest;
        }
    }

    state WaitingForConnectionRequest {
        on eConnectionRequest ($caller, $id, $request) {
            my $response = %.endpoints{ $request->{url} };

            unless ($response) {
                %!stats{errors}++;

                throw E_ENDPOINT_NOT_FOUND => {
                    id  => $id,
                    url => $request->{url}
                };
            }

            send $caller, event eConnectionResponse => {
                id       => $id,
                response => $response
            };

            %!stats{counter}++;
        }
    }

}

machine Client ($user, $registry_pid, $timeout) : CLIENT {

    has $.user         = $user;
    has $.registry_pid = $registry_pid;
    has $.timeout      = $timeout;

    has %!registry_cache;

    has $!next_request_id;
    has %!current_request;

    start state Init {
        entry {
            %!registry_cache  = {};
            $!next_request_id = 0;

            goto WaitingForRequest;
        }
    }

    state WaitingForRequest {

        on eRequest ($method, $url) {
            my ($service, $endpoint) = ($url =~ /^\/\/([a-z.]+)(.*)$/);

            %!current_request = {
                id           => ++$!next_request_id,
                service_pid  => undef,
                service_name => $service,
                method       => $method,
                endpoint     => $endpoint,
                url          => $url,
            };

            goto LookupService;
        }
    }

    state LookupService {
        defer eRequest;

        entry {

            if (exists %!registry_cache{ %!current_request{service_name} }) {
                %!current_request{service_pid} = %!registry_cache{ %!current_request{service_name} };
                goto SendConnectionRequest;
            }

            send $.registry_pid, event eServiceLookupRequest => {
                caller => self(),
                name   => %!current_request{service_name},
            };

            alarm $!timeout, self(), event E_TIMEOUT;
        }

        on eServiceLookupResponse ($address) {
            %!current_request{service_pid} = $address;
            %!registry_cache{ %!current_request{service_name} } = $address;

            goto SendConnectionRequest;
        }

        on E_SERVICE_NOT_FOUND ($name) {
            send $.user, event eResponse => {
                status => 404,
                body   => "Service Not Found @ ($name)"
            };

            goto WaitingForRequest;
        }

        on E_TIMEOUT () {
            send $.user, event eResponse => {
                status => 408,
                body   => "Service Lookup Request Timeout for ".%!current_request{url}
            };

            goto WaitingForRequest;
        }
    }

    state SendConnectionRequest {
        defer eRequest;

        entry {
            send %!current_request{service_pid}, event eConnectionRequest => {
                caller  => self(),
                id      => %!current_request{id},
                request => {
                    method => %!current_request{method},
                    url    => %!current_request{endpoint}
                }
            };

            goto WaitingForConnectionResponse;
        }
    }

    state WaitingForConnectionResponse {
        defer eRequest;

        entry {
            alarm $!timeout, self(), event E_TIMEOUT;
        }

        on eConnectionResponse ($id, $response) {
            send $.user, event eResponse => $response;

            goto WaitingForRequest;
        }

        on E_ENDPOINT_NOT_FOUND ($id, $url) {
            send $.user, event eResponse => {
                status => 404,
                body   => "Endpoint Not Found @ ($url)"
            };

            goto WaitingForRequest;
        }

        on E_TIMEOUT () {
            send $.user, event eResponse => {
                status => 408,
                body   => "Service Request Timeout for ".%!current_request{url}
            };

            goto WaitingForRequest;
        }
    }

}

machine Main () : () {

    has @!clients;
    has @!services;
    has $!service_registry;

    start state Init {
        entry {

            @!services = (
                spawn Service (
                    endpoints => {
                        '/'    => { status => 200, body => 'OK  .oO( ~ )' },
                        '/foo' => { status => 300, body => '>>> .oO(foo)' },
                        '/bar' => { status => 404, body => ':-| .oO(bar)' },
                        '/baz' => { status => 500, body => ':-O .oO(baz)' },
                    }
                ),

                spawn Service (
                    endpoints => {
                        '/'    => { status => 200, body => 'OK  .oO( ~ )' },
                        '/foo' => { status => 300, body => '>>> .oO(foo)' },
                        '/bar' => { status => 404, body => ':-| .oO(bar)' },
                        '/baz' => { status => 500, body => ':-O .oO(baz)' },
                    }
                ),
            );

            $!service_registry = spawn ServiceRegistry (
                registry => {
                    'service.one' => @!services[0],
                    'service.two' => @!services[0],
                }
            );

            @!clients = (
                map {
                    spawn Client (
                        user     => self(),
                        registry => $service_registry_pid,
                        timeout  => 10,
                    )
                } 0, 1, 2
            );

            goto Pump;
        }
    }

    state Pump {
        send @!clients[0], event eRequest => { method => 'GET', url => '//service.one/' };
        send @!clients[1], event eRequest => { method => 'GET', url => '//service.two/foo' };
        send @!clients[2], event eRequest => { method => 'GET', url => '//service.one/' };
        send @!clients[0], event eRequest => { method => 'GET', url => '//service.one/bar' };
        send @!clients[1], event eRequest => { method => 'GET', url => '//service.one/baz' };
        send @!clients[2], event eRequest => { method => 'GET', url => '//service.one/foo' };
        send @!clients[2], event eRequest => { method => 'GET', url => '//service.two/foo' };
    }
}

# Container ...

container {
    start Main;

}


