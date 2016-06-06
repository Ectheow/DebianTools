package Debian::Package;
use Carp;

sub new {
    my $class = shift;

    my $self = {
        upstream_version => undef,       # string 
        debian_version   => undef,       # string
        package_name     => undef,       # string
        @_,
    };

    return bless $self, $class;
}


sub version {
    my ($self, $arg) = @_;

    if (defined $arg) {
        my ($deb, $up) = split "-", $arg;
        $self->debian_version($deb);
        $self->upstream_version($up);
    }

    return join "-", ($self->{upstream_version}, $self->{debian_version});
}

sub name {
    my ($self, $arg) = @_;

    if (defined $arg) {
        $self->{package_name} = $arg;
    }

    return $self->{package_name};
}

sub upstream_version {
    my ($self, $arg) = @_;

    if (defined $arg) {
        $self->{upstream_version} = $arg;
    }

    return $self->{upstream_version};
}

sub debian_version {
    my ($self, $arg) = @_;

    if (defined $arg) {
        $self->{debian_version} = $arg;
    }

    return $self->{debian_version};
}

sub distribution {
    my ($self, $arg) = @_;

   if (defined $arg) {
       $self->{distribution} = $arg;
   } 

   return $self->{distribution};
}

1;
