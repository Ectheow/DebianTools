package Debian::SourcePackage::Error;
use Moose;
extends 'Throwable::Error';


package Debian::SourcePackage;
use Carp;
use autodie;
use Cwd;
use Dpkg::Changelog::Debian;
use Dpkg::Arch qw[get_host_arch get_build_arch];
use Dpkg::Control;
use Debian::ChangelogEntry;
use Debian::ControlFile;
use Debian::Util;
use strict;
use warnings;
use Archive::Tar;
use File::Basename;
use Util::Dirstack;
use File::Find;
use Switch;
use IO::Compress::Xz;
use IO::Zlib;
use File::Spec;
use v5.20;
use Moose;

=head

A debian source package represents, well, a debian source package. A source
package is a tricky object in that it may be represented fully by

    1. A source directory and nothing else.
    2. An orig tarball and a .debian.tar.xz or other source package debianization archive.
    3. Just an orig tarball.

It may also have associated build artifacts which provide helpful information
about state.

You should be able to point this object at any build artifact or primary source
object, and to the following:
    
    1. Do a source build
    2. Do a source extraction.
    3. Edit any control information and commit it by a source build.
    4. Get descriptions of any control information in various formats - 
       
You should be able to do this from anywhere on the filesystem and not worry
about your current directory being mucked by the methods you call, although
they may themselves change directories.

=cut



has 'debian_version' => (
    is => 'ro',
    isa => 'Str',
    writer => '_debian_version'
);

has 'upstream_version' => (
    is => 'ro',
    isa => 'Str',
    writer => '_upstream_version'
);

has 'name' => (
    is => 'ro',
    isa => 'Str',
    writer => '_name'
);

has 'containing_dir' => (
    is => 'ro',
    isa => 'Str',
    writer => '_containing_dir'
);



=head1

Construction

You should be able to construct a source package from a variety of source or
build artifacts.  You should be able to construct an object from a path
pointing to any of the following:

    1. Orig tarball
    2. Source directory without a tarball
    3. dsc file
    4. changes file

These are organized in least-to-greatest order in terms of how far along the
packages is in it's build process/debianization. Here is the behaviour:

    1. Orig tarball
        1. Test to see if the corresponding source dir, dsc file, or changes file exist.
            Die if so.
        2. Unconditionally extract the orig tarball.
        3. Read information about name/versioning etc. from the source dir
        4. On success, return. If normal debian dirs don't exist, die.
    2. Source directory
        1. Read information about name/versioning etc. from the source dir. 
           On failure, die.
        2. Check for an orig tarball. If it doesn't exist, and we have in the 
           options kw hash the value CREATE_ORIG=>1, create it. Otherwise, die.
        3. try to build the source with dpkg-source -b. Die on failure.
    3. DSC file
        1. Read the name/versioning info from the DSC file.
        2. Check for the orig tarball that the DSC file describes. Die if it doesn't exist.
        3. Check for the debian tarball _or_ the source dir the DSC describes. Die if it doesn't exist.
    4 Changes file
        1. Same as DSC file. Don't check for binary artifacts.

=cut

sub BUILDARGS
{
    my $class = shift;
    my %args = (
            orig_tarball=>undef,
            source_directory=>undef,
            dsc_file => undef,
            changes_file => undef,
            opts => undef,
            @_);

    my $self = {};
    my $opts = $args{opts} // {};
    if (defined $args{orig_tarball}) {
        return init_from_orig($self, $args{orig_tarball}, $opts);
    }
    elsif(defined $args{source_directory}) {
        return init_from_source_dir($self, $args{source_directory}, $opts);
    }
    elsif(defined $args{dsc_file}) {
        return init_from_dsc_file($self, $args{dsc_file}, $opts);
    }
    elsif(defined $args{changes_file}) {
        return init_from_changes_file($self, $args{changes_file}, $opts);
    }
    else {
        Debian::SourcePackage::Error->throw({
                message=>"No relevant build artifacts passed for construction"});
    }

}

