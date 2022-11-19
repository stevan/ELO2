package ELO::Core::State;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp         'confess';
use Scalar::Util 'blessed';

use Data::Dumper;

use constant HOT  => 1;
use constant COLD => 2;

use constant DEBUG => $ENV{DEBUG} // 0;

use parent 'UNIVERSAL::Object';
use slots (
    name     => sub {},      # human friendly name
    entry    => sub {},      # the entry callback, called when a state is ENTERed
    exit     => sub {},      # the exit callback, called when a state is EXITed
    handlers => sub { +{} }, # Hash<EventType, &> event handlers, keyed by event type
    deferred => sub { +[] }, # Array<EventType> events that should be deferred in this state
    on_error => sub { +{} }, # Hash<ErrorType, &> error handlers, keyed by error type
    # ...
    _temperature => sub {}, # is this HOT or COLD
);

sub BUILD ($self, $params) {

    # it can only be marked HOT, otherwise it is COLD
    $self->{_temperature} = $params->{is_hot} ? HOT : COLD;
}

# duplicate ones self

sub CLONE ($self) {
    ELO::Core::State->new(
        name     => $self->{name},
        entry    => $self->{entry},
        exit     => $self->{exit},
        handlers => { $self->{handlers}->%* },
        deferred => [ $self->{deferred}->@* ],
        on_error => { $self->{on_error}->%* },
        is_hot   => ($self->is_hot ? 1 : 0),
    )
}

# some accessors

sub name     ($self) { $self->{name}     }
sub deferred ($self) { $self->{deferred} }

# temperature

sub is_hot  ($self) { $self->{_temperature} == HOT  }
sub is_cold ($self) { $self->{_temperature} == COLD }

# controls

sub entry ($self) { $self->{entry} }
sub exit  ($self) { $self->{exit} }

sub event_handler_for ($self, $e) {
    my $e_name = $e->type->name;

    if ($e->isa('ELO::Core::Error')) {
        if (exists $self->{on_error}->{ $e_name }) {
            return $self->{on_error}->{ $e_name };
        }
    }
    elsif (exists $self->{handlers}->{ $e_name }) {
        return $self->{handlers}->{ $e_name };
    }
    else {
        # XXX - should this throw an exception?
        return;
    }
}

1;

__END__
