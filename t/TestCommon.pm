package TestCommon;
use v5.20;
use strict;
use warnings;
use Carp;
use File::Path;
use Archive::Tar;
use File::Copy;
use File::Basename;
use Test::More;

BEGIN {
    require Exporter;
    our @ISA = qw(Exporter);
    our @EXPORT = qw[
    $SAMPLE_TARBALL_STORE
    $SAMPLE_TARBALL
    $SAMPLE_DSC_FILE
    $SAMPLE_DEBIAN_TAR
    $EXTRACTED_DIR
    $SAMPLE_SRC_DIR
    $UPSTREAM_VERSION
    $DEBIAN_VERSION
    $PKG_NAME
    extract_tar
    standard_cleanup];
};


our $SAMPLE_TARBALL_STORE = "t/data/sample-package_1.0.orig.tar.gz";
our $SAMPLE_TARBALL="t/sample-package_1.0.orig.tar.gz";
our $SAMPLE_DSC_FILE="t/sample-package_1.0-1.dsc";
our $SAMPLE_DEBIAN_TAR="t/sample-package_1.0-1.debian.tar.xz";
our $EXTRACTED_DIR ="t/sample-package-1.0";
our $SAMPLE_SRC_DIR=$EXTRACTED_DIR;
our $UPSTREAM_VERSION = "1.0";
our $DEBIAN_VERSION = "1";
our $PKG_NAME = "sample-package";

sub extract_tar {
    copy ($SAMPLE_TARBALL_STORE, $SAMPLE_TARBALL);

    chdir "t";
    Archive::Tar->extract_archive(basename $SAMPLE_TARBALL);
    chdir "..";
    ok ( (-d $SAMPLE_SRC_DIR), "Directory exists for test");

}

sub standard_cleanup {
    unlink $SAMPLE_DSC_FILE if -f $SAMPLE_DSC_FILE;
    unlink $SAMPLE_DEBIAN_TAR if -f $SAMPLE_DEBIAN_TAR;
    unlink $SAMPLE_TARBALL if -f $SAMPLE_TARBALL;
    rmtree $SAMPLE_SRC_DIR;
}


1;