sub init_from_orig($$$)
{
    my ($self, $tarball, $opts) = @_;

    Debian::SourcePackage::Error->throw({message => "Tarball: $tarball doesn't exist"}) 
        if not -f $tarball;


    my $d = Util::Dirstack->new;

    $d->pushd(dirname $tarball);
    my $dname = Debian::Util::dirname_for_orig(basename $tarball);

    Debian::SourcePackage::Error->throw({message => "source directory: $dname for tarball: $tarball already exists"})
        if -d $dname;

    (my @files = Archive::Tar->extract_archive(basename $tarball))
        or Debian::SourcePackage::Error->throw({
            message=>"Can't extract: $tarball"});




    Debian::SourcePackage::Error->throw({
            message=> "debian/ directory doesn't exist in extracted source: " . $dname})
        if not -d $dname . "/debian"; 

    my $v_h = read_version_from_changelog(changelog_filename => $dname . "/debian/changelog");

    $self->{$_} = $v_h->{$_} foreach keys %{$v_h};

    return $self;
}

sub init_from_source_dir($$$)
{
    my ($self, $dirname, $opts) = @_;

    Debian::SourcePackage::Error->throw({
            message=>"Source directory $dirname doesn't exist"})
        if not -d $dirname;

    Debian::SourcePackage::Error->throw({
            message=>"Orig tarball for $dirname doesn't exist, and no create option specified"})
        if ( (not grep { -f $_ } (Debian::Util::orignames_for_dir($dirname))) 
                or 
              (not (exists($opts->{create_orig}) and $opts->{create_orig} == 1)));


    if (not grep { -f $_} Debian::Util::orignames_for_dir($dirname) and $opts->{create_orig} == 1) {
        # make the source orig tarball.
        Debian::Util::create_orig_tarball_for_dir($dirname)
            or Debian::SourcePackage::Error->throw({
                message => "Orig tarball couldn't be created succesfully for $dirname"});
    }

    my $v_h = read_version_from_changelog(changelog_filename => $dirname . "/debian/changelog");

    $self->{$_} = $v_h->{$_} foreach (keys %{$v_h});

    return $self;
}

sub init_from_dsc_file($$$)
{
}

sub init_from_changes_file($$$)
{
}

