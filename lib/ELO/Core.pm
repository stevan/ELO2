package ELO::Core;
use v5.24;
use warnings;

use ELO::Core::EventType;
use ELO::Core::Event;

use ELO::Core::ErrorType;
use ELO::Core::Error;

use ELO::Core::Machine;
use ELO::Core::State;
use ELO::Core::Queue;

use ELO::Core::Loop;
use ELO::Core::Message;

1;

__END__

=pod

A protocol is a set of EventTypes and ErrorTypes that a given machine understands

A Loop has many Machine instances
A Loop has a protocol and a Message queue

Each Machine instance has a PID address
Each Machine instance has an Event queue

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