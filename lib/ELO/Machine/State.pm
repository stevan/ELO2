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
    ignored     => sub { +[] },  # Array<EventType> events that should be ignored in this state
    on_error    => sub { +{} },  # Hash<ErrorType, &> error handlers, keyed by error type
    temperature => sub { COLD }, # is this HOT or COLD
);

sub BUILD ($self, $) {
    Carp::confess('A `name` is required')
        unless $self->{name};

    foreach my $deferred ( $self->{deferred}->@* ) {
        Carp::confess('The `deferred` values should be of type `ELO::Machine::Event::Type`')
            unless Scalar::Util::blessed($deferred)
                && $deferred->isa('ELO::Machine::Event::Type');
    }

    foreach my $ignored ( $self->{ignored}->@* ) {
        Carp::confess('The `ignored` values should be of type `ELO::Machine::Event::Type`')
            unless Scalar::Util::blessed($ignored)
                && $ignored->isa('ELO::Machine::Event::Type');
    }

    # QUESTION:
    # Should I bless the various CODE handlers
    # {entry, exit, on_error & handlers} into
    # a class so the trampoline knows what to
    # do?

    # QUESTION:
    # Should I Lock all these values, so we can be
    # sure it can be reused the class itself is already
    # immutable, but we want to be certain folks don't
    # alter these as well.
    #
    # And if so, should we create copies of them? so that
    # we can be sure that we own them?
    #
    # use overload     ();
    # use Hash::Util   ();
    #
    # Internals::SvREADONLY( $self->{name}, 1 );
    # Hash::Util::lock_hash( $self->{handlers}->%* );
    # Internals::SvREADONLY( $self->{deferred}->@*, 1 );
    # Hash::Util::lock_hash( $self->{on_error}->%* );
}

# some accessors

sub name     ($self) { $self->{name}     }
sub deferred ($self) { $self->{deferred} }
sub ignored  ($self) { $self->{ignored}  }

sub has_deferred ($self) { !! scalar $self->{deferred}->@* }
sub has_ignored  ($self) { !! scalar $self->{ignored}->@*  }

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

    if ($e->isa('ELO::Machine::Error')) {
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
