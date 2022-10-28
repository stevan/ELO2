package ELO::Core::Loop;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Data::Dumper;

use parent 'UNIVERSAL::Object::Immutable';
use slots (
    machines => sub { +[] },
    _msg_bus => sub { +[] },
);

1;

__END__
