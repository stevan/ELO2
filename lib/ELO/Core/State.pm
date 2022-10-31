package ELO::Core::State;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp 'confess';

use Data::Dumper;

use constant IDLE   => 1;
use constant ACTIVE => 2;

use constant DEBUG => $ENV{DEBUG} // 0;

use parent 'UNIVERSAL::Object';
use slots (
    name     => sub {},      # human name
    entry    => sub {},      # the entry callback, called when a state is ENTERed
    exit     => sub {},      # the exit callback, called when a state is EXITed
    handlers => sub { +{} }, # Hash<EventType, &> event handlers, keyed by event type
    deferred => sub { +[] }, # Array<EventType> events that should be deferred in this state
    on_error => sub { +{} }, # Hash<ErrorType, &> error handlers, keyed by error type
    # ...
    _machine => sub {}, # machine this state is attached to
    _status  => sub {}, # the status, either IDLE or ACTIVE
);

sub BUILD ($self, $) {
    $self->{_status} = IDLE;
}

# some accessors

sub name     ($self) { $self->{name}     }
sub deferred ($self) { $self->{deferred} }

# attached machine

sub machine ($self) { $self->{_machine} }

sub attach_to_machine ($self, $machine) {
    $self->{_machine} = $machine;
}

# status

sub is_active ($self) { $self->{_status} == ACTIVE }
sub is_idle   ($self) { $self->{_status} == IDLE   }

# controls

sub ENTER ($self) {

    if ($self->{entry}) {
        # wrap this in an eval, .. but do what with the error?
        $self->{entry}->( $self );
    }

    $self->{_status} = ACTIVE;
    return;
}

sub EXIT ($self) {

    if ($self->{exit}) {
        # wrap this in an eval, .. but do what with the error?
        $self->{exit}->( $self );
    }

    $self->{_status} = IDLE;
    return;
}

sub TICK ($self, $e) {

    if ( $e->isa('ELO::Core::Error') ) {
        my $catch = $self->{on_error}->{ $e->type->name };
        $catch ||= sub { die Dumper [ WTF => $e ] };
        $catch->( $self, $e );
    }
    else {
        # should this be wrapped in an eval?
        $self->{handlers}->{ $e->type->name }->( $self, $e );
    }

    return;
}


1;

__END__
