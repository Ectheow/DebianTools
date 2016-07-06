use v5.20;
use strict;
use warnings;
use Test::More;
use Test::Exception tests => 1;
use Carp;
use Debian::SourcePackage;
use Debian::SourcePackageBuilder;
use Debian::PbuilderPackageBuilder;
use TestCommon;


my $spkg = undef;

subtest "build_sample_package" => sub {
    plan tests => 3;

    my $builder = undef;

    extract_tar();

    lives_ok {
        $spkg = Debian::SourcePackage->new(
            source_directory=>$SAMPLE_SRC_DIR); 
        } 'Created source package';

    lives_ok { 
        $builder = Debian::PbuilderPackageBuilder->new(
               build_output_directory => ".",
               source_package => $spkg); 
       }  'Created builder object';

    lives_ok {
        $builder->build;
    }
    'Built package';

   standard_cleanup();

};

done_testing();
