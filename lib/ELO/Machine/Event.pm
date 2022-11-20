package ELO::Machine::Event;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp         ();
use Scalar::Util ();

use ELO::Machine::Event::Type;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    type    => sub {},
    payload => sub { +[] },
);

sub BUILD ($self, $) {
    Carp::confess('The `type` must be of type `ELO::Machine::Event::Type`')
        unless Scalar::Util::blessed($self->{type})
            && $self->{type}->isa('ELO::Machine::Event::Type');
}

sub type    ($self) { $self->{type}    }
sub payload ($self) { $self->{payload} }

1;

__END__
