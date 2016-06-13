package Debian::Util;
require Exporter;
our @ISA=qw(Exporter);
our @EXPORT_OK=qw[
dirname_for_orig
pkgname_from_orig
is_valid_orig
];

our $ORIG_REGEX = qr{
    ([\w\d\-]+?)
    _
    ([\w\d\-\.]+)
    \.orig\.tar.*$
}xi;

sub dirname_for_orig($)
{
    my $orig = shift;

    $orig =~ s/^(.*?)\.orig.*$/$1/;
    $orig =~ tr/_/-/;

    return $orig;
}

sub pkgname_from_orig($)
{
    my $orig_fname = shift;

    $orig_fname =~ m/$ORIG_REGEX/;

    return $1;
}

sub is_valid_orig($)
{
    my $orig_fname = shift;
    return $orig_fname =~ m/$ORIG_REGEX/;
}

1;
