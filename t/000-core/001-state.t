#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;
use Test::Exception;

use ok 'ELO';

subtest '... basic state' => sub {
    my $s = ELO::Machine::State->new( name => 'Init' );
    isa_ok($s, 'ELO::Machine::State');

    is($s->name, 'Init', '... got the name');
    ok($s->is_cold, '... we are cold (by default)');
    ok(!$s->is_hot, '... we are not hot (by default)');

    ok(!$s->has_deferred, '... does not have deferred');
    ok(!$s->has_entry, '... does not have entry');
    ok(!$s->has_exit, '... does not have exit');
    ok(!$s->has_handlers, '... does not have handlers');
};

subtest '... basic state' => sub {

    my $eSkip         = ELO::Machine::Event::Type->new( name => 'eSkip' );
    my $eFoo          = ELO::Machine::Event::Type->new( name => 'eFoo' );
    my $eBar          = ELO::Machine::Event::Type->new( name => 'eBar' );
    my $E_INVALID_FOO = ELO::Machine::Event::Type->new( name => 'E_INVALID_FOO' );

    my %args = (
        name     => 'Init',
        deferred => [ $eSkip ],
        entry    => sub ($m) {},
        exit     => sub ($m) {},
        handlers => {
            eBar => sub ($m, $e) {},
            eFoo => sub ($m, $e) {},
            # errors ...
            E_INVALID_FOO => sub ($m, $e) {},
        }
    );

    my $s = ELO::Machine::State->new( %args );
    isa_ok($s, 'ELO::Machine::State');

    is($s->name, 'Init', '... got the name');
    ok($s->is_cold, '... we are cold (by default)');
    ok(!$s->is_hot, '... we are not hot (by default)');

    ok($s->has_deferred, '... does have deferred');
    is_deeply($s->deferred, $args{deferred}, '... and deferred is what we expect');

    ok($s->has_entry, '... does have entry');
    is($s->entry, $args{entry}, '... got the same entry code ref');

    ok($s->has_exit, '... does have exit');
    is($s->exit, $args{exit}, '... got the same exit code ref');

    ok($s->has_handlers, '... does have handlers');

    is($s->event_handler_for( ELO::Machine::Event->new( type => $eBar ) ),
        $args{handlers}->{eBar},
        '... got the right code ref for eBar');

    is($s->event_handler_for( ELO::Machine::Event->new( type => $eFoo ) ),
        $args{handlers}->{eFoo},
        '... got the right code ref for eFoo');

    is($s->event_handler_for( ELO::Machine::Event->new( type => $E_INVALID_FOO ) ),
        $args{handlers}->{E_INVALID_FOO},
        '... got the right code ref for E_INVALID_FOO');
};


subtest '... constructor errors' => sub {
    throws_ok {
        ELO::Machine::State->new;
    } qr/^A \`name\` is required/,
    '... got the expected error';

    throws_ok {
        ELO::Machine::State->new( name => 'Foo', deferred => [ 10 ] );
    } qr/^The \`deferred\` values should be of type \`ELO\:\:Machine\:\:Event\:\:Type\`/,
    '... got the expected error';
};


done_testing;

1;
