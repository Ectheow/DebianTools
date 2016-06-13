package Debian::BinaryPackage;
use Carp;
use Cwd;
use strict;
use warnings;
use v5.22;
use parent qw[Debian::Package Debian::SourcePackageObject];

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(
        parent_source=>undef,
        package_control_hash=>undef,
        binary_name=>undef,
        @_,
    );

    $self->copy_parent_info
        or do {
        carp "Can't Initialize binary package";
        return undef;
    };

    if (defined $self->{package_control_hash}) {
        $self->init_from_control_hash
            or do {
            carp "Can't initialize binary package from hash";
            return undef;
        };
    }

    return $self;
}


sub init_from_control_hash {
    my ($self, $hash) = @_;

    $self->binary_name($self->{package_control_hash}->{'Package'});

    1
}

sub copy_parent_info {

    my $self = shift;

    my @keys = qw[
        debian_version
        upstream_version
        package_name];
    foreach my $key (@keys) {
        $self->{$key} = $self->parent_source->{$key};
    }
    1
}

sub binary_name {
    my ($self, $arg) = @_;

    if (defined $arg) {
        $self->{binary_name} = $arg;
    }
    return $self->{binary_name};
}
sub arch
{
    return $_[0]->{package_control_hash}->{'Architecture'};
}

1;
