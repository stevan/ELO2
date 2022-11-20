package ELO::Machine;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Carp 'confess';

use Data::Dumper;

use ELO::Queue;
use ELO::Event;

use ELO::ControlException::TransitionState;
use ELO::ControlException::RaiseEvent;

use constant PROCESS => 1; # this machine is being used as a process
use constant MONITOR => 2; # this machine is being used as a monitor

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
    _kind      => sub {},      # how is this process being used
    _env       => sub { +{} }, # immutable env settings for the machine
    _context   => sub { +{} }, # mutable context for the machine
    _loop      => sub {},      # the associated event loop
    _pid       => sub {},      # an externally supplied identifier for this machine instance
    _queue     => sub {},      # the event queue
    _status    => sub {},      # the various machine status
    _active    => sub {},      # the currently active state
    _state_map => sub { +{} }, # a mapping of state-name to state
);

sub BUILD ($self, $params) {
    $self->set_status(BUILDING);

    $self->{_queue} = ELO::Queue->new;

    foreach my $state ( $self->all_states ) {
        $self->{_state_map}->{ $state->name } = $state;
    }

    $self->set_status(BUILT);
}

# duplicate ones self

sub CLONE ($self) {
    ELO::Machine->new(
        name     => $self->{name},
        protocol => $self->{protocol},
        start    => $self->{start}->CLONE,
        states   => [ map { $_->CLONE } $self->{states}->@* ],
    )
}

# name

sub name ($self) { $self->{name} }

# context

sub env     ($self) { $self->{_env} }
sub context ($self) { $self->{_context} }

# pid

sub pid ($self) { $self->{_pid} }

sub assign_pid ($self, $pid) {
    $self->{_pid} = $pid; # FIXME: single assignment
}

# loop

sub loop ($self) { $self->{_loop} }

sub attach_to_loop ($self, $loop) {
    $self->{_loop} = $loop; # FIXME: single assignment
}

sub send_to ($self, $pid, $event) {
    $self->loop->enqueue_message(
        ELO::Message->new(
            to    => $pid,
            event => $event,
            from  => $self->pid,
        )
    );
}

sub set_alarm ($self, $delay, $pid, $event) {
    $self->loop->set_alarm(
        $delay,
        ELO::Message->new(
            to    => $pid,
            event => $event,
            from  => $self->pid,
        )
    );
}

# protocol

sub protocol ($self) { $self->{protocol} }

# machine type

sub kind ($self) { $self->{_kind} }

sub is_monitor ($self) { $self->{_kind} == MONITOR }
sub is_process ($self) { $self->{_kind} == PROCESS }

# FIXME: these should be single assignment
sub become_monitor ($self) { $self->{_kind} = MONITOR }
sub become_process ($self) { $self->{_kind} = PROCESS }

# all things status

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
    $self->{_queue}->dequeue( $self->{_active}->deferred->@* )
}

# da states

sub start  ($self) { $self->{start}  }
sub states ($self) { $self->{states} }

sub all_states ($self) { ($self->{start}, $self->{states}->@*) }

# the trampoline

sub trampoline ($self, $f, $args, %options) {
    eval {
        $f->(@$args);
        1;
    } or do {
        my $e = $@;
        if ($options{can_transition} && Scalar::Util::blessed($e) && $e->isa('ELO::ControlException::TransitionState')) {
            $self->transition_to_state( $e->next_state );
        }
        elsif ($options{can_raise_event} && Scalar::Util::blessed($e) && $e->isa('ELO::ControlException::RaiseEvent')) {
            $self->handle_event( $e->event );
        }
        else {
            die $e;
        }
    };
}

sub active_state       ($self) {    $self->{_active}         }
sub has_active_state   ($self) { !! $self->{_active}         }
sub clear_active_state ($self) {    $self->{_active} = undef }
sub set_active_state   ($self, $next_state) {
    $self->{_active} = $next_state;
}

sub exit_active_state ($self) {
    return unless $self->has_active_state;
    if ( my $exit = $self->active_state->exit ) {
        $self->trampoline(
            $exit,     # call exit function
            [ $self ], # with $machine
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
            [ $self ], # with $machine
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
            [ $self, $e ], # the args to the handler
            (              # the options
                can_transition  => 1,
                can_raise_event => 1
            )
        );
    }
    else {
        use Data::Dumper;
        confess "DROPPED EVENT!" . Dumper($e);
    }
}

## Machine controls

sub GOTO ($self, $state_name) {
    confess "Unable to find state ($state_name) in the set of states"
        unless exists $self->{_state_map}->{ $state_name };
    ELO::ControlException::TransitionState
        ->throw( goto => $self->{_state_map}->{ $state_name } );
}

sub RAISE ($self, $error) {
    ELO::ControlException::RaiseEvent->throw( event => $error );
}

sub START ($self) {
    $self->set_status(STARTING);

    $self->set_active_state($self->start);
    $self->enter_active_state;

    $self->set_status(STARTED);

    return $self;
}

sub STOP ($self) {

    $self->set_status(STOPING);

    $self->exit_active_state;
    $self->clear_active_state;

    $self->set_status(STOPPED);

    return $self;
}

sub TICK ($self) {

    $self->set_status(RUNNING);

    my $q = $self->queue;

    until ($q->is_empty) {
        #warn Dumper $q;

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

    return $self;
}

1;

__END__
