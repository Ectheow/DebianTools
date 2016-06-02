use Dpkg::Control;
use Archive::Tar;
use File::Basename;
use File::Spec;
use Carp;
use autodie;
use Cwd;
use Dpkg::Changelog::Debian;
use Debian::Package;
use strict;
use warnings;
use v5.22;

my $MAINTAINER = 'John Phillips <john.phillips5@hpe.com>';
my $ORIGIN = 'HPE';
my $REQUESTOR = 'Terry Rudd <terry.rudd@hpe.com>';
my $HPE_VERSION_ADD = "+hpelinux1";
my $CHANGELOG_MESSAGE = "Update changelog for inclusion in HPElinux cattleprod repo";
my $SOURCE_ORIGIN = "Upstream";
my $REPO = "hpelinux";

my %control_fields = (
    Maintainer=>$MAINTAINER,
    Origin=>$ORIGIN,
    "XS-Source-Origin"=>$SOURCE_ORIGIN,
    "XS-Requestor"=> $REQUESTOR,
    "Vcs-Browser"=> " ",
    "Vcs-Git" => " ",
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
        $tp_control->{$key} = $control_fields{$key};
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

#sub generate_source_artifacts {
#    my %args = (
#        source_dir=>undef,
#        @_,
#    );
#
#    system("dpkg-source --build $args{source_dir}") == 0
#        or croak "Can't create build source artifacts";
#
#    return 1;
#}

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

sub save_debian {

}

sub extract_debian {
    my ($self, %opts) = @_;

    if ($self->get_)) {
    }
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
    $opts{pkg_obj}->extract_orig() 
        or do {
        carp "Can't extract orig";
        return undef;
    };

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

    $opts{pkg_obj}->save_source_orig() 
        or do {
        carp "can't save source orig";
        return undef;
    };
    $opts{pkg_obj}->generate_source_artifacts()
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
my $pkg = Debian::Package->new(orig_tar=>basename $pkg_orig);

$pkg->extract_orig() 
    or croak "Can't extract the orig tarball";
$pkg->extract_debian()
    or croak "Can't extract debian tarball";

$version = $pkg->debian_version() 
    or croak "Can't get debian version";
$pkg->debian_version($version . "+hpelinux0");
$pkg->distribution("cattleprod");
$pkg->set_watch(text=>"\n") 
    or croak "Can't set watch text";

edit_control(pkg_obj=>$pkg) 
    or croak "Can't edit control file";

edit_changelog(pkg_obj=>$pkg)
    or croak "can't edit changelog";

$pkg->save_debian()
    or croak "Can't save orig tarball";

$pkg->generate_source_artifacts()
    or croak "Can't generate source artifacts";
if (not -f $pkg->get_artifact_name(suffix=>".dsc")) {
    croak "dsc build artifact doesn't exist";
}

$pkg->build()
    or croak "Couldn't build";

while(override_lintian(pkg_obj=>$pkg) > 0) {
    $pkg->build() 
        or croak "Can't build package";
}

$pkg->dput_to(server=>"hpelinux")
    or croak "Couldn't dput .changes file";
