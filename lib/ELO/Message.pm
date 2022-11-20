package ELO::Message;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    to    => sub {},
    event => sub {},
    from  => sub {},
);

sub to    ($self) { $self->{to}    }
sub event ($self) { $self->{event} }
sub from  ($self) { $self->{from}  }

1;

__END__
