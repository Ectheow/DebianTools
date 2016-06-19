package Util::Dirstack::Error;
use Moose;
extends 'Throwable::Error';

package Util::Dirstack;
use v5.20;
use Moose;
use Cwd;

has 'dirs' => (
    isa => 'ArrayRef',
    is => 'ro',
    default => sub {[]}
);


sub pushd($$)
{
    my ($self, $dir) = @_;

    Util::Dirstack::Error->throw({message => "$dir doesn't exist or isn't a dir"})
        if not -d $dir;

    if(@{$self->dirs} == 0) {
        push @{$self->dirs}, getcwd();
    }

    if($dir =~ m!^([^/]|\.)!) {
        $dir = getcwd() . "/" .  $dir;
    }

    chdir $dir;
    push @{$self->dirs}, $dir;

    $dir;
}

sub popd($)
{
    my ($self) = @_;

    return undef if @{$self->dirs} == 0;

    my $dir = pop @{$self->dirs};
    Util::Dirstack::Error->throw({message => "$dir is on the stack but no longer exists. did you chdir?"})
        if not -d $dir;
    chdir $dir;

    $dir;
}

sub DEMOLISH
{
    my $self = shift;

    while($self->popd) {;}
}

1;
