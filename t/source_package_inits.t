use v5.20;
use strict;
use warnings;
use Test::More;
use Test::Exception tests => 3;
use Carp;
use Debian::SourcePackage;
use File::Path;
use Archive::Tar;
use File::Copy;
use File::Basename;

my $SAMPLE_TARBALL_STORE = "t/data/sample-package_1.0.orig.tar.gz";
my $SAMPLE_TARBALL="t/sample-package_1.0.orig.tar.gz";
my $SAMPLE_DSC_FILE="t/sample-package_1.0-1.dsc";
my $SAMPLE_DEBIAN_TAR="t/sample-package_1.0-1.debian.tar.xz";
my $EXTRACTED_DIR ="t/sample-package-1.0";
my $SAMPLE_SRC_DIR=$EXTRACTED_DIR;
my $UPSTREAM_VERSION = "1.0";
my $DEBIAN_VERSION = "1";
my $PKG_NAME = "sample-package";

my $BAD_DSC_FILE_BAD_FORMAT=<<EOF;
dowlekERA==dlelr
EOF

my $BAD_DSC_FILE_TEXT_NAME=<<EOF;
Format: 3.0 (quilt)
Source: bad-source-name
Version: 1.0-1
EOF

my $BAD_DSC_FILE_TEXT_VERSION=<<EOF;
Format: 3.0 (quilt)
Source: sample-package
Binary: binary-package
Version: 1.0-10-10
EOF

my $BAD_DSC_FILE_TEXT_FORMAT=<<EOF;
Format: 3.0 (cats)
Source: sample-package
Binary: binary-package
Version: 1.0-1
EOF

my @bad_file_texts = (
    [$BAD_DSC_FILE_TEXT_NAME, qr/Couldn't extract source for:/],
    [$BAD_DSC_FILE_TEXT_VERSION, qr/Bad version string:/],
    [$BAD_DSC_FILE_TEXT_FORMAT, qr/Unsupported source format:/],
    [$BAD_DSC_FILE_BAD_FORMAT, qr/Parse error for DSC file:/]
);

my $debian_source_package = undef;

subtest "init_from_orig" => sub {


    plan tests => 9;
    copy ($SAMPLE_TARBALL_STORE, $SAMPLE_TARBALL);

    throws_ok { Debian::SourcePackage->new(irrelevant=>"1"); } qr/No relevant build artifacts/, 'Caught no relevant build artifacts';
    my $tarname = "does_not_exist.orig.tar";
    throws_ok { Debian::SourcePackage->new(orig_tarball=>$tarname); } qr/Tarball:\s*\Q$tarname\E doesn't exist/, 'Caught exception for bad tar';

    lives_ok  { $debian_source_package = Debian::SourcePackage->new(orig_tarball=>$SAMPLE_TARBALL); } 'Created debian source package object';

    ok ( (-d $EXTRACTED_DIR), "Directory extraction works");
    cmp_ok ($debian_source_package->upstream_version, 'eq', $UPSTREAM_VERSION, "Upstream versions are the same");
    cmp_ok ($debian_source_package->debian_version, 'eq', $DEBIAN_VERSION, "Debian versions match");
    cmp_ok ($debian_source_package->name, 'eq', $PKG_NAME, "Names match");
    cmp_ok ($debian_source_package->files()->{orig_tarball}, 'eq', basename $SAMPLE_TARBALL);
    cmp_ok($debian_source_package->directory, 'eq', dirname $SAMPLE_TARBALL);


    rmtree($EXTRACTED_DIR);
    unlink $SAMPLE_TARBALL;
};

sub extract_tar {
    copy ($SAMPLE_TARBALL_STORE, $SAMPLE_TARBALL);

    chdir "t";
    Archive::Tar->extract_archive(basename $SAMPLE_TARBALL);
    chdir "..";

    ok ( (-d $SAMPLE_SRC_DIR), "Directory exists for test");

}

sub compare_version_info {
    cmp_ok ($debian_source_package->upstream_version, 'eq', $UPSTREAM_VERSION, "Upstream versions are the same");
    cmp_ok ($debian_source_package->debian_version, 'eq', $DEBIAN_VERSION, "Debian versions match");
    cmp_ok ($debian_source_package->name, 'eq', $PKG_NAME, "Names match");
}

subtest "init_from_dir" => sub {
    copy ($SAMPLE_TARBALL_STORE, $SAMPLE_TARBALL);

    plan tests => 10;

    extract_tar();
    unlink $SAMPLE_TARBALL;


    throws_ok { Debian::SourcePackage->new(source_directory=>"does_not_exist"); } qr/Source directory does_not_exist doesn't exist/i, 
        'Caught exception for non-existent dir';
    throws_ok { Debian::SourcePackage->new(source_directory=>$SAMPLE_SRC_DIR); } qr/Orig tarball for \Q$SAMPLE_SRC_DIR\E doesn't exist,.*/i,
        'Caught exception for source dir with no orig tarball';

    lives_ok { $debian_source_package = Debian::SourcePackage->new(source_directory=>$SAMPLE_SRC_DIR, opts=>{create_orig => 1}); }
        'Created source package object ok';

    cmp_ok ($debian_source_package->files()->{source_directory}, 'eq', basename $SAMPLE_SRC_DIR);
    cmp_ok ($debian_source_package->directory, 'eq', dirname $SAMPLE_SRC_DIR);

    cmp_ok ($debian_source_package->calc_file_name(type=>"source_directory"), 'eq', $SAMPLE_SRC_DIR);
    compare_version_info;
    rmtree $SAMPLE_SRC_DIR;

};

subtest "init_from_dsc" => sub {

    plan tests => (9 + @bad_file_texts);
    extract_tar();



    foreach my $text_entry (@bad_file_texts) {
        open my $fh, ">", $SAMPLE_DSC_FILE or do 
        {
            carp "Can't open: $SAMPLE_DSC_FILE for writing";
            fail();
            goto cleanup;
        };
        say $fh $text_entry->[0];
        close $fh;

        throws_ok { 
            Debian::SourcePackage->new(dsc_file => $SAMPLE_DSC_FILE);
        } $text_entry->[1], 
        'Caught exception for bad text entry ' . $text_entry->[0];
    }

    chdir "t";
    system("dpkg-source -b " . basename $SAMPLE_SRC_DIR) == 0 or do 
    {
        carp "Can't build source package: $SAMPLE_SRC_DIR";
        fail();
        chdir "..";
        goto cleanup;
    };
    chdir "..";

    throws_ok { Debian::SourcePackage->new(dsc_file => "does_not_exist"); } qr/DSC file does_not_exist doesn't exist/i,
        'Caught exception for non-existent DSC file';
    lives_ok { $debian_source_package = Debian::SourcePackage->new(dsc_file => $SAMPLE_DSC_FILE); }
        'Created source object OK';
    
    cmp_ok($debian_source_package->files()->{dsc_file}, 'eq', basename $SAMPLE_DSC_FILE);
    cmp_ok($debian_source_package->files()->{source_directory}, 'eq', basename $SAMPLE_SRC_DIR);
    cmp_ok($debian_source_package->calc_file_name(type=>"dsc"), 'eq',
            $SAMPLE_DSC_FILE);

    compare_version_info;

    cleanup:
    unlink $SAMPLE_DSC_FILE if -f $SAMPLE_DSC_FILE;
    unlink $SAMPLE_DEBIAN_TAR if -f $SAMPLE_DEBIAN_TAR;
    unlink $SAMPLE_TARBALL;
    rmtree $SAMPLE_SRC_DIR;
};

done_testing;


