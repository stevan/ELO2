# Notes from C Runtime
## --------------------------------------------------------


- There should be a Halt event for machines, which all get
- there must always be a start state


- `goto`/`raise` should be implemented with execptions
    - these are kind of machine controls
        - essentially forces the stopping of the handler
            - without the user needing to care
    - legit errors can be handled better
        - if they aren't ours, they're errors
    - and we can establish the available controls for diff states
        - `entry` can goto, but not raise
        - `exit` can do neither
        - `tick` can do both


- Should a process be it's own concept?
    - instead of a process being a machine instance controlled by a loop
        - add another layer in between?



## --------------------------------------------------------

```
+------+
| Node |
+------+

+-----------+
| Container |
+-----------+
| %signals  |
| $STDIN    |
| $STDOUT   |
| $STDERR   |
+-----------+
  |
  |     +------+
  `-(*)-| Loop |
        +------------------+
        | %process_table   |
        +--------+---------+
        | PID -> | Machine |
        +--------+---------+
                   |
                   |     +------------+
                   `-(*)-| State, ... |
                         +------------+


```


Local pid:
    - "0001:foo" <PID-ID>:<name>

Linked pid:
    - "0001@54321:foo" <PID-ID>@<OS-PID>:<name>

Distributed pid:
    - "0001@elo.example.org:foo" <PID-ID>@<hostname>:<name>
    - "0001@127.0.0.1:foo"       <PID-ID>@<localhost>:<name>
