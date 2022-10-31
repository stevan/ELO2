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

my ($Init, $WaitingForRequest, $WaitingForResponse);

$Init = ELO::Core::State->new(
    name     => 'Init',
    deferred => [ $eRequest, $eResponse ],
    entry    => sub { return $WaitingForRequest },
);

$WaitingForRequest = ELO::Core::State->new(
    name     => 'WaitingForRequest',
    deferred => [ $eResponse ],
    entry    => sub {},
    handlers => {
        eRequest => sub ($request) {
            warn "  GOT: eRequest  : >> " . join(' ', @$request) . "\n";
            return $WaitingForResponse;
        }
    }
);

$WaitingForResponse = ELO::Core::State->new(
    name     => 'WaitingForResponse',
    deferred => [ $eRequest ],
    entry    => sub {},
    handlers => {
        eResponse => sub ($response) {
            warn "  GOT: eResponse : << " . join(' ', @$response) . "\n";
            return $WaitingForRequest;
        }
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

my $q = $m->queue;

## manual testing ...

warn Dumper $m->START;

$q->enqueue(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/'   ] ));
$q->enqueue(ELO::Core::Event->new( type => $eResponse, payload => [  200, 'OK  .oO( ~ )'  ] ));
$q->enqueue(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/foo'] ));
$q->enqueue(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/bar'] ));
warn Dumper $m->RUN;


$q->enqueue(ELO::Core::Event->new( type => $eResponse, payload => [  300, '>>> .oO(foo)' ] ));
$q->enqueue(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/baz'] ));
$q->enqueue(ELO::Core::Event->new( type => $eResponse, payload => [  404, ':-| .oO(bar)' ] ));
$q->enqueue(ELO::Core::Event->new( type => $eResponse, payload => [  500, ':-O .oO(baz)' ] ));
warn Dumper $m->RUN;

warn Dumper $m->STOP;


done_testing;



