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

A Loop has many Machine instances

Each Machine instance has a PID address
Each Machine instance has an Event queue

Loop has a protocol and a Message queue

When a loop begins
    messages are processed
        each enclosed event is delivered to the appropriate Machine PID
            these trigger handlers in the Machine State


=cut
