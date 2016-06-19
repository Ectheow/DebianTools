use v5.20;
use strict;
use warnings;
use Debian::Util qw[
dirname_for_orig
pkgname_from_orig
orignames_for_dir
];
use Test::More tests=>2;


my $origname = "sample-package_1.0.orig.tar.gz";
my $dirname = "sample-package-1.0";


is_deeply ([(sort(orignames_for_dir($dirname)))], 
           [(sort qw[sample-package_1.0.orig.tar.gz sample-package_1.0.orig.tar.xz])], 
        "orignames worked out");
is (dirname_for_orig($origname), $dirname);


done_testing;
