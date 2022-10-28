package ELO::Core::Machine;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use ELO::Core::Queue;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    pid      => sub {},
    protocol => sub {},
    start    => sub {},
    states   => sub { +[] },
    queue    => sub {},
);

sub BUILD ($self, $) {
    $self->{queue} = ELO::Core::Queue->new;
}

sub pid ($self) { $self->{pid} }

sub protocol ($self) { $self->{protocol} }

sub start ($self) { $self->{start} }

sub states ($self) { $self->{states} }
sub queue  ($self) { $self->{queue}  }

1;

__END__
