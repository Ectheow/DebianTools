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
my $HPE_VERSION_ADD = "+hpelinux0";
my $CHANGELOG_MESSAGE = "Update changelog for inclusion in HPElinux cattleprod repo";
my $SOURCE_ORIGIN = "Upstream";
my $REPO = "hpelinux";


my %control_fields = (
    Maintainer=>$MAINTAINER,
    Origin=>$ORIGIN,
    "XS-Source-Origin"=>$SOURCE_ORIGIN,
    "XS-Requestor"=> $REQUESTOR);

my %move_control_fields = (
    "Maintainer"=>"XSBC-Original-Maintainer",
);

sub edit_control {
    my %args = (
        control_filename=>undef,
        @_,
    );
    my @save_lines;
    unless(defined $args{control_filename}) {
        croak "Need a control filename to edit!";
    }

    open my $fh, "<", $args{control_filename};

    while(<$fh>) {chomp; last if /^$/; };
    push @save_lines, "\n";
    while(my $line = <$fh>) {
        push @save_lines, $line;
    }

    close $fh;

    my $cntrl = Dpkg::Control->new();

    $cntrl->load($args{control_filename})
        or croak "Can't load control file";

    foreach my $key (keys %{$cntrl}) {
        if (exists $move_control_fields{$key}) {
            $cntrl->{$move_control_fields{$key}} = 
                $cntrl->{$key};
        }
    }

    foreach my $key (keys %control_fields)  {
        $cntrl->{$key} = $control_fields{$key};
    }

    $cntrl->save($args{control_filename})
        or croak "can't save control file";

    open $fh, ">>", $args{control_filename};

    print $fh @save_lines;
    close $fh;

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
        changelog_name=>undef,
        @_
    );

    my $dir = getcwd;
    my $changelog = Dpkg::Changelog::Debian->new();

    $changelog->load($args{changelog_name})
        or croak "Can't load changelog";

    my $latest = $changelog->[0];
    my $version = $latest->get_version();

    chdir dirname($args{changelog_name} . "../" );

    system("dch --newversion "
        . $version . $HPE_VERSION_ADD
        . " -D cattleprod "
        . $CHANGELOG_MESSAGE) == 0
        or croak "Can't edit changelog: $args{changelog_name} $!";

    chdir $dir;
    return $version . $HPE_VERSION_ADD;
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

sub add_watch {
    my %args = (
        source_dir=>undef,
        @_,
    );

    open my $fh, ">", $args{source_dir} . "debian/watch";

    say $fh "";

    close $fh;
    return 1;
}

sub override_lintian {
}

my $pkg_orig = shift;
my $source_dir=undef;
my $source_dsc = undef;
my $version = undef;
my $changes = undef;

chdir dirname $pkg_orig;
my $pkg = Debian::Package->new(orig_tar=>basename $pkg_orig);


my $watch_fh = $pkg->get_watch();
add_watch(watch_filehandle=>$watch_fh)
    or croak "Couldn't edit watch file.";

($version = edit_changelog(changelog_name => (join "/", ($source_dir, "debian", "changelog"))))
    or croak "can't edit changelog";

# Get a control file object and edit it.
my $control_obj = $pkg->get_control_file()
    or croak "Control object not defined";
edit_control(control_object=>$control_obj)
    or croak "Control object editing failed";

$pkg->generate_source_artifacts()
    or croak "Can't generate source artifacts";
if (not -f $pkg->get_artifact_name(suffix=>".dsc")) {
    croak "dsc build artifact doesn't exist";
}

$pkg->build()
    or croak "Couldn't build";


$pkg->dput_to(server=>"hpelinux");
    or croak "Couldn't dput .changes file";

($changes = build_source(source_archive=>$pkg_orig,
             version=>$version))
    or croak "can't build source";
dput_changes(changes_file=>$changes) 
    or croak "Can't put changes file: $changes";
