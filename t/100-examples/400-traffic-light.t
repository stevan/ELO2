#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use Term::ANSIColor qw[ :constants ];

use ELO;

my $eSignalStart   = ELO::Machine::Event::Type->new( name => 'eSignalStart'   );
my $eTimerFinished = ELO::Machine::Event::Type->new( name => 'eTimerFinished' );

my $pTrafficSignal = ELO::Protocol->new(
    accepts  => [ $eSignalStart ],
    internal => ELO::Protocol->new(
        name    => 'TrafficSignalTimer',
        accepts => [ $eTimerFinished ]
    )
);

my $TrafficSignal = ELO::Machine->new(
    name     => 'TrafficSignal',
    protocol => $pTrafficSignal,
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            pass('... TrafficSignal->Init initializing');
        },
        handlers => {
            eSignalStart => sub ($m, $e) {
                pass('... TrafficSignal->Init got eSignalStart');
                $m->GOTO('Green');
            }
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'Green',
            ignored  => [ $eSignalStart ],
            entry    => sub ($m) {
                print GREEN('');
                pass('... TrafficSignal->Green entered Green state');
                $m->set_alarm(
                    $m->env->{DELAY},
                    $m->pid,
                    ELO::Machine::Event->new( type => $eTimerFinished ),
                );
            },
            exit => sub { print RESET },
            handlers => {
                eTimerFinished => sub ($m, $e) {
                    pass('... TrafficSignal->Green timer finished');
                    $m->GOTO('Yellow');
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'Yellow',
            ignored  => [ $eSignalStart ],
            entry    => sub ($m) {
                print YELLOW('');
                pass('... TrafficSignal->Yellow entered Yellow state');
                $m->set_alarm(
                    $m->env->{DELAY},
                    $m->pid,
                    ELO::Machine::Event->new( type => $eTimerFinished ),
                );
            },
            exit => sub { print RESET },
            handlers => {
                eTimerFinished => sub ($m, $e) {
                    pass('... TrafficSignal->Yellow timer finished');
                    $m->GOTO('Red');
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'Red',
            ignored  => [ $eSignalStart ],
            entry    => sub ($m) {
                print RED('');
                pass('... TrafficSignal->Red entered Red state');
                $m->set_alarm(
                    $m->env->{DELAY},
                    $m->pid,
                    ELO::Machine::Event->new( type => $eTimerFinished ),
                );
            },
            exit => sub { print RESET },
            handlers => {
                eTimerFinished => sub ($m, $e) {
                    pass('... TrafficSignal->Red timer finished');
                    $m->GOTO('Green');
                }
            }
        ),
    ]
);

my $Main = ELO::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            pass('... Main->Init entering');

            my $light = $m->container->spawn('TrafficSignal', ( DELAY => 5 ));

            $m->send_to(
                $light,
                ELO::Machine::Event->new( type => $eSignalStart )
            );
            $m->send_to(
                $light,
                ELO::Machine::Event->new( type => $eSignalStart )
            );
        }
    )
);


my $L = ELO::Container->new(
    entry    => 'Main',
    machines => [
        $Main,
        $TrafficSignal
    ]
);

## manual testing ...

$L->LOOP(50);


done_testing;



