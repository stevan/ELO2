package ELO::Core::EventType;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name    => sub {},
    checker => sub { sub { 1 } },
);

sub name ($self) { $self->{name} }

sub check ($self, @args) {
    return $self->{checker}->(@args);
}

1;

__END__
