package ELO::Core::Event;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    type => sub {},
    args => sub { +[] },
);

sub type ($self) { $self->{type} }
sub args ($self) { $self->{args} }

1;

__END__
