
type PID = string;
type EventType = string;

type Address = (
    pid : PID,
);

type Event = (
    type : EventType,
    args : seq[Any],
);

type Message = (
    address : Address,
    event   : Event,
);

/*
// Message construction

(
    address = (pid = $PID),
    event   = (
        type = "eRequest",
        args = [ "GET /foo/" ]
    ),
)

*/

type ErrorType = EventType;

type Error : Event = (
    code : int,
);

type State = (
    name     : string,
    deferred : seq[EventType],
    handlers : map[EventType, Code[Event]],
    on_error : map[ErrorType, Code[Error]],
);

type Machine = (
    queue  : seq[Message],
    states : seq[State],
);


// ...

type Loop = (
    machines : seq[Machine],
    msg_bus  : seq[Message],
);













