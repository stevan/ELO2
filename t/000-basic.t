#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;
use Test::More;

use ELO::Core;

my $eRequest = ELO::Core::EventType->new(
    name => 'eRequest',
    checker => sub ($method, $path) {
        $method eq 'GET' # only GET (for now)
            &&
        $path =~ /^\//   # only Absolute paths (for now)
    }
);

my $eResponse = ELO::Core::EventType->new(
    name => 'eResponse',
    checker => sub ($status, $) {
        $status <= 100 && $status >= 599
    }
);

my $Init = ELO::Core::State->new(
    name     => 'Init',
    deferred => [qw[ eRequest eResponse ]],
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Init\n" }
    }
);

my $WaitingForRequest = ELO::Core::State->new(
    name     => 'WaitingForRequest',
    deferred => [qw[ eResponse ]],
    handlers => {
        eRequest => sub ($request) {
            warn "  GOT: eRequest  : >> " . join(' ', @$request) . "\n";
        }
    },
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Waiting For Requests\n" }
    }
);

my $WaitingForResponse = ELO::Core::State->new(
    name     => 'WaitingForResponse',
    deferred => [qw[ eRequest ]],
    handlers => {
        eResponse => sub ($response) {
            warn "  GOT: eResponse : << " . join(' ', @$response) . "\n";
        }
    },
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Waiting For Responses\n" }
    }
);

my $m = ELO::Core::Machine->new(
    pid    => 'init<001>',
    start  => $Init,
    states => [
        $WaitingForRequest,
        $WaitingForResponse
    ]
);

$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/'   ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => ['200', 'OK'  ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/foo'] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/bar'] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => ['300', '>>>' ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => ['404', ':-|' ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/baz'] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => ['500', ':-O' ] ));

$Init->run($m->queue);
foreach ( 0 .. 5 ) {
    $WaitingForRequest->run($m->queue);
    $WaitingForResponse->run($m->queue);
}


done_testing;



