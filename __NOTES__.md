
- Revive `ProcessRecord` object
    - it will provide the user with sensible API for accessing machine data
        - the syntax is basically
            - go_to($state)
            - raise($event)
            - send_to($pid, $event)
            - spawn($machine, ?@flags, %env)
            - exit( ?$event )
    - should also know some meta info
        - parent PID

- Bless the different subs (entry, exit, handler) to different classes
    - these will define the following:
        - what control-exceptions they can raise
        - what syntax to localize for them
    - for example:
        - entry can raise, goto and send
        - exit can send
        - handlers can raise, goto and send

- create set of flags for events that Machine can send like
    - flags would be:
        - ON_START # sent when machine starts
        - ON_STOP  # sent when machine stops
        - ON_EXIT  # sent when machine exits
        - ON_TRANS # sent when machine transition states
        - ON_BLOCK # sent when machine enters BLOCKING state
        - ON_EVENT # sent when machine handles event
    - these kind of mimic the various status of the Machine
        - maybe it should be `ON_${status}` events for each??
    - they could also be passed to `spawn`
        - spawn(
            $machine_name,
            [ ON_EXIT, ON_TRANS ], # optional
            ( ... env variables ), # if first arg is not ARRAY slurp env
        )
    - the events are an internal EventTypes
        - and they have standard payloads (TBD)
    - these events will be sent to the machine that called `spawn`
        - this requires calling `spawn` via the Machine
            - because local data is required in the payloads
    - this should create a sub-protocol
        - and inject it into it's own machine protocol

- Event::Type should define the payload for Event
    - this should be a type constraint
    - and maybe a constructor as well??

- improve annotation of States
    - HOT/COLD is not enought
    - States can be ...
        - ENTRY    -> this state is the entry state
        - TERMINAL -> this state can only exit
    - States that have context
        - HOT/COLD  -> being in a HOT state is bad, COLD is good
        - PASS/FAIL -> for regexp like states that have pass/fail
    - States should also annotate transitions
        - GOES_TO(@states) -> this can transition to these states
            - GOES_TO($self) is implied

- Removals??
    - remove the Monitors, they seem less useful
        - perhaps make Monitors a diff thing
            - that can be attached to specific machines
                - or maybe types of machines
            - and can watch events to that machine
                - and maybe add FLAGS at runtime

## --------------------------------------------------------

package NODE {
    has @.containers;

    sub LISTEN;
}

package CONTAINER {
    has $.entry;
    has @.machines;
    has @.monitors;

    sub START;
    sub STOP;
    sub TICK;

    sub LOOP; # implies START/TICK.../STOP
}

package MACHINE {
    has $.start;
    has @.states;

    sub CLONE;

    sub ACCEPT;
    sub START;
    sub STOP;
    sub TICK;

    sub EXIT;
}

package MACHINE::HANDLE {
    sub pid;

    sub ENV;

    sub goto;
    sub raise;

    sub send;

    sub spawn;

    sub exit;
}








## --------------------------------------------------------
## --------------------------------------------------------


# Notes from C Runtime
## --------------------------------------------------------


- There should be a Halt event for machines, which all get
- there must always be a start state


- Should a process be it's own concept?
    - instead of a process being a machine instance controlled by a loop
        - add another layer in between?


## --------------------------------------------------------


Local pid:
    - "0001:foo" <PID-ID>:<name>

Linked pid:
    - "0001@54321:foo" <PID-ID>@<OS-PID>:<name>

Distributed pid:
    - "0001@elo.example.org:foo" <PID-ID>@<hostname>:<name>
    - "0001@127.0.0.1:foo"       <PID-ID>@<localhost>:<name>
