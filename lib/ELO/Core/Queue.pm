package ELO::Core::Queue;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp 'confess';

use Data::Dumper;

use ELO::Core::Error;

use constant DEBUG => $ENV{DEBUG} // 0;

use parent 'UNIVERSAL::Object';
use slots (
    inbox     => sub { +[] },
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

    return ELO::Core::Error->new(
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
        return ELO::Core::Error->new(
            type => 'E_TYPE_MISMATCH',
            args => [ { found => $e->type, wanted => \@types } ]
        );
    }
}

1;

__END__
