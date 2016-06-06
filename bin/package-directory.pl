use Dpkg::Control;
use Archive::Tar;
use File::Basename;
use File::Spec;
use Carp;
use autodie;
use Cwd;
use Dpkg::Changelog::Debian;
use Debian::SourcePackage;
use strict;
use warnings;
use v5.22;

my $MAINTAINER = 'John Phillips <john.phillips5@hpe.com>';
my $ORIGIN = 'HPE';
my $REQUESTOR = 'Terry Rudd <terry.rudd@hpe.com>';
my $HPE_VERSION_ADD = "+hpelinux1";
my $CHANGELOG_MESSAGE = "Update changelog for inclusion in HPElinux cattleprod repo";
my $SOURCE_ORIGIN = "upstream";
my $REPO = "hpelinux";

my %control_fields = (
    Maintainer=>$MAINTAINER,
    Origin=>$ORIGIN,
    "XS-Source-Origin"=>$SOURCE_ORIGIN,
    "XS-Requestor"=> $REQUESTOR,
    "Vcs-Browser"=> "http://www.mellanox.com/page/products_dyn?product_family=26&mtag=linux_sw_drivers",
    "Vcs-Git" => "http://git.openfabrics.org/",
);

my %move_control_fields = (
    "Maintainer"=>"XSBC-Original-Maintainer",
);

sub edit_control {
    my %args = (
        pkg_obj=>undef,
        @_,
    );
    (my $cntrl = $args{pkg_obj}->get_control_file())
        or return undef;

    my $tp_control = $cntrl->source_control();
    foreach my $key (keys %{$tp_control}) {
        if (exists $move_control_fields{$key}) {
            $tp_control->{$move_control_fields{$key}} = 
                $tp_control->{$key};
        }
    }

    foreach my $key (keys %control_fields)  {

        $tp_control->{$key} = do {
            if (not defined $control_fields{$key}) {
                printf "Give a value for field '%s': >", $key;
                <STDIN>;
            } else {            
                $control_fields{$key};
            }
        };
    }

    $cntrl->save() or return undef;

    return 1; 
}

sub untar_archive {
    my %args = (
            orig_archive=>undef,
            @_,
    );

    unless(defined $args{orig_archive}) {
        croak "Need orig archive";
    } 

    my $tar = Archive::Tar->new();
    $tar->read($args{orig_archive});
    my @files = $tar->extract();
    if (scalar @files > 0)  {
        return $files[0]->name();
    } else {
        return undef;
    }
}

sub add_lintian_to_rules {
    my %args = (
        pkg_obj=>undef,
        @_,
    );

    my $binary = 0;
    my $dh_lintian = 0;
    if (not defined $args{pkg_obj}) {
        return undef;
    }

    open my $fh, "+<", $args{pkg_obj}->debian_dir_name() . "/rules" or do {
        carp "can't open debian/rules";
        return undef;
    };

    while(<$fh>) {
        if(/^binary\-arch:/) {
            $binary = 1;
        } elsif (/^\S/) {
            $binary = 0;
        }

        if ($binary and m/dh_lintian/) {
            say "Has dh_lintian";
            $dh_lintian = 1;
        }
    }

    if (not $dh_lintian) {
        say "No DH lintian";
    }
    return $dh_lintian;
}

sub edit_changelog {
    my %args = (
        pkg_obj=>undef,
        @_
    );
    my $entry = Debian::ChangelogEntry->new(
        package=>$args{pkg_obj},
        distribution=>"cattleprod",
        urgency=>"medium",
        changes=>["Update for HPELinux repo inclusion"],
        author=>$MAINTAINER,
        date=> undef);
    if (not defined $entry) {
        carp "Undefined entry for changelog, couldn't construct";
        return undef;
    }
#    chdir dirname($args{changelog_name} . "../" );
#
#    system("dch --newversion "
#        . $version . $HPE_VERSION_ADD
#        . " -D cattleprod "
#        . $CHANGELOG_MESSAGE) == 0
#        or croak "Can't edit changelog: $args{changelog_name} $!";
#
    #chdir $dir;
    #
    $args{pkg_obj}->append_changelog_entry(entry=>$entry) or do {
        carp "Can't append changelog entry";
        return undef;
    };

    return 1;
}

