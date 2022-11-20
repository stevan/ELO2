package ELO::Machine::Error;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp         ();
use Scalar::Util ();

use ELO::Machine::Error::Type;

use parent 'ELO::Machine::Event';
use slots;

sub BUILD ($self, $) {
    Carp::confess('The `type` must be of type `ELO::Machine::Error::Type`')
        unless Scalar::Util::blessed($self->type)
            && $self->type->isa('ELO::Machine::Error::Type');
}

1;

__END__
