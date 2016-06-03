package Debian::SourcePackage;
use Carp;
use autodie;
use Cwd;
use Dpkg::Changelog::Debian;
use Dpkg::Arch qw[get_host_arch get_build_arch];
use Debian::ChangelogEntry;
use Debian::ControlFile;
use strict;
use warnings;
use Archive::Tar;
use File::Basename;
use File::Find;
use Switch;
use IO::Compress::Xz;
use IO::Zlib;
use File::Spec;
use v5.22;

=head1

Package for manipulating a debian package's files.

=cut
sub new {
    my $class = shift;

    my $package_regex = qr{
    ([\w\d\-]+)
    _
    ([\w\d\.]+)
    \.orig.*
    }xi;
    my %args = (
        orig_tar=>undef,
        @_,
    );
    my $self = {
        package_name => undef,
        upstream_version => undef,
        debian_version => undef,
    };


    if (defined $args{orig_tar}) {
        $args{orig_tar} =~ m/$package_regex/;
        $self->{package_name} = $1;
        $self->{upstream_version} = $2;
    }

    return bless $self, $class;
}

=over 4
=item $changelog = $p->parse_changelog

Parses the changelog for the package. Requires that the orig_tar or a debian tar
archive exists. Returns a Dpkg::Changelog object.

=cut
sub parse_changelog {
    my ($self, %args) = @_;

    my $changelog = Dpkg::Changelog::Debian->new();

    $changelog->load($self->__checked_get_debian_file("changelog")) or do {
        carp "Can't load changelog file";
        return undef;
    };

    return $changelog;
}

sub read_version_from_changelog {
    my ($self, %opts) = @_;

    my $chng = $self->parse_changelog() or do {
        carp "can't read version";
        return undef;
    };

    my $top_entry = $chng->[0];

    ($self->{upstream_version}, $self->{debian_version}) = 
        split "-", $top_entry->get_version();

    return 1;
}


=item $result = $p->extract_orig();

Extracts the orig tarball.

=cut
sub extract_orig {
    my $self = shift;
    my $source_orig = $self->orig_tar_name();

    if (not -f $source_orig) {
        carp "No source orig: $source_orig";
        return undef;
    }

    my $tar = Archive::Tar->new();

    $tar->read($source_orig);

    my @files = $tar->extract();

    if (not scalar @files) {
        carp "Extracted no files from orig tarball";
        return undef;
    }
    return $files[0]->name();

}
sub source_extract {
    my $self = shift;

    my $dsc_file = $self->get_artifact_name(suffix=>".dsc")
        or do {
        carp "can't get dsc artifact";
        return undef;
    };

    system("dpkg-source -x $dsc_file") == 0 or do {
        carp "Can't extract $dsc_file";
        return undef;
    };

    return 1;
}

=item $result = $p->extract_all();

Extracts both the orig tarball and the debian tarball directory (if it exists).
Returns 1 on success, undef on failure. 

=cut
sub extract_all {
    my ($self, %opts) = @_;


    $self->extract_orig() or do {
        carp "Failure extracting orig archive";
        return undef;
    }; 
    $self->extract_debian() or do {
        carp "Failure while extracting debian archive";
        return undef;
    };
    return 1;
}

=item $result = $p->extract_debian();

Extracts the debian tarball into the correct directory. 1 on success, undef on
failure. If the debian directory doesn't exist this isn't counted as a failure.
It _is_ a failure if the orig doesn't already exist untarred.

=cut 
sub extract_debian {
    my ($self, %opts) = @_;
    
    my $source_orig = $self->orig_tar_name();
    my $debian_tar = $self->debian_tar_name();

    
    if (not -f $source_orig) {
        carp "The source orig: $source_orig should already exist, but it doesn't";
        return undef;
    }

    if (not defined $debian_tar or not -f $debian_tar) {
        say "The tarball: $debian_tar doesn't exist, which may be OK, so skipping...";
        return 1;
    }

    if (not -d $self->source_dir()) {
        say "The source dir for $debian_tar doesn't exist";
        return undef;
    }

    my $tar = Archive::Tar->new();

    $tar->read($debian_tar) or do {
        carp "Can't read debian archive: $debian_tar";
        return undef;
    };


    my @files = $tar->extract();

    if(not scalar @files) {
        carp "Extraction of debian archive $debian_tar failed";
        return undef;
    }

    return $files[0];
}

=item $result = $p->save_all();

Creates from the source directory the debian and orig tarballs, overwriting if
they exist.  Returns 1 on success, undef on failure.

=cut 
sub save_all {
}


=item $dirname = $p->source_dir()

Get name of the source directory that may or may not be extracted. If it isn't,
returns undef. Call extract_orig first.

=cut
sub source_dir {
    my ($self, %opts) = @_;

    my $source_orig = $self->orig_tar_name();

    if (not defined $source_orig) {
        carp "Can't find orig source tarball";
    }

    my $source_dirname =  (substr $source_orig, 0, index($source_orig, ".orig")) =~ tr/_/-/r;
    if (not (-d $source_dirname)) {
        carp "Source directory $source_dirname didn't exist.";
        return undef;
    }

    return $source_dirname;

}

