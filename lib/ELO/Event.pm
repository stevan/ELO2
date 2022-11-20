package ELO::Event;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp         ();
use Scalar::Util ();
use Data::Dumper ();

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    type    => sub {},
    payload => sub { +[] },
);

sub BUILD ($self, $) {
    Carp::confess('The `type` must be of type `ELO::Event::Type`')
        unless Scalar::Util::blessed($self->{type})
            && $self->{type}->isa('ELO::Event::Type');
}

sub type    ($self) { $self->{type}    }
sub payload ($self) { $self->{payload} }

1;

__END__
