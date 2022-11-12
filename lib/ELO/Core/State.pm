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
    _machine     => sub {}, # machine this state is attached to
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

# attached machine

sub machine ($self) { $self->{_machine} }

sub attach_to_machine ($self, $machine) {
    $self->{_machine} = $machine; # FIXME: single assignment
}

# temperature

sub is_hot  ($self) { $self->{_temperature} == HOT  }
sub is_cold ($self) { $self->{_temperature} == COLD }

# controls

sub ENTER ($self) {

    if ($self->{entry}) {
        # wrap this in an eval, .. but do what with the error?
        $self->{entry}->( $self );
    }

    return;
}

sub EXIT ($self) {

    if ($self->{exit}) {
        # wrap this in an eval, .. but do what with the error?
        $self->{exit}->( $self );
    }

    return;
}

sub TICK ($self, $e) {

    my $err;
    if ( !$e->isa('ELO::Core::Error') ) {
        eval {
            die "Could not find handler for type(".$e->type->name.")"
                unless exists $self->{handlers}->{ $e->type->name };
            $self->{handlers}->{ $e->type->name }->( $self, $e );
            1;
        } or do {
            $err = $@;
            if (!(blessed $err && $err->isa('ELO::Core::Error'))) {
                $err = ELO::Core::Error->new(
                    type    => ELO::Core::ErrorType->new( name => 'E_UNKNOWN_ERROR'),
                    payload => [ $err ],
                );
            }
        };
    }
    elsif ( $e->isa('ELO::Core::Error') ) {
        $err = $e;
    }

    if ($err) {
        my $catch = $self->{on_error}->{ $err->type->name };
        $catch ||= sub { die Dumper [ WTF => $err ] };
        $catch->( $self, $err );
    }

    return;
}


1;

__END__
