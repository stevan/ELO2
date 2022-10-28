#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;
use Test::More;

use ELO::Core::Error;
use ELO::Core::Event;
use ELO::Core::Queue;
use ELO::Core::State;

my $q = ELO::Core::Queue->new;

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

$q->enqueue(ELO::Core::Event->new( type => 'eRequest', args => ['GET /'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eResponse', args => ['200 OK'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eRequest', args => ['GET /foo'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eRequest', args => ['GET /bar'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eResponse', args => ['300 >>>'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eResponse', args => ['404 :-|'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eRequest', args => ['GET /baz'] ));
$q->enqueue(ELO::Core::Event->new( type => 'eResponse', args => ['500 :-O'] ));

$Init->run($q);
foreach ( 0 .. 5 ) {
    $WaitingForRequest->run($q);
    $WaitingForResponse->run($q);
}


done_testing;



