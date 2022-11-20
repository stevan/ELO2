package ELO::ControlException::TransitionState;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'ELO::ControlException';
use slots (
    goto => sub {}
);

sub next_state ($self) { $self->{goto} }

1;

__END__
