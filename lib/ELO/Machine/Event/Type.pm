package ELO::Machine::Event::Type;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    name => sub {},
);

sub name ($self) { $self->{name} }

# XXX
# Should this be a constructor for Event objects?
# such as a `new_event` method, that would accept
# the payload value and construct an event with
# this as the type?
#
# or is this starting to add sugar where we might
# not need it?

1;

__END__