sub save_tar {
    my ($self, %opts) = @_;
    my @files = ();

    my ($dir, $dest) = ($opts{directory}, $opts{destination});
    if (not defined $dir) {
        carp "Undefined file";
        return undef;
    }

    if (not defined $dest) {
        carp "Undefined destination for tar";
        return undef;
    }

    find(
        sub { push @files, $File::Find::name; }, 
        $dir);

    if (not scalar @files) {
        carp "No files in source directory";
        return undef;
    }

    {
        local $,="\n";
        say "Adding ", @files, " to archive";
    };

    my $tar = Archive::Tar->new();
    my $fh = undef;
    $tar->add_files(@files)
        or do {
        carp "Can't add files: " . @files;
        return undef;
    };

    switch ($self->orig_tar_name()) {
        case m/.*\.gz$/i { $fh = IO::Zlib->new($dest, "wb"); }
        case m/.*\.xz$/i { $fh = new IO::Compress::Xz $dest; }
        else { open $fh, ">", $dest; }
    };

    if(not defined $fh) {
        carp "Can't open filehandle to " . $dest . " for writing";
        return undef;
    }

    return scalar $tar->write($fh);
}

sub save_source_orig {
    my ($self, %opts) = @_;

    return $self->save_tar(directory=>$self->source_dir(), 
                           destination=>$self->orig_tar_name());
}

sub save_debian {
    my ($self, %opts) = @_;

    return $self->save_tar(directory=>$self->source_dir() . "/debian",
                           destination=>$self->debian_tar_name());
}

=item $is_ok = $p->source_build()

Dpkg-source builds the source directory.

=cut
sub source_build {
    my ($self, %opts) = @_;

    my $source_dir = $self->source_dir();

    if (not defined $source_dir) {
        carp "Can't find or generate orig source";
        return undef;
    }

    if (not -d $source_dir) {
        carp "Received a directory that DNE: $source_dir";
        return undef;
    }
    system("dpkg-source --build $source_dir") == 0 
        or do {
        carp "Can't build source directory $source_dir";
        return undef;
    };

    return 1;
}


=item $filename = $p->orig_tar_name()

Gets the filename for the orig tarball.

=cut 
sub orig_tar_name {
    my $self = shift;

    my $root = $self->{package_name}
    . "_"
    . $self->{upstream_version}
    . ".orig.tar";

    if (-f $root) {
        return $root;
    } elsif (-f $root . ".gz" ) {
        return $root . ".gz";
    } elsif(-f $root . ".xz") {
        return $root . ".xz";
    } else {
        carp "No defined file with root: $root found";
        return undef;
    }
}


sub debian_tar_name {
    my $self = shift;

    my @suffixes = (".debian.tar", ".diff");
    my @compressions = (".gz", ".xz");

    foreach my $suffix (@suffixes) {
        my $root = sprintf("%s_%s%s", $self->name(), $self->version(), $suffix);
        foreach my $compression (@compressions) {
            my $fname = $root . $compression;
            if (-f $fname) {
                return $fname;
            }
        }
    }

    return undef;
}


sub debian_dir_name {
    my $self = shift;

    return $self->source_dir(). "/debian";
}


sub __get_deb_names {
    my ($self, %opts) = @_;

    
}

=item $filename = $p->get_artifact_name(%opts)

Gets the artifact name according to opts.
    suffix => $suffix
        Suffix of build artifact file. Can be
        '.dsc' for example, or '.changes'.

=cut
sub get_artifact_name {
    my $self = shift;

    my %args = (
        suffix=>undef,
        @_,
    );


    if($args{suffix} eq ".dsc") {
        return $self->{package_name}
            . "_"
            . $self->{upstream_version}
            . "-"
            . $self->{debian_version}
            . ".dsc";
    } elsif($args{suffix} eq ".changes") {
        my $buildarch = Dpkg::Arch::get_build_arch();
        return $self->{package_name}
            . "_"
            . $self->version()
            . "_"
            . $buildarch
            . ".changes";
    } elsif($args{suffix} eq ".deb") {
        $self->__get_deb_names();
    }

    return undef;
}

sub __get_debian_file {
    my ($self, $name) = @_;

    return join "/", ($self->source_dir(), "debian", $name);

}

sub __checked_get_debian_file {
    my ($self, $name) = @_;

    my $fname = $self->__get_debian_file($name);

    unless(-f $fname) {
        carp "$fname doesn't exist";
        return undef;
    };
    return $fname;
}

sub get_control_file {
    my ($self, %opts) = @_;

    my $control_filename = $self->__checked_get_debian_file("control");
    unless(-f $control_filename) {
        carp "Debian control file DNE";
        return undef;
    }
    
    my $cntrl = Debian::ControlFile->new(control_filename=>$control_filename) or do{
        carp "Can't parse control file";
        return undef;
    };

    return $cntrl;

}

