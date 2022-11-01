package ELO::Core::Loop;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use ELO::Core::Message;

use List::Util 'uniq';

use parent 'UNIVERSAL::Object';
use slots (
    builders    => sub { +[] }, # a set of Machine::Builder objects
    # ...
    _tick        => sub { 0 },   # the tick counter
    _pid_counter => sub { 0 },   # the pid counter
    _builder_map => sub { +{} }, # mapping of machine name to builder instance
    _pid_map     => sub { +{} }, # mapping of pid to machine instance
    _message_bus => sub { +[] }, # the message bus between machines
);

sub BUILD ($self, $) {
    foreach my $builder ($self->{builders}->@*) {
        $self->{_builder_map}->{ $builder->get_name } = $builder;
    }
}

sub generate_new_pid ($self, $machine) {
    sprintf '%s:%03d' => $machine->name, ++$self->{_pid_counter}
}

sub tick ($self) { $self->{_tick} }

# messages

sub send ($self, $message) {
    push $self->{_message_bus}->@* => $message;
}

sub send_to ($self, $pid, $event) {
    $self->send(
        ELO::Core::Message->new(
            pid   => $pid,
            event => $event,
        )
    );
}

# processes

sub spawn ($self, $machine_name) {
    my $builder = $self->{_builder_map}->{ $machine_name };
    my $machine = $builder->build;

    $machine->assign_pid( $self->generate_new_pid( $machine ) );
    $self->{_pid_map}->{ $machine->pid } = $machine;

    $machine->attach_to_loop( $self );
    $machine->START;

    return $machine->pid;
}

# controls

sub TICK ($self) {

    my @msgs = $self->{_message_bus}->@*;
    $self->{_message_bus}->@* = ();

    my @machines_to_run;
    while (@msgs) {
        my $message = shift @msgs;
        my $machine = $self->{_pid_map}->{ $message->pid };
        if ($machine) {
            $machine->enqueue_event( $message->event );
            push @machines_to_run => $machine;
        }
        else {
            die "Could not find machine for pid(".$message->pid.")"
        }
    }

    foreach my $machine (@machines_to_run) {
        $machine->TICK;
    }

    $self->{_tick}++;

}

sub LOOP ($self, $MAX_TICKS) {
    while ($self->{_tick} <= $MAX_TICKS) {
        $self->TICK;
    }
}

1;

__END__
