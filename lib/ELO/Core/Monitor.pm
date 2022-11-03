package ELO::Core::Monitor;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef', 'lexical_subs';

use Carp 'confess';

use Data::Dumper;

use parent 'ELO::Core::Machine';
use slots;

1;

__END__
