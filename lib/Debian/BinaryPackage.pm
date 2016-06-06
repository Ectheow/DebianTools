package Debian::BinaryPackage;
use Carp;
use Cwd;
use strict;
use warnings;
use v5.22;
use parent 'Debian::Package';

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(
        parent_source=>undef,
        @_,
    );

    $self->init()
        or do {
        carp "Can't Initialize binary package";
        return undef;
    };

    return $self;
}


sub init {
    1
}

sub parent_source {
    my ($self, $arg) = @_;

    if (defined $arg) {
        if (not $arg->isa('Debian::SourcePackage')) {
            carp "I need a debian source pacakge.";
        }
        $self->{parent_source} = $arg;
    }

    return $self->{parent_source};
}

1;
