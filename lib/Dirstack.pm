package Dirstack;
use warnings;
use strict;
use v5.20;
use Cwd;

sub new 
{
    my $class = shift;
    my $self = bless {
        dirstack=>[]
    };

    return $self;
}

sub pushd
{
    my ($self, $dir) = @_;

    my $cwd = getcwd;
    push @{$self->{dirstack}}, $cwd if $cwd ne $dir;
    chdir $dir if $cwd ne $dir;

    1
}

sub popd
{
    my ($self) = @_;

    return undef unless scalar @{$self->{dirstack}};
    my $dir = pop @{$self->{dirstack}};

    chdir $dir;
    $dir;
}

sub DESTROY 
{
    my ($self) = @_;

    while($self->popd()) {;}
}

1
