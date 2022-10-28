
package main;

use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;
use Test::More;

package Event {
    use v5.24;
    use warnings;
    use experimental 'signatures', 'postderef';

    use Data::Dumper;

    use parent 'UNIVERSAL::Object::Immutable';
    use slots (
        type => sub {},
        args => sub { +[] },
    );

    sub type ($self) { $self->{type} }
    sub args ($self) { $self->{args} }

    sub is_error ($self) { $self->{type} =~ /^E_/ ? 1 : 0 }
}

# FIXME - make Error class
# FIXME - make Signal class?

package Actor::Queue {
    use v5.24;
    use warnings;
    use experimental 'signatures', 'postderef';

    use Carp 'confess';

    use Data::Dumper;

    use constant DEBUG => $ENV{DEBUG} // 0;

    use parent 'UNIVERSAL::Object';
    use slots (
        inbox => sub { +[] },
        # ...
        _deferred => sub { +{} }
    );

    sub is_deferred ($self, $type) {
        !! exists $self->{_deferred}->{$type};
    }

    sub defer ($self, $type) {
        $self->{_deferred}->{$type}++;
    }

    sub resume ($self, $type) {
        delete $self->{_deferred}->{$type};
    }

    sub enqueue ($self, $e) {
        push $self->{inbox}->@* => $e
    }

    sub dequeue ($self, @types) {
        my $idx = 0;

    DEQUEUE:
        warn "IDX: $idx" if DEBUG;
        my $e = $self->{inbox}->[ $idx ];

        return Event->new(
            type => 'E_EMPTY_QUEUE',
            args => [{ for_types => \@types }]
        ) unless defined $e;

        # FIXME - this can be a real loop, no need for GOTO
        if ( $self->is_deferred( $e->type ) ) {
            $idx++;
            goto DEQUEUE;
        }

        if ( grep $e->type eq $_, @types ) {
            # FIXME - use splice
            warn Dumper [
                [ $idx, scalar $self->{inbox}->@* ],
                [ 0 .. $idx-1 ],
                [ $idx+1 .. (scalar($self->{inbox}->@*) - 1 ) ],
            ] if DEBUG;
            $self->{inbox} = [
                $self->{inbox}->@[
                    0 .. $idx-1
                ],
                $self->{inbox}->@[
                    $idx+1 .. (scalar($self->{inbox}->@*) - 1 )
                ]
            ],
            return $e;
        }
        else {
            return Event->new(
                type => 'E_TYPE_MISMATCH',
                args => [ { found => $e->type, wanted => \@types } ]
            );
        }
    }
}


package Actor::State {
    use v5.24;
    use warnings;
    use experimental 'signatures', 'postderef';

    use Carp 'confess';

    use Data::Dumper;

    use constant DEBUG => $ENV{DEBUG} // 0;

    use parent 'UNIVERSAL::Object';
    use slots (
        name     => sub {},
        handlers => sub { +{} }, # Hash<Type, &>
        deferred => sub { +[] }, # Array<Type>
        on_error => sub { +{} }, # Hash<Error, &>
    );

    sub ENTER ($self, $q) {
        foreach my $type ($self->{deferred}->@*) {
            $q->defer($type);
        }
    }

    sub LEAVE ($self, $q) {
        foreach my $type ($self->{deferred}->@*) {
            $q->resume($type);
        }
    }

    sub run ($self, $q) {
        $self->ENTER($q);

        my $e = $q->dequeue( keys $self->{handlers}->%* );

        if ( $e->is_error ) {
            my $catch = $self->{on_error}->{ $e->type };
            $catch ||= sub { die Dumper [ WTF => $e ] };
            $catch->( $e );
        }
        else {
            $self->{handlers}->{ $e->type }->( $e->args );
        }

        $self->LEAVE($q);
    }
}

my $q = Actor::Queue->new;

my $Init = Actor::State->new(
    name     => 'Init',
    deferred => [qw[ eRequest eResponse ]],
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Init\n" }
    }
);

my $WaitingForRequest = Actor::State->new(
    name     => 'WaitingForRequest',
    deferred => [qw[ eResponse ]],
    handlers => {
        eRequest => sub ($request) {
            warn "  GOT: eRequest  : >> " . join(' ', @$request) . "\n";
        }
    },
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Waiting For Requests\n" }
    }
);

my $WaitingForResponse = Actor::State->new(
    name     => 'WaitingForResponse',
    deferred => [qw[ eRequest ]],
    handlers => {
        eResponse => sub ($response) {
            warn "  GOT: eResponse : << " . join(' ', @$response) . "\n";
        }
    },
    on_error => {
        E_EMPTY_QUEUE => sub { warn "ERROR: Empty Queue in Waiting For Responses\n" }
    }
);

$q->enqueue(Event->new( type => 'eRequest', args => ['GET /'] ));
$q->enqueue(Event->new( type => 'eResponse', args => ['200 OK'] ));
$q->enqueue(Event->new( type => 'eRequest', args => ['GET /foo'] ));
$q->enqueue(Event->new( type => 'eRequest', args => ['GET /bar'] ));
$q->enqueue(Event->new( type => 'eResponse', args => ['300 >>>'] ));
$q->enqueue(Event->new( type => 'eResponse', args => ['404 :-|'] ));
$q->enqueue(Event->new( type => 'eRequest', args => ['GET /baz'] ));
$q->enqueue(Event->new( type => 'eResponse', args => ['500 :-O'] ));

$Init->run($q);
foreach ( 0 .. 5 ) {
    $WaitingForRequest->run($q);
    $WaitingForResponse->run($q);
}


done_testing;



