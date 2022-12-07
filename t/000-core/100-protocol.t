#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;
use Test::Exception;

use ok 'ELO';

subtest '... basic web client' => sub {

    my $eRequest  = ELO::Machine::Event::Type->new( name => 'eRequest'  );
    my $eResponse = ELO::Machine::Event::Type->new( name => 'eResponse' );

    my $eConnectionRequest = ELO::Machine::Event::Type->new( name => 'eConnectionRequest' );

    my $eServiceLocatorRequest  = ELO::Machine::Event::Type->new( name => 'eServiceLocatorRequest' );
    my $eServiceLocatorResponse = ELO::Machine::Event::Type->new( name => 'eServiceLocatorResponse' );

    # these are all clear pairs of request/response

    my $pServiceLocator = ELO::Protocol->new(
        name => 'ServiceLocator',
        pair => [
            $eServiceLocatorRequest,
            $eServiceLocatorResponse
        ]
    );
    isa_ok($pServiceLocator, 'ELO::Protocol');

    is_deeply(
        [ $pServiceLocator->all_types ],
        [
            $eServiceLocatorRequest,
            $eServiceLocatorResponse
        ], '... got all the types');

    is_deeply(
        [ $pServiceLocator->input_types ],
        [ $eServiceLocatorRequest ],
        '... got the input types');

    is_deeply(
        [ $pServiceLocator->output_types ],
        [ $eServiceLocatorResponse ],
        '... got the input types');

    # this one re-uses the eResponse here

    my $pWebServer = ELO::Protocol->new(
        name => 'WebServer',
        pair => [
            $eConnectionRequest,
            $eResponse
        ]
    );
    isa_ok($pWebServer, 'ELO::Protocol');

    is_deeply(
        [ $pWebServer->all_types ],
        [
            $eConnectionRequest,
            $eResponse
        ], '... got all the types');

    is_deeply(
        [ $pWebServer->input_types ],
        [ $eConnectionRequest ],
        '... got the input types');

    is_deeply(
        [ $pWebServer->output_types ],
        [ $eResponse ],
        '... got the input types');

    # this uses

    my $pWebClient = ELO::Protocol->new(
        name => 'WebClient',
        pair => [
            $eRequest,
            $eResponse
        ],
        uses => [
            $pServiceLocator,
            $pWebServer
        ]
    );
    isa_ok($pWebClient, 'ELO::Protocol');

    is_deeply(
        [ $pWebClient->all_types ],
        [
            $eRequest,
            $eServiceLocatorRequest,
            $eConnectionRequest,
            $eResponse,
            $eServiceLocatorResponse
        ], '... got all the types');

    is_deeply(
        [ $pWebClient->input_types ],
        [
            $eRequest,
            $eServiceLocatorRequest,
            $eConnectionRequest,
        ],
        '... got the input types');

    is_deeply(
        [ $pWebClient->output_types ],
        [
            $eResponse,
            $eServiceLocatorResponse
        ],
        '... got the input types');

};

subtest '... basic queue' => sub {

    my $eEnqueueRequest = ELO::Machine::Event::Type->new( name => 'eEnqueueRequest' );
    my $eDequeueRequest = ELO::Machine::Event::Type->new( name => 'eDequeueRequest' );

    my $eDequeueResponse = ELO::Machine::Event::Type->new( name => 'eDequeueResponse' );

    my $E_EMPTY_QUEUE = ELO::Machine::Event::Type->new( name => 'E_EMPTY_QUEUE' );
    my $E_FULL_QUEUE  = ELO::Machine::Event::Type->new( name => 'E_FULL_QUEUE' );

    # request/response pattern for de-queue
    # and raises specific erros

    my $pDequeue = ELO::Protocol->new(
        name => 'Dequeue',
        pair => [
            $eDequeueRequest,
            $eDequeueResponse
        ],
        raises => [ $E_EMPTY_QUEUE ]
    );
    isa_ok($pDequeue, 'ELO::Protocol');

    # while enquee is just an accepted message
    # which means that it expects no response
    # and also an error here

    my $pEnqueue = ELO::Protocol->new(
        name    => 'Enqueue',
        accepts => [ $eEnqueueRequest ],
        raises  => [ $E_FULL_QUEUE ]
    );
    isa_ok($pEnqueue, 'ELO::Protocol');

    # the Queue protocol is a union of both of these

    my $pQueue = ELO::Protocol->new(
        name => 'Queue',
        uses => [ $pEnqueue, $pDequeue ]
    );
    isa_ok($pQueue, 'ELO::Protocol');

    is_deeply(
        [ $pQueue->all_types ],
        [
            $eEnqueueRequest,
            $eDequeueRequest,
            $E_FULL_QUEUE,
            $eDequeueResponse,
            $E_EMPTY_QUEUE,

        ], '... got all the types');

    is_deeply(
        [ $pQueue->input_types ],
        [
            $eEnqueueRequest,
            $eDequeueRequest,
        ],
        '... got the input types');

    is_deeply(
        [ $pQueue->output_types ],
        [
            $E_FULL_QUEUE,
            $eDequeueResponse,
            $E_EMPTY_QUEUE,
        ],
        '... got the input types');

};

subtest '... basic bounce' => sub {
    my $eBeginBounce  = ELO::Machine::Event::Type->new( name => 'eBeginBounce' );
    my $eFinishBounce = ELO::Machine::Event::Type->new( name => 'eFinishBounce' );

    my $eBounceUp   = ELO::Machine::Event::Type->new( name => 'eBounceUp'   );
    my $eBounceDown = ELO::Machine::Event::Type->new( name => 'eBounceDown' );

    # bounce has a basic request/response protocol
    # but also has an internal req/resp protocol
    # internal protocols should only ever be sent
    # to the machine itself

    my $pBounce = ELO::Protocol->new(
        name => 'Bounce',
        pair => [
            $eBeginBounce,
            $eFinishBounce
        ],
        internal => [
            ELO::Protocol->new(
                name => 'BounceInternal',
                pair => [
                    $eBounceUp,
                    $eBounceDown
                ],
            )
        ]
    );
    isa_ok($pBounce, 'ELO::Protocol');
};


done_testing;

1;
