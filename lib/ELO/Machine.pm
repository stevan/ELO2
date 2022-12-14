package ELO::Machine;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Carp         ();
use Scalar::Util ();
use List::Util   ();
use Data::Dumper ();

use ELO::Machine::Event;
use ELO::Machine::EventQueue;
use ELO::Machine::Activation;

use constant BUILDING => 1; # when the object is being built
use constant BUILT    => 2; # when the object has been built, but not started

use constant STARTING => 3; # before the start state is entered
use constant STARTED  => 4; # after the start state is entered, before we dequeue messages

use constant WAITING  => 5; # if the queue is empty
use constant RUNNING  => 6; # while we are processing the events for the active state
use constant BLOCKED  => 7; # no more events for the active state, but the queue is not empty

use constant STOPING  => 8; # before the active state is exited
use constant STOPPED  => 9; # after the active state has been cleared

use parent 'UNIVERSAL::Object';
use slots (
    name     => sub {},      # human friendly name
    protocol => sub {},      # the set of EventTypes that will be sent/recv by this machine
    start    => sub {},      # the start state of the machine
    states   => sub { +[] }, # the other states of this machine
    # ...
    _queue   => sub {},  # the event queue
    _status  => sub {},  # the various machine status
    _active  => sub {},  # the currently active state
    _topic   => sub {},  # the current Machine::Activation object
);

sub BUILD ($self, $params) {
    $self->set_status(BUILDING);

    $self->{_queue} = ELO::Machine::EventQueue->new;

    # TODO:
    # use the protocol and check to make sure that
    # all the states are correctly handling the
    # input types (or deferring them).

    $self->set_status(BUILT);
}

# duplicate ones self

sub ACTIVATE ($self) {

    # clone the machine so we start fresh ...
    my $machine = ELO::Machine->new(
        name     => $self->{name},
        protocol => $self->{protocol},
        start    => $self->{start},
        states   => [ $self->{states}->@* ],
    );

    # then create an activation as the topic
    # for this state machine ...
    $machine->{_topic} = ELO::Machine::Activation->new(
        machine => $machine
    );

    # return the activation ...`
    return $machine->{_topic};
}

# name

sub name ($self) { $self->{name} }

# protocol

sub protocol ($self) { $self->{protocol} }

# all things status

sub get_status ($self) { $self->{_status} }
sub set_status ($self, $status) {
    $self->{_status} = $status;
}

sub is_building ($self) { $self->{_status} == BUILDING }
sub is_built    ($self) { $self->{_status} == BUILT    }

sub is_starting ($self) { $self->{_status} == STARTING }
sub is_started  ($self) { $self->{_status} == STARTED  }

sub is_waiting  ($self) { $self->{_status} == WAITING  }
sub is_running  ($self) { $self->{_status} == RUNNING  }
sub is_blocked  ($self) { $self->{_status} == BLOCKED  }

sub is_stoping  ($self) { $self->{_status} == STOPING  }
sub is_stopped  ($self) { $self->{_status} == STOPPED  }

# da queue

sub queue ($self) { $self->{_queue} }

sub enqueue_event ($self, $e) {
    $self->{_queue}->enqueue($e)
}

sub dequeue_event ($self) {
    $self->{_queue}->dequeue
}

# da states

sub start  ($self) { $self->{start}  }
sub states ($self) { $self->{states} }

sub all_states ($self) { ($self->{start}, $self->{states}->@*) }

# the trampoline

sub trampoline ($self, $f, $args, %options) {
    eval {
        $f->($self->{_topic}, @$args);
        1;
    } or do {
        my $e = $@;
        if ($options{can_transition} && Scalar::Util::blessed($e) && $e->isa('ELO::Machine::Control::TransitionState')) {

            my $next_state = $e->next_state;
            my $state      = List::Util::first { $_->name eq $next_state } $self->all_states;
            Carp::confess("Unable to find state ($next_state) in the set of states")
                unless defined $state;

            $self->transition_to_state( $state );
        }
        elsif ($options{can_raise_event} && Scalar::Util::blessed($e) && $e->isa('ELO::Machine::Control::RaiseEvent')) {
            $self->handle_event( $e->event );
        }
        else {
            # if it is not one of ours,
            # we re-throw it ...
            die $e;
        }
    };
}

sub active_state       ($self) {    $self->{_active}         }
sub has_active_state   ($self) { !! $self->{_active}         }
sub clear_active_state ($self) {
    $self->{_active} = undef;
    $self->{_queue}->defer([]);
    $self->{_queue}->ignore([]);
}
sub set_active_state   ($self, $next_state) {
    $self->{_active} = $next_state;
    $self->{_queue}->defer( $self->{_active}->deferred );
    $self->{_queue}->ignore( $self->{_active}->ignored  );
}

sub exit_active_state ($self) {
    return unless $self->has_active_state;
    if ( my $exit = $self->active_state->exit ) {
        $self->trampoline(
            $exit,     # call exit function
            [],        # no additional args
            (          # the options
                can_transition  => 0,
                can_raise_event => 0,
            )
        );
    }
    $self->clear_active_state;
}

sub enter_active_state ($self) {
    if ( my $entry = $self->active_state->entry ) {
        $self->trampoline(
            $entry,    # call entry function
            [],        # no additional args
            (          # the options
                can_transition  => 1,
                can_raise_event => 0,
            )
        );
    }
}

sub transition_to_state ($self, $next_state) {
    $self->exit_active_state;
    $self->set_active_state($next_state);
    $self->enter_active_state;
}

sub handle_event ($self, $e) {
    if ( my $handler = $self->active_state->event_handler_for( $e ) ) {
        $self->trampoline(
            $handler,      # the handler for this event
            [ $e ],        # pass event as arg
            (              # the options
                can_transition  => 1,
                can_raise_event => 1
            )
        );
    }
    else {
        # FIXME:
        # this can happen inside the trampoline, so
        # we want to be careful about this ...
        Carp::confess("DROPPED EVENT!" . Data::Dumper::Dumper($e));
    }
}

## ---------------------------------------------
## Machine controls
## ---------------------------------------------
## This is the API which you can control the
## machine.
## ---------------------------------------------

sub ACCEPT ($self, $e) {
    # TODO : check that event is valid protocol input type
    $self->enqueue_event( $e );
}

sub START ($self) {
    $self->set_status(STARTING);

    $self->set_active_state($self->start);
    $self->enter_active_state;

    $self->set_status(STARTED);
    return;
}

sub STOP ($self) {

    $self->set_status(STOPING);

    $self->exit_active_state;
    $self->clear_active_state;

    $self->set_status(STOPPED);
    return;
}

sub TICK ($self) {

    $self->set_status(RUNNING);

    my $q = $self->queue;

    until ($q->is_empty) {

        my $e = $self->dequeue_event;
        last unless defined $e;

        $self->handle_event($e);
    }

    if ($q->is_empty) {
        $self->set_status(WAITING);
    }
    else {
        $self->set_status(BLOCKED);
    }

    # let the caller know if
    # we are waiting or blocked
    return $self->get_status;
}

1;

__END__
