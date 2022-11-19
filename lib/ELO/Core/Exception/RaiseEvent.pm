package ELO::Core::Exception::RaiseEvent;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'ELO::Core::Exception';
use slots (
    event => sub {}
);

sub event ($self) { $self->{event} }

1;

__END__
