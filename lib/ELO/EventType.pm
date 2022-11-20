package ELO::EventType;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name => sub {},
);

sub name ($self) { $self->{name} }

sub matches ($self, $other) {
    $other->isa( __PACKAGE__ )
        &&
    $self->name eq $other->name
}

1;

__END__
