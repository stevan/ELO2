#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;
use Test::Exception;

use ok 'ELO';

my $eSkip = ELO::Machine::Event::Type->new( name => 'eSkip' );
my $eFoo  = ELO::Machine::Event::Type->new( name => 'eFoo' );

subtest '... basic queue' => sub {

    my $q = ELO::Machine::EventQueue->new;
    isa_ok($q, 'ELO::Machine::EventQueue');

    ok($q->is_empty, '... the queue is empty');
    is($q->size, 0, '... got the expected number of items');

    my $foo_event = ELO::Machine::Event->new( type => $eFoo );
    $q->enqueue( $foo_event );

    ok(!$q->is_empty, '... the queue is no longer empty');
    is($q->size, 1, '... got the expected number of items');

    my $dequeued = $q->dequeue;
    is($foo_event, $dequeued, '... got the expected event back');

    ok($q->is_empty, '... the queue is empty again');
    is($q->size, 0, '... got the expected number of items');
};

subtest '... basic queue w/ deferred' => sub {

    my $q = ELO::Machine::EventQueue->new;
    isa_ok($q, 'ELO::Machine::EventQueue');

    ok($q->is_empty, '... the queue is empty');

    my @events = (
        ELO::Machine::Event->new( type => $eFoo ),
        ELO::Machine::Event->new( type => $eSkip ),
        ELO::Machine::Event->new( type => $eFoo ),
        ELO::Machine::Event->new( type => $eFoo ),
        ELO::Machine::Event->new( type => $eFoo ),
        ELO::Machine::Event->new( type => $eSkip ),
        ELO::Machine::Event->new( type => $eFoo ),
    );
    $q->enqueue( $_ ) foreach @events;

    ok(!$q->is_empty, '... the queue is no longer empty');
    is($q->size, 7, '... got the expected number of items');

    $q->defer([ $eSkip ]);
    foreach my $idx ( 0, 2, 3 ) {
        my $dequeued = $q->dequeue;
        isa_ok($dequeued, 'ELO::Machine::Event');
        is($dequeued->type, $eFoo, '... got the expected event type');
        is($events[ $idx ], $dequeued, '... got the expected event back ('.$idx.')');
    }

    ok(!$q->is_empty, '... the queue is not empty ');
    is($q->size, 4, '... got the expected number of items');

    $q->defer([ $eFoo ]);
    foreach my $idx ( 1, 5 ) {
        my $dequeued = $q->dequeue;
        isa_ok($dequeued, 'ELO::Machine::Event');
        is($dequeued->type, $eSkip, '... got the expected event type');
        is($events[ $idx ], $dequeued, '... got the expected event back ('.$idx.')');
    }

    ok(!$q->is_empty, '... the queue is not empty ');
    is($q->size, 2, '... got the expected number of items');

    $q->defer([]);
    foreach my $idx ( 4, 6 ) {
        my $dequeued = $q->dequeue;
        isa_ok($dequeued, 'ELO::Machine::Event');
        is($dequeued->type, $eFoo, '... got the expected event type');
        is($events[ $idx ], $dequeued, '... got the expected event back ('.$idx.')');
    }

    ok($q->is_empty, '... the queue is empty again');
    is($q->size, 0, '... got the expected number of items');

};

done_testing;

1;