sub set_watch {

    my ($self, %opts) =@_;

    unless(defined $opts{text}) {
        carp "Undefined options text";
        return undef;
    }

    my $fname = $self->__get_debian_file("watch") or do {
        carp "Can't get filename for watch file";
        return undef;
    };

    open my $fh, ">", $fname or do {
        carp "Can't open filehandle for watch file";
    };

    print $fh $opts{text};
    close $fh;
    return 1;
}

sub load_changelog {
    my ($self, %opts) = @_;

    my $changelog = $self->parse_changelog() or do {
        carp "Can't parse changelog";
        return undef;
    };

    return $changelog;
}

sub append_changelog_entry {
    my ($self, %opts) = @_;

    my @save_lines = ();

    unless(defined $opts{entry} and $opts{entry}->isa("Debian::ChangelogEntry")) {
        carp "Undefined or bad changelog entry";
        return undef;
    };

    open my $fh, "<", $self->__checked_get_debian_file("changelog") or do {
        carp "Can't open debian changelog";
        return undef;
    };

    @save_lines = <$fh>;
    close $fh;

    open $fh, ">", $self->__checked_get_debian_file("changelog") or do {
        carp "can't write to debian changelog";
        return undef;
    };

    $opts{entry}->generate_changelog_entry(filehandle=>$fh) or do{
        carp "Can't write entry to debian changelog";
        return undef;
    };

    print $fh @save_lines;

    close $fh;

    return 1; 
}

sub build {
    my ($self, %opts) = @_;

    system("sudo /usr/sbin/pbuilder --build --debbuildopts '-j -sa' --buildresult . " . $self->get_artifact_name(suffix=>".dsc")) == 0 or do {
        carp "Couldn't run pbuilder, got a non-zero result.";
        return undef;
    };

    say "dsc; " . $self->get_artifact_name(suffix=>".dsc");
    system("dpkg-source -x " . $self->get_artifact_name(suffix=>".dsc")) == 0 or do {
        carp "Can't re-extract source";
        return undef;
    };

    return 1;
}

sub debian_version {
    my ($self, $arg) = @_;

    if (defined $arg) {
        $self->{debian_version} = $arg;
    }

    if (not defined $self->{debian_version}) {
        $self->read_version_from_changelog() or do {
            carp "Can't read version from changelog";
        };
    }

    return $self->{debian_version};
}

sub distribution {
    my ($self, $arg) = @_;

   if (defined $arg) {
       $self->{distribution} = $arg;
   } 

   return $self->{distribution};
}

sub version {
    my ($self, $arg) = @_;

    
    if (defined $arg) {
        my ($deb, $up) = split "-", $arg;
        $self->debian_version($deb);
        $self->upstream_version($up);
    }

    return join "-", ($self->{upstream_version}, $self->{debian_version});
}

sub name {
    my ($self, $arg) = @_;

    if (defined $arg) {
        carp "Tried to set name of package, isn't supported";
        return undef;
    }

    return $self->{package_name};
}

sub dput_to {
    my ($self, %opts) = @_;

    unless(-f $self->get_artifact_name(suffix=>".changes")) {
        carp ".changes file: "
            . $self->get_artifact_name(suffix=>".changes")
            . " doesn't exist. Did you build it?";
        return undef;
    };

    system("dput $opts{server} " . $self->get_artifact_name(suffix=>".changes")) == 0 or do {
        carp "Can't dput to $opts{server}";
        return undef;
    };

    return 1;
}

=item $successs = $p->override_lintian(packages=>{"libfoo"=>["lintian-one", "lintian-two"], "libfoo-dev"=>["lintian-six", "lintian-seven"]});
    
Override a set of lintian errors for a set of packages produced by this source
package. Edits the debian/source/lintian-overrides file to include these
overrides. Overrides are currently assumed to be binary.

TODO: eliminate binary dependency. 

=cut
sub override_lintian {
    my ($self, %opts) = @_;

    $self->__get_debian_file("source");

    return undef if not defined $opts{packages};
    return undef if not ref $opts{packages} eq 'HASH';

    my $count = 0;
    foreach my $package (keys %{$opts{packages}}) {
        open my $fh, ">>", $self->__get_debian_file($package . ".lintian-overrides") or do {
            carp "can't open filehandle for lintian override $!";
            return undef;
        };

        foreach my $override (@{$opts{packages}{$package}}) {
            say "Override: $override in ". $self->__get_debian_file($package . ".lintian-overrides");
            say $fh $override;
            ++$count;
        }
        close $fh;
    }
    return $count;
}

=item $artifact_list = $p->binary_artifacts();

Get a list of binary artifacts that would be produced by building the package on
this machine. This uses the build architecture of the machine running as the
architecture postfix.

=cut
sub binary_artifacts {
    my ($self, @args) = @_;
    my $file_strings = [];

    if (scalar @args) {
        carp "Can't set binary_artifacts";
        return undef;
    }

    my $ctrl = $self->get_control_file(); 
    my $packages = $ctrl->packages(); 

    foreach my $hash (@$packages) {
        push @$file_strings,
                $hash->{'Package'}
                . "_"
                . $self->version()
                . "_"
                . Dpkg::Arch::get_build_arch()
                . ".deb";
    }

    return $file_strings;
}

=back
=cut
1;