sub read_version_from_changelog(%) {
    my (%opts) = @_;

    my $changelog = Dpkg::Changelog::Debian->new;

    Debian::SourcePackage::Error->throw({
            message=> "Not given a changelog kw argument"})
        if not exists $opts{changelog_filename};
    Debian::SourcePackage::Error->throw({
            message=>"Changelog file: " . $opts{changelog_filename} . "Doesn't exist"})
        if not -f $opts{changelog_filename};
    $changelog->load($opts{changelog_filename});


    my $top_entry = $changelog->[0];

    my $top_line = (split "\n", $top_entry)[0];

    my ($name, $upstream_version, $debian_version, $distribution) = 
        ($top_line =~ m/
            ^([\S]+)
            \s+
            \(
                ([\w\:\d\.]+)
                \-
                ([\w\+\d\-]+)
            \)
            \s+
            ([\w\d]+)
            \;
            \s+
            [\w\d\=]+
            \s*
            $
            /xi);

         
    my $h = {
        upstream_version=>$upstream_version, 
        debian_version=>$debian_version, 
        distribution=>$distribution,
        name=>$name
    };

    while(my ($k, $v) = each %{$h}) {
        Debian::SourcePackage::Error->throw({
                message=>"Undefined value for key: $k while parsing debian changelog"})
            if not defined $v;
    }

    return $h;
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

    $tar->read($source_orig)
        or do {
        carp "Can't read orig tarball: $source_orig";
        return undef;
    };

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

    if (defined $self->{dir} and -d $self->{dir}) {
        return $self->{dir};
    }

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

    my $root = $self->name
    . "_"
    . $self->upstream_version
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
sub get_artifact_name 
{
    my $self = shift;

    my %args = (
        suffix=>undef,
        @_,
    );

    if($args{suffix} eq ".dsc") 
    {
        return $self->name()
            . "_"
            . $self->upstream_version()
            . "-"
            . $self->debian_version()
            . ".dsc";
    } 
    elsif($args{suffix} eq ".changes") 
    {
        my $buildarch = Dpkg::Arch::get_build_arch();
        return $self->name
            . "_"
            . $self->version()
            . "_"
            . $buildarch
            . ".changes";
    } 
    elsif($args{suffix} eq ".deb") 
    {
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
    
    my $cntrl = Debian::ControlFile->new(control_filename=>$control_filename, parent_source=>$self) or do{
        carp "Can't parse control file";
        return undef;
    };

    return $cntrl;

}

sub set_watch {

    my ($self, %opts) = @_;

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



=item $successs = $p->override_lintian(package=>"example-package",
                                       tag=>"example-error-tag");
    
Override a single lintian error in the debian/ directory for the tag.
Returns "overridden" if the tag was overridden. Returns
"already-overridden" if the tag was already overridden. Returns undef on
error. Doesn't append another tag if it's already there.

TODO: eliminate binary dependency. 

=cut
sub override_lintian 
{
    my ($self, %opts) = @_;

    $self->__get_debian_file("source");

    return undef if not defined $opts{package};
    return undef if not defined $opts{tag};
    my $count = 0;

    my $fname = $self->__get_debian_file($opts{package} . ".lintian-overrides");
    my @lines = ();
    if (-f $fname) 
    {
        @lines = do 
        {
            open my $fh, "<", $fname;
            <$fh>;
        };

        map { chomp $_; } @lines;
    }

    return "already-overridden" if grep { $_ eq $opts{tag} } @lines;

    open my $fh, ">>", $fname
        or do 
    {
        carp "can't open filehandle for lintian override $!";
        return undef;
    };

    say $fh $opts{tag};

    close $fh;
    return "overridden";
}

=item $artifact_list = $p->binary_artifacts();

Get a list of binary artifacts that would be produced by building the package on
this machine. This uses the build architecture of the machine running as the
architecture postfix.

=cut
sub binary_artifacts 
{
    my ($self, @args) = @_;
    my $file_strings = [];

    if (scalar @args) 
    {
        carp "Can't set binary_artifacts";
        return undef;
    }

    my $changes_file = $self->get_artifact_name(suffix=>'.changes')
        or do
    {
        carp "A changes file is required.";
        return undef;
    };

    my $ctrl = $self->get_control_file(); 

    
    my $packages = $ctrl->packages(); 

    my $changes =  Dpkg::Control->new(type=>CTRL_FILE_CHANGES);
    $changes->load($changes_file)
        or do 
    {
        carp "Couldn't load changes file";
        return undef;
    };

    my @files = grep { if (/.*\.deb$/) { $_; } else {undef;} } 
                    map { (split /\s+/)[4]; } 
                        grep { $_ ? $_ : undef; }
                            split '\n', $changes->{Files};
    return undef if not scalar @files;
    return [@files];
}

sub binary_packages 
{
    my ($self, $args) = @_;

    my $ctrl = $self->get_control_file
        or do 
    {
        carp "can't get control file";
        return undef;
    };

    return $ctrl->packages;
}

sub build_depends 
{
    my ($self, $args) = @_;

    my $ctrl = $self->get_control_file
        or do 
    {
        carp "Can't get control file";
        return undef;
    };

    my $depends_names = [split /\s*,\s*/, $ctrl->source_control->{"Build-Depends"}];

    if (not scalar @{$depends_names}) {
        carp "Warning: Returning no build-depends: " . $self->name;
        return undef;
    }

    return $depends_names;
}

=back
=cut
1;
