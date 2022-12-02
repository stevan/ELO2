- Remove the Error and Error::Type they are not needed
- Remove on_error, regular handler will do
- Bless the different subs (entry, exit, handler) to different classes
    - these will define the following:
        - what control-exceptions they can raise
        - what syntax to localize for them
    - the syntax is basically
        - go_to($state)
        - raise($event)
        - send_to($pid, $event)
    - for example:
        - entry can raise and send
        - exit can send
        - handlers can raise, goto and send




Cipy exampkes

https://www.youtube.com/watch?v=hJIST1cEf6A&ab_channel=AbelardoPardo
https://www.youtube.com/watch?v=4rNYAvsSkwk&ab_channel=justAlevel


# Notes from C Runtime
## --------------------------------------------------------


- There should be a Halt event for machines, which all get
- there must always be a start state


- Should a process be it's own concept?
    - instead of a process being a machine instance controlled by a loop
        - add another layer in between?



## --------------------------------------------------------

```
+------+
| Node |
+------+

+------------------+
| Container        |
+------------------+
| %signals         | <-- events from the container
| %timers          | <-- tick timers
| $STDIN           | <-- input  fd
| $STDOUT          | <-- output fd
| $STDERR          | <-- error  fd
| %process_table   | <-- mapping of PID to Machine(PROCESS) instance
| %monitor_table   | <-- mapping of PID to Machine(MONITOR) instance
+--------+---------+



```


Local pid:
    - "0001:foo" <PID-ID>:<name>

Linked pid:
    - "0001@54321:foo" <PID-ID>@<OS-PID>:<name>

Distributed pid:
    - "0001@elo.example.org:foo" <PID-ID>@<hostname>:<name>
    - "0001@127.0.0.1:foo"       <PID-ID>@<localhost>:<name>
