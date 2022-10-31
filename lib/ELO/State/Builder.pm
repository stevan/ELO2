package ELO::State::Builder;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use ELO::Core::State;

use parent 'UNIVERSAL::Object';
use slots (
    parent   => sub {},      # the parent builder
    name     => sub {},      # human friendly name
    entry    => sub {},      # the entry callback, called when a state is ENTERed
    exit     => sub {},      # the exit callback, called when a state is EXITed
    handlers => sub { +{} }, # Hash<EventType, &> event handlers, keyed by event type
    deferred => sub { +[] }, # Array<EventType> events that should be deferred in this state
    on_error => sub { +{} }, # Hash<ErrorType, &> error handlers, keyed by error type
);

sub name  ($self, $name)  { $self->{name}  = $name;  $self }
sub entry ($self, $entry) { $self->{entry} = $entry; $self }
sub exit  ($self, $exit)  { $self->{exit}  = $exit;  $self }

sub deferred ($self, @deferred) {
    $self->{deferred} = [ @deferred ];
    $self;
}

sub add_handler_for ($self, $event_type, $handler) {
    $self->{handlers}->{ $event_type } = $handler;
    $self;
}

sub add_error_handler_for ($self, $error_type, $handler) {
    $self->{on_error}->{ $error_type } = $handler;
    $self;
}

sub end ($self) {
    $self->{parent};
}

sub build ($self) {
    my %params = %$self;
    delete $params{parent};
    return ELO::Core::State->new(\%params);
}

1;

__END__
