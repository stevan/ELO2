package ELO::Machine::Builder;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use ELO::State::Builder;

use ELO::Core::Machine;

use parent 'UNIVERSAL::Object';
use slots (
    name     => sub {},      # human friendly name
    protocol => sub {},      # the set of EventTypes that will be used by this machine
    start    => sub {},      # the start state of the machine
    states   => sub { +[] }, # the other states of this machine
);

# getters

sub get_name     ($self) { $self->{name}     }
sub get_protocol ($self) { $self->{protocol} }
sub get_start    ($self) { $self->{start}    }
sub get_states   ($self) { $self->{states}   }

# setters

sub name ($self, $name) {
    $self->{name} = $name;
    $self;
}

sub protocol ($self, $protocol) {
    $self->{protocol} = $protocol;
    $self;
}

sub start_state ($self) {
    $self->{start} = ELO::State::Builder->new( parent => $self );
    $self->{start};
}

sub add_state ($self) {
    my $new_state = ELO::State::Builder->new( parent => $self );
    push $self->{states}->@* => $new_state;
    return $new_state;
}

sub build ($self) {
    my %params = %$self;
    $params{start}  = $params{start}->build;
    $params{states} = [ map $_->build, $params{states}->@* ];
    return ELO::Core::Machine->new(\%params);
}

1;

__END__
