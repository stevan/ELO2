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
    entry    => sub ($self, $m) { return $WaitingForRequest },
);

$WaitingForRequest = ELO::Core::State->new(
    name     => 'WaitingForRequest',
    deferred => [ $eResponse ],
    handlers => {
        eRequest => sub ($self, $m, $request) {
            warn "  GOT: eRequest  : >> " . join(' ', @$request) . "\n";
            return $WaitingForResponse;
        }
    }
);

$WaitingForResponse = ELO::Core::State->new(
    name     => 'WaitingForResponse',
    deferred => [ $eRequest ],
    handlers => {
        eResponse => sub ($self, $m, $response) {
            warn "  GOT: eResponse : << " . join(' ', @$response) . "\n";
            return $WaitingForRequest;
        }
    }
);

## Machine

my $M = ELO::Core::Machine->new(
    pid      => 'init<001>',
    protocol => [ $eRequest, $eResponse ],
    start    => $Init,
    states   => [
        $WaitingForRequest,
        $WaitingForResponse
    ]
);

## manual testing ...

$M->START;

$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/'   ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  200, 'OK  .oO( ~ )'  ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/foo'] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/bar'] ));
$M->RUN;


$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  300, '>>> .oO(foo)' ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eRequest,  payload => ['GET', '/baz'] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  404, ':-| .oO(bar)' ] ));
$M->enqueue_event(ELO::Core::Event->new( type => $eResponse, payload => [  500, ':-O .oO(baz)' ] ));
$M->RUN;

$M->STOP;


done_testing;