sub dput_changes {
    my %args = (
        changes_file=>undef,
        @_,
    );
    unless (-f $args{changes_file}) {
        carp "changes file DNE $args{changes_file}";
        return undef;
    }
    system("dput --force $REPO $args{changes_file}") == 0 
        or do {
        carp "Can't dput";
        return undef;
    };
}

sub build_source {
    my %args = (
        source_archive=>undef,
        version=>undef,
        @_,
    );
    
    my $dsc_filename = $args{source_archive};

    $dsc_filename =~ s/\_.*//;
    $dsc_filename .= "_" . $args{version} . ".dsc";
    
    unless(-f $dsc_filename) {
        carp "Can't open $dsc_filename";
        return undef;
    };
    system("sudo /usr/sbin/pbuilder --build --buildresult . --debbuildopts '-j -sa' $dsc_filename") == 0
        or do {
        carp "Can't run pbuilder";
        return undef;
    };

    return $dsc_filename =~ s/\.dsc/_amd64\.changes/r;
}


sub override_lintian {
    my %opts = (
        pkg_obj => undef,
        @_,
    );

    my $count=0;
    my $binary_arts = $opts{pkg_obj}->binary_artifacts();

    foreach my $artifact (@$binary_arts) {
        if (not (-f $artifact)) {
            carp "ARtifact: $artifact undefined";
            next;
        }

        open my $lintian, "-|", "lintian $artifact" or do {
            carp "can't run lintian for $artifact";
        };

        while(<$lintian>) {
            if(/^E.*$/) {
                my (undef, $package, $error) = split /:\s*/, $_;
                $error = (split /\s+/, $error)[0];
                $opts{pkg_obj}->override_lintian(
                    packages=>{$package=>[$error]}) > 0 or do {
                    return 0;
                };
                print "Overriding $error for $package\n" if /^E.*$/;
                ++$count;
            }
        }
    }

    $opts{pkg_obj}->source_build()
        or do {
        carp "Can't generate source artifacts";
        return undef;
    };

    return $count;
}

my $pkg_orig = shift;
my $source_dir=undef;
my $source_dsc = undef;
my $version = undef;
my $changes = undef;

chdir dirname $pkg_orig;
my $pkg = Debian::SourcePackage->new(orig_tar=>basename $pkg_orig);

sub make_control_edits {
    
    my %args = (
        pkg_obj=>undef,
        @_);

    $version = $pkg->debian_version() 
        or croak "Can't get debian version";
    $pkg->debian_version($version . $HPE_VERSION_ADD);
    $pkg->distribution("cattleprod");
    $pkg->set_watch(text=>"\n") 
        or croak "Can't set watch text";

    edit_control(pkg_obj=>$args{pkg_obj}) 
        or croak "Can't edit control file";

    edit_changelog(pkg_obj=>$args{pkg_obj})
        or croak "can't edit changelog";

    return 1;
}

sub main {

    my $pkg = shift;
    my $success = 0;
    while(not $success) {
        if (-f $pkg->get_artifact_name(suffix=>".dsc")) {
            $pkg->source_extract()
                or croak "Can't extract source";
        } else {
            $pkg->extract_all()
                or croak "Can't extract orig tarball";
            make_control_edits(pkg_obj=>$pkg);
        }

        wait_for_manual_edits() 
            or do {
            carp "Quitting";
            return 0;
        };
        $pkg->source_build()
            or croak "Can't build source";
        $pkg->build()
            or croak "Can't build binary package";

        if (override_lintian(pkg_obj=>$pkg) == 0) {
            $success = 1;
        }

    }
    
    return 1;
}

sub wait_for_manual_edits()
{
    print "> ";
    while(<STDIN>) {
        chomp;
        return 1 if /^continue$/;
        return 0 if /^quit$/;
    }
}

main($pkg) and $pkg->dput_to(server=>"hpelinux")
    or croak "Couldn't dput .changes file";
