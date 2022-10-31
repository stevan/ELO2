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
    name     => sub {},
    status   => sub {},
    entry    => sub {},
    exit     => sub {},
    handlers => sub { +{} }, # Hash<EventType, &>
    deferred => sub { +[] }, # Array<EventType>
    on_error => sub { +{} }, # Hash<ErrorType, &>
);

sub BUILD ($self, $) {
    $self->{status} = IDLE;
}

sub name     ($self) { $self->{name}     }
sub deferred ($self) { $self->{deferred} }

sub is_active ($self) { $self->{status} == ACTIVE }
sub is_idle   ($self) { $self->{status} == IDLE   }

sub ENTER ($self, $machine) {
    my $next;
    if ($self->{entry}) {
        # wrap this in an eval, .. but do what with the error?
        $next = $self->{entry}->( $self, $machine );
    }

    $self->{status} = ACTIVE;
    return $next;
}

sub EXIT ($self, $machine) {
    if ($self->{exit}) {
        # wrap this in an eval, .. but do what with the error?
        $self->{exit}->( $self, $machine );
    }

    $self->{status} = IDLE;
}

sub TICK ($self, $machine, $e) {
    my $next;

    if ( $e->isa('ELO::Core::Error') ) {
        my $catch = $self->{on_error}->{ $e->type->name };
        $catch ||= sub { die Dumper [ WTF => $e ] };
        $next = $catch->( $self, $machine, $e );
    }
    else {
        # should this be wrapped in an eval?
        $next = $self->{handlers}->{ $e->type->name }->( $self, $machine, $e->payload );
    }

    return $next;
}


1;

__END__
