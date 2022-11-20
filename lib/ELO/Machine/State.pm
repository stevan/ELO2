package ELO::Machine::State;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp         ();
use Scalar::Util ();
use Data::Dumper ();

use constant HOT  => 1;
use constant COLD => 2;

use constant DEBUG => $ENV{DEBUG} // 0;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name        => sub {},       # human friendly name
    entry       => sub {},       # the entry callback, called when a state is ENTERed
    exit        => sub {},       # the exit callback, called when a state is EXITed
    handlers    => sub { +{} },  # Hash<EventType, &> event handlers, keyed by event type
    deferred    => sub { +[] },  # Array<EventType> events that should be deferred in this state
    on_error    => sub { +{} },  # Hash<ErrorType, &> error handlers, keyed by error type
    temperature => sub { COLD }, # is this HOT or COLD
);

sub BUILD ($self, $) {
    Carp::confess('A `name` is required')
        unless $self->{name};

    foreach my $deferred ( $self->{deferred}->@* ) {
        Carp::confess('The `deferred` values should be of type `ELO::Event::Type`')
            unless Scalar::Util::blessed($deferred)
                && $deferred->isa('ELO::Event::Type');
    }

    # XXX - should I bless the various handlers
    # {entry, exit, on_error & handlers} into
    # a class so the trampoline knows what to
    # do?
}

# duplicate ones self

sub CLONE ($self) {
    ELO::Machine::State->new(
        name        => $self->{name},
        entry       => $self->{entry},
        exit        => $self->{exit},
        handlers    => { $self->{handlers}->%* },
        deferred    => [ $self->{deferred}->@* ],
        on_error    => { $self->{on_error}->%* },
        temperature => $self->{temperature},
    )
}

# some accessors

sub name     ($self) { $self->{name}     }
sub deferred ($self) { $self->{deferred} }

sub has_deferred ($self) { !! scalar $self->{deferred}->@* }

# temperature

sub is_hot  ($self) { $self->{temperature} == HOT  }
sub is_cold ($self) { $self->{temperature} == COLD }

# controls

sub has_entry ($self) { !! $self->{entry} }
sub has_exit  ($self) { !! $self->{exit}  }

sub entry ($self) { $self->{entry} }
sub exit  ($self) { $self->{exit}  }

sub has_error_handlers ($self) { !! scalar keys $self->{on_error}->%* }
sub has_handlers       ($self) { !! scalar keys $self->{handlers}->%* }

sub event_handler_for ($self, $e) {
    my $e_name = $e->type->name;

    if ($e->isa('ELO::Error')) {
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
