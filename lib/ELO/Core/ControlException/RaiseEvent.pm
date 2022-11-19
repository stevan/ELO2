package ELO::Core::ControlException::RaiseEvent;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'ELO::Core::ControlException';
use slots (
    event => sub {}
);

sub event ($self) { $self->{event} }

1;

__END__
