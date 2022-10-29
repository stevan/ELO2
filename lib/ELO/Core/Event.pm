package ELO::Core::Event;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    type    => sub {},
    payload => sub { +[] },
);

sub type    ($self) { $self->{type}    }
sub payload ($self) { $self->{payload} }

1;

__END__
