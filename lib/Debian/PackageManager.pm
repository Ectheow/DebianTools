package Debian::PackageManager;
use Debian::SourcePackage;
use Debian::PackageBuilder;
use warnings;
use strict;
use Moose;
use JSON;

has 'package_hash_file' => (
    isa => 'Str',
    is => 'rw',
    trigger => \&parse_hash_file,
);

has 'packages' => (
    isa => 'ArrayRef',
    is => 'rw',
    default => sub {[]}
);

sub parse_hash_file($)
{
    my ($self) = @_;

    my $text = do 
    {
        open my $fh, "<", $self->package_hash_file or die "$!";
        local $/=undef;
        <$fh>;
    };

    my $package_config_hash = decode_json $text;

    while(my ($k, $v) = (each %$package_config_hash)) {

        my $pkg = Debian::PackageBuilder->new(
            dir => $v->{dir},
            name => $k);
        die "Couldn't construct package: $k" if not defined $pkg;
        push @{$self->packages}, $pkg;
    }

    1
}

1
