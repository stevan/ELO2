#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO;

sub DEBUG ($msg) {
    warn $msg if $ENV{DEBUG};
}

my $eBeginBounce  = ELO::Machine::Event::Type->new( name => 'eBeginBounce' );
my $eFinishBounce = ELO::Machine::Event::Type->new( name => 'eFinishBounce' );

my $eBounceUp   = ELO::Machine::Event::Type->new( name => 'eBounceUp'   );
my $eBounceDown = ELO::Machine::Event::Type->new( name => 'eBounceDown' );

my $Bounce = ELO::Machine->new(
    name     => 'Bounce',
    protocol => [ $eBeginBounce, $eFinishBounce ],
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            DEBUG $m->pid." : INIT\n";
        },
        handlers => {
            eBeginBounce => sub ($m, $e) {
                $m->context->{caller}  = $e->payload->[0];
                $m->context->{bounces} = $e->payload->[1];
                $m->context->{height}  = $e->payload->[2];

                DEBUG $m->pid." : eBeginBounce (".(join ", " =>
                    $m->context->{caller},
                    $m->context->{bounces},
                    $m->context->{height})
                .")\n";

                $m->set_alarm( $m->context->{height} => (
                    $m->pid, ELO::Machine::Event->new( type => $eBounceUp )
                ));
                $m->go_to('Up');
            }
        }
    ),
    states => [
        ELO::Machine::State->new(
            name     => 'Up',
            entry    => sub ($m) {
                DEBUG $m->pid." : UP entering\n";
            },
            handlers => {
                eBounceUp => sub ($m, $e) {
                    DEBUG $m->pid." : UP handling -> eBounceUp\n";
                    $m->set_alarm(
                        $m->context->{height} => (
                            $m->pid,
                            ELO::Machine::Event->new( type => $eBounceDown )
                        )
                    );
                    $m->go_to('Down');
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'Down',
            entry    => sub ($m) {
                DEBUG $m->pid." : DOWN entering\n";
            },
            handlers => {
                eBounceDown => sub ($m, $e) {
                    DEBUG $m->pid." : DOWN handling -> eBounceDown (".$m->context->{bounces}.")\n";
                    $m->context->{bounces}--;
                    if ( $m->context->{bounces} > 0 ) {
                        $m->set_alarm(
                            $m->context->{height} => (
                                $m->pid,
                                ELO::Machine::Event->new( type => $eBounceUp )
                            )
                        );
                        $m->go_to('Up');
                    }
                    else {
                        $m->go_to('Finish');
                    }
                }
            }
        ),
        ELO::Machine::State->new(
            name     => 'Finish',
            entry    => sub ($m) {
                DEBUG $m->pid." : FINISH\n";
                $m->send_to(
                    $m->context->{caller},
                    ELO::Machine::Event->new( type => $eFinishBounce )
                );
            }
        )
    ]
);

my $Main = ELO::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Machine::State->new(
        name     => 'Init',
        entry    => sub ($m) {
            DEBUG $m->pid." : INIT\n";

            my $bounce_001 = $m->spawn('Bounce');
            my $bounce_002 = $m->spawn('Bounce');

            DEBUG $m->pid . " : Bounce Begin\n";

            $m->send_to(
                $bounce_001,
                ELO::Machine::Event->new(
                    type    => $eBeginBounce,
                    payload => [ $m->pid, 2, 6 ]
                )
            );

            $m->send_to(
                $bounce_002,
                ELO::Machine::Event->new(
                    type    => $eBeginBounce,
                    payload => [ $m->pid, 2, 3 ]
                )
            );
        },
        handlers => {
            eFinishBounce => sub ($m, $e) {
                DEBUG $m->pid . " : Bounce Finished\n";
                pass('... Main -> Init -> bounce finished');
            }
        }
    )
);


my $L = ELO::Container->new(
    #monitors => [],
    entry    => 'Main',
    machines => [
        $Main,
        $Bounce
    ]
);

## manual testing ...

$L->LOOP(50);


done_testing;



