package ELO::Core::State;
use v5.24;
use warnings;
use experimental 'signatures', 'postderef';

use Carp 'confess';

use Data::Dumper;

use constant DEBUG => $ENV{DEBUG} // 0;

use parent 'UNIVERSAL::Object';
use slots (
    name     => sub {},
    handlers => sub { +{} }, # Hash<Type, &>
    deferred => sub { +[] }, # Array<Type>
    on_error => sub { +{} }, # Hash<Error, &>
);

sub ENTER ($self, $q) {
    foreach my $type ($self->{deferred}->@*) {
        $q->defer($type);
    }
}

sub LEAVE ($self, $q) {
    foreach my $type ($self->{deferred}->@*) {
        $q->resume($type);
    }
}

sub run ($self, $q) {
    $self->ENTER($q);

    my $e = $q->dequeue( keys $self->{handlers}->%* );

    if ( $e->isa('ELO::Core::Error') ) {
        my $catch = $self->{on_error}->{ $e->type };
        $catch ||= sub { die Dumper [ WTF => $e ] };
        $catch->( $e );
    }
    else {
        $self->{handlers}->{ $e->type }->( $e->args );
    }

    $self->LEAVE($q);
}


1;

__END__
