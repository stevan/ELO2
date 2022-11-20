package ELO::Machine::Control::TransitionState;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    goto => sub {}
);

sub next_state ($self) { $self->{goto} }

sub throw ($class, @params) {
    die $class->new( @params );
}

1;

__END__
