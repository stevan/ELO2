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

## States

my $Init = ELO::Core::State->new(
    name     => 'Init',
    deferred => [ $eRequest, $eResponse ],
    entry    => sub {},
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Init\n" }
    }
);

my $WaitingForRequest = ELO::Core::State->new(
    name     => 'WaitingForRequest',
    deferred => [ $eResponse ],
    entry    => sub {},
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
    deferred => [ $eRequest ],
    entry    => sub {},
    handlers => {
        eResponse => sub ($response) {
            warn "  GOT: eResponse : << " . join(' ', @$response) . "\n";
        }
    },
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Waiting For Responses\n" }
    }
);

## Machine

my $m = ELO::Core::Machine->new(
    pid      => 'init<001>',
    protocol => [ $eRequest, $eResponse ],
    start    => $Init,
    states   => [
        $WaitingForRequest,
        $WaitingForResponse
    ]
);

## manual testing ...

$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/'   ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => [  200, 'OK'  ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/foo'] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/bar'] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => [  300, '>>>' ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => [  404, ':-|' ] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eRequest,  args => ['GET', '/baz'] ));
$m->queue->enqueue(ELO::Core::Event->new( type => $eResponse, args => [  500, ':-O' ] ));

$Init->enter($m->queue);
foreach ( 0 .. 5 ) {
    $WaitingForRequest->enter($m->queue);
    $WaitingForResponse->enter($m->queue);
}


done_testing;



