package ELO;
use v5.24;
use warnings;

use ELO::Machine::Event;
use ELO::Machine::Event::Type;

use ELO::Machine::Error;
use ELO::Machine::Error::Type;

use ELO::Machine;
use ELO::Machine::State;
use ELO::Machine::Control::RaiseEvent;
use ELO::Machine::Control::TransitionState;

use ELO::Container;
use ELO::Container::Message;

use ELO::Machine::EventQueue;

1;

__END__

=pod

A protocol is a set of EventTypes and ErrorTypes that a given machine understands

A Loop has many Machine instances
A Loop has a Message queue for delivering message to machines

Each Machine instance has a PID address
Each Machine instance has an Event queue
Each Machine instance has one or more State instances

When a loop begins
    messages are processed
        each enclosed event is delivered to the appropriate Machine PID
            these trigger handlers in the Machine State


Each state in the P state machine has an entry function associated with
it which gets executed when the state machine enters that state.

After executing the entry function, the machine tries to dequeue an event
from the input buffer or blocks if the buffer is empty.

Upon dequeuing an event from the input queue of the machine, the attached
handler is executed which might transition the machine to a different state.


=cut
