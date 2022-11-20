package ELO::Machine::Control::RaiseEvent;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    event => sub {}
);

sub event ($self) { $self->{event} }

sub throw ($class, @params) {
    die $class->new( @params );
}

1;

__END__
