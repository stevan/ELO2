package ELO::Machine::EventQueue;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp         ();
use Scalar::Util ();
use List::Util   ();
use Data::Dumper ();

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    _deferred => sub { +{} },
    _ignored  => sub { +{} },
    _inbox    => sub { +[] },
);

sub defer ($self, $deferred) {
    Carp::confess('You must supply a deferred event-type set')
        unless defined $deferred
            && ref $deferred eq 'ARRAY';

    my %deferred;
    foreach ( @$deferred ) {
        Carp::confess('The deferred event-types should be of type `ELO::Machine::Event::Type`')
            unless Scalar::Util::blessed($_)
                && $_->isa('ELO::Machine::Event::Type');
        $deferred{ $_->name }++;
    }

    $self->{_deferred}->%* = %deferred;

    $self;
}

sub ignore ($self, $ignored) {
    Carp::confess('You must supply a ignored event-type set')
        unless defined $ignored
            && ref $ignored eq 'ARRAY';

    my %ignored;
    foreach ( @$ignored ) {
        Carp::confess('The ignored event-types should be of type `ELO::Machine::Event::Type`')
            unless Scalar::Util::blessed($_)
                && $_->isa('ELO::Machine::Event::Type');
        $ignored{ $_->name }++;
    }

    $self->{_ignored}->%* = %ignored;

    $self;
}

sub size ($self) {
    scalar $self->{_inbox}->@*
}

sub is_empty ($self) {
    (scalar $self->{_inbox}->@*) == 0
}

sub enqueue ($self, $e) {
    Carp::confess('You can only enqueue items of type `ELO::Machine::Event` not '.$e)
        unless Scalar::Util::blessed($e)
            && $e->isa('ELO::Machine::Event');

    push $self->{_inbox}->@* => $e
        unless exists $self->{_ignored}->{ $e->type->name };

    $self;
}

sub dequeue ($self) {
    my $idx = 0;

DEQUEUE:
    return if $idx >= scalar $self->{_inbox}->@*;

    my $e = $self->{_inbox}->[ $idx ];

    return unless defined $e;

    if ($self->{_deferred}->{ $e->type->name }) {
        $idx++;
        goto DEQUEUE;
    }

    splice $self->{_inbox}->@*, $idx, 1;
    return $e;
}

1;

__END__
