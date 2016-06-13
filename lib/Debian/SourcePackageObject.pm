package Debian::SourcePackageObject;
use Carp;
use v5.2;

sub new
{
    my $class = shift;

    my $opts = {
        parent_source=>undef,
        @_,
    };


    return bless $opts, $class;

}

sub parent_source {
    my ($self, $arg) = @_;

    if (defined $arg) {
        if (not $arg->isa('Debian::SourcePackage')) {
            carp "I need a debian source pacakge.";
        }
        $self->{parent_source} = $arg;
        $self->copy_parent_info;
    }

    return $self->{parent_source};
}

1;
