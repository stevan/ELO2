package ELO::Core::Machine;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Data::Dumper;

use ELO::Core::Queue;

use constant STOPPED => 1;
use constant RUNNING => 2;

use parent 'UNIVERSAL::Object';
use slots (
    pid      => sub {},
    protocol => sub {},
    start    => sub {},
    states   => sub { +[] },
    queue    => sub {},
    active   => sub {},
    state    => sub {},
);

sub BUILD ($self, $) {
    $self->{state} = STOPPED;
    $self->{queue} = ELO::Core::Queue->new;
}

sub pid      ($self) { $self->{pid}      }
sub protocol ($self) { $self->{protocol} }
sub start    ($self) { $self->{start}    }
sub states   ($self) { $self->{states}   }
sub queue    ($self) { $self->{queue}    }

sub is_running ($self) { $self->{state} == RUNNING }
sub is_stopped ($self) { $self->{state} == STOPPED }

sub START ($self) {

    my $q = $self->queue;

    my $start = $self->start;

    my $goto = $start->ENTER($q);
    # if we are going to another state,
    if ($goto) {
        # TODO : make sure this is a member of {states}

        # exit this one ...
        $start->EXIT($q);
        # and enter the next one ...
        $goto->ENTER($q);
    }
    else {
        # but if we are not going to
        # another state use the start
        # state when we enter the loop
        $goto = $start;
    }

    $self->{active} = $goto;

    $self->{state} = RUNNING;

    return $self;
}

sub STOP ($self) {

    if ( $self->{active} ) {
        $self->{active}->EXIT($self->queue);
        $self->{active} = undef;
    }

    $self->{state} = STOPPED;

    $self;
}

sub RUN ($self) {

    my $q = $self->queue;

    until ($q->is_empty) {
        my $e = $q->dequeue( $self->{active}->deferred->@* );

        last unless defined $e;

        # TODO; check invarient here, only one state is ACTIVE

        my $next = $self->{active}->TICK($e);
        if ($next) {
            # exit his one
            $self->{active}->EXIT($q);
            # if we move to a new state ...
            $next->ENTER($q);
            $self->{active} = $next;
        }

        # else, we can do nothing, {active} state is in the right state
    }

    return $self;
}

1;

__END__
