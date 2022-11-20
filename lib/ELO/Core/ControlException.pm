package ELO::Core::ControlException;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'UNIVERSAL::Object::Immutable';
use slots;

sub throw ($class, @params) {
    die $class->new( @params );
}

1;

__END__
