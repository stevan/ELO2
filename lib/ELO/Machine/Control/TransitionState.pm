package ELO::Machine::Control::TransitionState;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'ELO::Core::ControlException';
use slots (
    goto => sub {}
);

sub next_state ($self) { $self->{goto} }

1;

__END__
