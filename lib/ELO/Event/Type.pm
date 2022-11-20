package ELO::Event::Type;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name => sub {},
);

sub name ($self) { $self->{name} }

1;

__END__
