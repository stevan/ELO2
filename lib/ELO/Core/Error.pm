package ELO::Core::Error;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use parent 'ELO::Core::Event';
use slots (
    code => sub {},
);

sub code ($self) { $self->{code} }

1;

__END__
