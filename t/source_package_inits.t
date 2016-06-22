use v5.20;
use strict;
use warnings;
use Test::More;
use Test::Exception tests => 2;
use Debian::SourcePackage;
use File::Path;
use Archive::Tar;
use File::Copy;
use File::Basename;

my $SAMPLE_TARBALL_STORE = "t/data/sample-package_1.0.orig.tar.gz";
my $SAMPLE_TARBALL="t/sample-package_1.0.orig.tar.gz";
my $EXTRACTED_DIR ="t/sample-package-1.0";
my $SAMPLE_SRC_DIR=$EXTRACTED_DIR;
my $UPSTREAM_VERSION = "1.0";
my $DEBIAN_VERSION = "1";
my $PKG_NAME = "sample-package";
my $debian_source_package = undef;

subtest "init_from_orig" => sub {


    plan tests => 7;
    copy ($SAMPLE_TARBALL_STORE, $SAMPLE_TARBALL);

    throws_ok { Debian::SourcePackage->new(irrelevant=>"1"); } qr/No relevant build artifacts/, 'Caught no relevant build artifacts';
    my $tarname = "does_not_exist.orig.tar";
    throws_ok { Debian::SourcePackage->new(orig_tarball=>$tarname); } qr/Tarball:\s*\Q$tarname\E doesn't exist/, 'Caught exception for bad tar';

    lives_ok  { $debian_source_package = Debian::SourcePackage->new(orig_tarball=>$SAMPLE_TARBALL); } 'Created debian source package object';

    ok ( (-d $EXTRACTED_DIR), "Directory extraction works");
    cmp_ok ($debian_source_package->upstream_version, 'eq', $UPSTREAM_VERSION, "Upstream versions are the same");
    cmp_ok ($debian_source_package->debian_version, 'eq', $DEBIAN_VERSION, "Debian versions match");
    cmp_ok ($debian_source_package->name, 'eq', $PKG_NAME, "Names match");


    rmtree($EXTRACTED_DIR);
    unlink $SAMPLE_TARBALL;
};

subtest "init_from_dir" => sub {
    copy ($SAMPLE_TARBALL_STORE, $SAMPLE_TARBALL);

    plan tests => 7;
    chdir "t";
    Archive::Tar->extract_archive(basename $SAMPLE_TARBALL);
    chdir "..";

    ok ( (-d $SAMPLE_SRC_DIR), "Directory exists for test");
    unlink $SAMPLE_TARBALL;


    throws_ok { Debian::SourcePackage->new(source_directory=>"does_not_exist"); } qr/Source directory does_not_exist doesn't exist/i, 
        'Caught exception for non-existent dir';
    throws_ok { Debian::SourcePackage->new(source_directory=>$SAMPLE_SRC_DIR); } qr/Orig tarball for \Q$SAMPLE_SRC_DIR\E doesn't exist,.*/i,
        'Caught exception for source dir with no orig tarball';

    lives_ok { $debian_source_package = Debian::SourcePackage->new(source_directory=>$SAMPLE_SRC_DIR, opts=>{create_orig => 1}); }
        'Created source package object ok';

    cmp_ok ($debian_source_package->upstream_version, 'eq', $UPSTREAM_VERSION, "Upstream versions are the same");
    cmp_ok ($debian_source_package->debian_version, 'eq', $DEBIAN_VERSION, "Debian versions match");
    cmp_ok ($debian_source_package->name, 'eq', $PKG_NAME, "Names match");


    rmtree $SAMPLE_SRC_DIR;

};


done_testing;


