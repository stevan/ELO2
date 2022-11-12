package ELO::Core::Queue;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use List::Util 'any';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    inbox => sub { +[] },
);

sub is_empty ($self) {
    (scalar $self->{inbox}->@*) == 0
}

sub enqueue ($self, $e) {
    push $self->{inbox}->@* => $e
}

sub dequeue ($self, @deferred) {
    my $idx = 0;

DEQUEUE:
    return if $idx >= scalar $self->{inbox}->@*;

    my $e = $self->{inbox}->[ $idx ];

    return unless defined $e;

    if (any { $e->type->matches( $_ ) } @deferred) {
        $idx++;
        goto DEQUEUE;
    }

    splice $self->{inbox}->@*, $idx, 1;
    return $e;
}

1;

__END__
