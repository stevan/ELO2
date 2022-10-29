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
    entry    => sub {},
    handlers => sub { +{} }, # Hash<EventType, &>
    deferred => sub { +[] }, # Array<EventType>
    on_error => sub { +{} }, # Hash<ErrorType, &>
);

sub enter ($self, $q) {

    $self->{entry}->( $self, $q );

    my $e = $q->dequeue( $self->{deferred}->@* );

    if ( $e->isa('ELO::Core::Error') ) {
        my $catch = $self->{on_error}->{ $e->type->name };
        $catch ||= sub { die Dumper [ WTF => $e ] };
        $catch->( $e );
    }
    else {
        $self->{handlers}->{ $e->type->name }->( $e->payload );
    }
}


1;

__END__
