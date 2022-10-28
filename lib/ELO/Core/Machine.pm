package ELO::Core::Machine;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use ELO::Core::Queue;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    states => sub { +[] },
    queue  => sub {}
);

sub BUILD ($self, $) {
    $self->{queue} = ELO::Core::Queue->new;
}

1;

__END__
