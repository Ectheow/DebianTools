package Debian::Util;
use v5.20;
use strict;
use warnings;
require Exporter;
use File::Basename;
use File::Find;
use Archive::Tar;
use IO::Zlib;
use Carp;
use Switch;
our @ISA=qw(Exporter);
our @EXPORT_OK=qw[
dirname_for_orig
pkgname_from_orig
is_valid_orig
create_orig_tarball_for_dir
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
    @ret = map { dirname($fullname). "/" . $_ } @ret if(defined dirname($fullname) and dirname($fullname) ne '.');
    return @ret;

}

sub create_orig_tarball_for_dir($)
{
    my ($dir) = @_;

    my @orignames = orignames_for_dir($dir);
    my @files = ();

    find (sub {push @files, $File::Find::name; }, $dir); 

    unless (@orignames > 0) {
        carp "No orignames for: $dir";
        return undef;
    }
    unless(@files > 0) {
        carp "No files in: $dir";
        return undef;
    }

    my $origname = $orignames[0];

    my $tar = Archive::Tar->new;
    $tar->add_files (@files);
    my $ioh=undef;
    foreach ( $origname ) {
        if (/.*\.gz$/) {
            $tar->write($origname, COMPRESS_GZIP) or do
            {
                carp "Can't write tar: $origname";
                return undef;
            };
        }
        elsif (/.*\.xz$/) {
            $ioh = IO::Zlib->new($origname, "rb");
            $tar->write($ioh) or do
            {
                carp "Can't write tar with zlib format; $origname";
                return undef;
            };
        }
        else {
            carp "Bad origname: $origname";
            return undef;
        }
    };

    1;
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
