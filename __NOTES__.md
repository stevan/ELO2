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
