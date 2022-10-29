package ELO::Core::Queue;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp       'confess';
use List::Util 'any';

use Data::Dumper;
use constant DEBUG => $ENV{DEBUG} // 0;

use ELO::Core::Error;
use ELO::Core::ErrorType;

my $E_EMPTY_QUEUE = ELO::Core::ErrorType->new( name => 'E_EMPTY_QUEUE' );

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    inbox => sub { +[] },
);

sub enqueue ($self, $e) {
    push $self->{inbox}->@* => $e
}

sub dequeue ($self, @deferred) {
    my $idx = 0;

DEQUEUE:
    my $e = $self->{inbox}->[ $idx ];

    return ELO::Core::Error->new(
        type => $E_EMPTY_QUEUE
    ) unless defined $e;

    if (any { $e->type->matches( $_ ) } @deferred) {
        $idx++;
        goto DEQUEUE;
    }

    splice $self->{inbox}->@*, $idx, 1;
    return $e;
}

1;

__END__
