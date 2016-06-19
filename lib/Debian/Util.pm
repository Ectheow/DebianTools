package Debian::Util;
require Exporter;
use File::Basename;
our @ISA=qw(Exporter);
our @EXPORT_OK=qw[
dirname_for_orig
pkgname_from_orig
is_valid_orig
orignames_for_dir];


our $ORIG_REGEX = qr{
    ([\w\d\-]+?)
    _
    ([\w\d\-\.]+)
    \.orig\.tar.*$
}xi;

our $DIR_REGEX = qr{
    ^([\w\d\-\.]+)
    \-
    ([\d\.]+)$
}xi;

our @ORIG_SUFFIXES = qw[gz xz];

sub orignames_for_dir($)
{
    my $fullname = shift;
    my $dirname = basename($fullname);

    return undef if not $dirname =~ m/$DIR_REGEX/;

    my $origname = $1 . "_" . $2 . ".orig.tar.";
    
    my @ret = ();

    (push @ret, $origname . $_) foreach (@ORIG_SUFFIXES);
    @ret = map { dirname($fullname). $_ } @ret if(defined dirname($fullname) and dirname($fullname) ne '.');
    return @ret;

}

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
