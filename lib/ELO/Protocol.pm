package ELO::Protocol;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use List::Util;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name     => sub {},
    pair     => sub {},
    accepts  => sub {},
    throws   => sub {},
    internal => sub {},
    uses     => sub {},
);

# We can monitor all the types if we want

sub all_types ($self) {
    List::Util::uniq( $self->input_types, $self->output_types );
}

# We can check that all input types have a corresponding handler
# in the states where they are used

sub input_types ($self) {
    # the first element of pair + all accepts
    List::Util::uniq(
        ($self->{pair}    ? $self->{pair}->[0]                        : ()),
        ($self->{accepts} ? $self->{accepts}->@*                      : ()),
        ($self->{uses}    ? map { $_->input_types } $self->{uses}->@* : ()),
    )
}

# We can verify that all sent messages are one of the output types
# in the states where they are used

sub output_types ($self) {
    # the second element of pair + all throws
    List::Util::uniq(
        ($self->{pair}   ? $self->{pair}->[1]                         : ()),
        ($self->{throws} ? $self->{throws}->@*                        : ()),
        ($self->{uses}   ? map { $_->output_types } $self->{uses}->@* : ()),
    )
}

## accessors

sub pair ($self) {
    # event request/response pair
    # --
    # this implies that we can check for 1-to-1 mapping
    # with some kind of monitor which could be used to
    # test things, and to enforce protocol
    #
    # this implies one input type, and one output type
    # and this is important because we want to classiy
    # input/output types
    $self->{pair};
}

sub accepts ($self) {
    # events that do not require response
    # --
    #
    # these are just things we accept, thats all. they
    # are input types
    $self->{accepts};
}

sub throws ($self) {
    # errors that can be thrown
    # --
    #
    # these are basically output events, but that should
    # always be errors
    $self->{throws};
}

sub internal ($self) {
    # internal protocol (only sent to local-machine)
    # --
    #
    # we can ensure that these events are always delivered
    # to $self (the running machine instance),
    $self->{internal};
}

sub uses ($self) {
    # a list of protocols used by this protocol
    # --
    #
    # this means this protocol will
    # - send any of the cumulative input types
    # - recv any of the cumulative output types
    $self->{uses};
}

1;

__END__

