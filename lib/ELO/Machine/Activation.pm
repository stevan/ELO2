package ELO::Machine::Activation;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use ELO::Container::Message;

use ELO::Machine::Control::TransitionState;
use ELO::Machine::Control::RaiseEvent;

use constant PROCESS => 1; # this machine is being used as a process
use constant MONITOR => 2; # this machine is being used as a monitor

use parent 'UNIVERSAL::Object';
use slots (
    machine    => sub {},      # the machine this process runs
    # ...
    _kind      => sub {},      # is a process or monitor?
    _pid       => sub {},      # an externally supplied identifier for this machine instance
    _env       => sub { +{} }, # immutable env settings for the machine
    _context   => sub { +{} }, # mutable context for the machine
    _container => sub {},      # the associated container
);

sub BUILD ($self, $) {
    $self->{machine}->attach_activation( $self );
}

sub name ($self) { $self->{machine}->name }

sub machine ($self) { $self->{machine} }

# machine type

sub kind ($self) { $self->{_kind} }

sub is_monitor ($self) { $self->{_kind} == MONITOR }
sub is_process ($self) { $self->{_kind} == PROCESS }

# FIXME: these should be single assignment
sub become_monitor ($self) { $self->{_kind} = MONITOR }
sub become_process ($self) { $self->{_kind} = PROCESS }

# context

sub env     ($self) { $self->{_env} }
sub context ($self) { $self->{_context} }

# pid

sub pid ($self) { $self->{_pid} }

sub assign_pid ($self, $pid) {
    $self->{_pid} = $pid; # FIXME: single assignment
}

# container

sub container ($self) { $self->{_container} }

sub attach_to_container ($self, $container) {
    $self->{_container} = $container; # FIXME: single assignment
}

sub send_to ($self, $pid, $event) {
    $self->container->enqueue_message(
        ELO::Container::Message->new(
            to    => $pid,
            event => $event,
            from  => $self->pid,
        )
    );
}

sub set_alarm ($self, $delay, $pid, $event) {
    $self->container->set_alarm(
        $delay,
        ELO::Container::Message->new(
            to    => $pid,
            event => $event,
            from  => $self->pid,
        )
    );
}

sub spawn ($self, @args) {
    $self->container->spawn( @args )
}

# controls

sub go_to ($self, $state_name) {
    # NOTE:
    # this resolves the state name within the trampoline
    # instead of trying to do it here, the result is the
    # same in the end.
    ELO::Machine::Control::TransitionState->throw( goto => $state_name );
}

sub raise ($self, $event) {
    ELO::Machine::Control::RaiseEvent->throw( event => $event );
}

## --------------------------------------------------------
## Delegate to Machine API
## --------------------------------------------------------

sub ACCEPT ($self, $e) {
    $self->machine->ACCEPT( $e );
}

sub TICK ($self) {
    $self->machine->TICK;
}

sub START ($self) {
    $self->machine->START;
}

sub STOP ($self) {
    $self->machine->STOP;
}

1;

__END__
