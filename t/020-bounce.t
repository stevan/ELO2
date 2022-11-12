#!perl

use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;
use Test::More;

use ELO::Core;

my $eBeginBounce  = ELO::Core::EventType->new( name => 'eBeginBounce' );
my $eFinishBounce = ELO::Core::EventType->new( name => 'eFinishBounce' );

my $eBounceUp   = ELO::Core::EventType->new( name => 'eBounceUp'   );
my $eBounceDown = ELO::Core::EventType->new( name => 'eBounceDown' );

my $Bounce = ELO::Core::Machine->new(
    name     => 'Bounce',
    protocol => [ $eBeginBounce, $eFinishBounce ],
    start    => ELO::Core::State->new(
        name     => 'Init',
        entry    => sub ($self) {
            my $machine = $self->machine;
            warn $machine->pid." : INIT\n";
        },
        handlers => {
            eBeginBounce => sub ($self, $e) {
                my $machine = $self->machine;
                $machine->context->{caller}  = $e->payload->[0];
                $machine->context->{bounces} = $e->payload->[1];

                warn $machine->pid." : eBeginBounce (".(join ", " =>
                    $machine->context->{caller},
                    $machine->context->{bounces})
                .")\n";

                $machine->send_to(
                    $machine->pid,
                    ELO::Core::Event->new( type => $eBounceUp )
                );
                $machine->GOTO('Up');
            }
        }
    ),
    states => [
        ELO::Core::State->new(
            name     => 'Up',
            entry    => sub ($self) {
                my $machine = $self->machine;
                warn $machine->pid." : UP\n";
            },
            handlers => {
                eBounceUp => sub ($self, $e) {
                    my $machine = $self->machine;
                    warn $machine->pid." : eBounceUp\n";
                    $machine->send_to(
                        $machine->pid,
                        ELO::Core::Event->new( type => $eBounceDown )
                    );
                    $machine->GOTO('Down');
                }
            }
        ),
        ELO::Core::State->new(
            name     => 'Down',
            entry    => sub ($self) {
                my $machine = $self->machine;
                warn $machine->pid." : DOWN\n";
            },
            handlers => {
                eBounceDown => sub ($self, $e) {
                    my $machine = $self->machine;
                    warn $machine->pid." : eBounceDown (".$machine->context->{bounces}.")\n";
                    $machine->context->{bounces}--;
                    if ( $machine->context->{bounces} > 0 ) {
                        $machine->send_to(
                            $machine->pid,
                            ELO::Core::Event->new( type => $eBounceUp )
                        );
                        $machine->GOTO('Up');
                    }
                    else {
                        $machine->GOTO('Finish');
                    }
                }
            }
        ),
        ELO::Core::State->new(
            name     => 'Finish',
            entry    => sub ($self) {
                my $machine = $self->machine;
                warn $machine->pid." : FINISH\n";
                $machine->send_to(
                    $machine->context->{caller},
                    ELO::Core::Event->new( type => $eFinishBounce )
                );
            }
        )
    ]
);

my $Main = ELO::Core::Machine->new(
    name     => 'Main',
    protocol => [],
    start    => ELO::Core::State->new(
        name     => 'Init',
        entry    => sub ($self) {
            my $machine = $self->machine;
            warn $machine->pid." : INIT\n";

            my $bounce_001 = $self->machine->loop->spawn('Bounce');
            my $bounce_002 = $self->machine->loop->spawn('Bounce');

            warn $self->machine->pid . " : Bounce Begin\n";
            $self->machine->send_to(
                $_,
                ELO::Core::Event->new(
                    type    => $eBeginBounce,
                    payload => [ $self->machine->pid, 5 ]
                )
            ) foreach ($bounce_001, $bounce_002);
        },
        handlers => {
            eFinishBounce => sub ($self, $e) {
                warn $self->machine->pid . " : Bounce Finished\n";
            }
        }
    )
);


my $L = ELO::Core::Loop->new(
    #monitors => [],
    entry    => 'Main',
    machines => [
        $Main,
        $Bounce
    ]
);

## manual testing ...

$L->LOOP(20);


done_testing;



