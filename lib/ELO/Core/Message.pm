package ELO::Core::Message;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    pid   => sub {},
    event => sub {},
);

sub pid   ($self) { $self->{pid}   }
sub event ($self) { $self->{event} }

1;

__END__
