package ELO::Machine::Event::Type;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name => sub {},
);

sub name ($self) { $self->{name} }

1;

__END__
