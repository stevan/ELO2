package ELO::Loop::Process;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use ELO::Loop::Message;

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
    _loop      => sub {},      # the associated event loop
);

sub BUILD ($self, $) {
    $self->{machine}->attach_process( $self );
}

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

# loop

sub loop ($self) { $self->{_loop} }

sub attach_to_loop ($self, $loop) {
    $self->{_loop} = $loop; # FIXME: single assignment
}

sub send_to ($self, $pid, $event) {
    $self->loop->enqueue_message(
        ELO::Loop::Message->new(
            to    => $pid,
            event => $event,
            from  => $self->pid,
        )
    );
}

sub set_alarm ($self, $delay, $pid, $event) {
    $self->loop->set_alarm(
        $delay,
        ELO::Loop::Message->new(
            to    => $pid,
            event => $event,
            from  => $self->pid,
        )
    );
}

## API

sub enqueue_event ($self, $e) {
    $self->machine->enqueue_event( $e );
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
