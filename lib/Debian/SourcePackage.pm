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
use TryCatch;
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

has 'directory' => (
    is => 'ro', 
    isa => 'Str',
    writer => '_write_directory'
);

has 'files' => (
    is => 'ro',
    isa => 'HashRef',
    writer => '_write_files' 
);

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

    my $self = { };
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

sub BUILD {
    my ($self) = @_;
    $self->normalize_filenames();
}

sub build_source($)
{
    my ($self) = @_;


}

sub extract_source($)
{
    my ($self) = @_;
}


sub normalize_filenames($)
{
    my ($self) = @_;

    
    my $dirname = undef;
    while(my ($k, $v) = (each %{$self->{files}})) {
        Debian::SourcePackage::Error->throw({
                message => "All artifacts don't have the same directory name"})
            if ((defined $dirname) and  (not dirname($v) eq $dirname) );
        $dirname = dirname $v;
        $self->{files}->{$k} = basename $v;
    }

    $self->_write_directory($dirname);
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
    $self->{files}->{orig_tarball} = $tarball;
    read_version_from_changelog($self, changelog_filename => $dname . "/debian/changelog");

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
                and
              (not (exists($opts->{create_orig}) and $opts->{create_orig} == 1)));


    if (not grep { -f $_} Debian::Util::orignames_for_dir($dirname) and $opts->{create_orig} == 1) {
        # make the source orig tarball.
        Debian::Util::create_orig_tarball_for_dir($dirname)
            or Debian::SourcePackage::Error->throw({
                message => "Orig tarball couldn't be created succesfully for $dirname"});
    }

    read_version_from_changelog($self, changelog_filename => $dirname . "/debian/changelog");

    $self->{files}->{source_directory} = $dirname;

    return $self;
}

sub init_from_dsc_file($$$)
{
    my ($self, $dsc_filename, $opts) = @_;

    Debian::SourcePackage::Error->throw({
            message => "DSC file $dsc_filename doesn't exist"})
        if not -f $dsc_filename;
    
    my $dsc_file = Dpkg::Control->new(type=>CTRL_PKG_SRC);

    try {
        $dsc_file->load($dsc_filename) or die "Can't parse dsc file";
    } 
    catch($description) {
        Debian::SourcePackage::Error->throw({
                message => "Parse error for DSC file: $dsc_filename: $description"});
    }

    Debian::SourcePackage::Error->throw({
            message => "Unsupported source format: " . ($dsc_file->{Format} // "undef") }) 
        if ((not exists($dsc_file->{Format})) or $dsc_file->{Format} !~ m/3\.0\s+\(quilt\)/);
    my @versions = split "-", $dsc_file->{Version};
    
    Debian::SourcePackage::Error->throw({
            message => "Bad version string: " . $dsc_file->{Version} . " found in: " . $dsc_filename})
        if not @versions == 2;

    my $dname = dirname($dsc_filename) . "/" . $dsc_file->{Source} . "-" . $versions[0];

    {
        my $dstack = Util::Dirstack->new;
        $dstack->pushd(dirname($dsc_filename));

        system("dpkg-source -x " . basename($dsc_filename)) == 0 or do {
            Debian::SourcePackage::Error->throw({
                    message => "Couldn't extract source for: $dname described by: $dsc_file"});
        };
    }

    $self->{files}->{dsc_file} = $dsc_filename;
    
    return init_from_source_dir($self, $dname, $opts);
}


sub generic_artifact_prefix($)
{
    my ($self) = @_;

    if (not (
            defined $self->directory() and
            defined $self->name() and
            defined $self->upstream_version() and
            defined $self->debian_version())) {
        Debian::SourcePackage::error->throw({
                message => "Some parameters required for artifact names are undefined"});
    }
    return $self->directory . "/" . $self->name . "_" . $self->upstream_version . "-" . $self->debian_version;
}

sub get_or_init_generic_artifact_name($$$)
{
    my ($self, $postfix_or_ixes, $key) = @_;
    my $n;
    my @postfixes = ();
    if (exists $self->files()->{$key}) {
        return $self->files()->{$key};
    }

    if(ref $postfix_or_ixes eq 'ARRAY') {
        @postfixes = @{$postfix_or_ixes};
    }
    else {
        @postfixes = ($postfix_or_ixes);
    }

    foreach my $postfix (@postfixes) {
        if (-e ($n = $self->generic_artifact_prefix . $postfix)) {
            $self->files()->{$key} = $n;
            return $n;
        }
    }

    Debian::SourcePackage::Error->throw({
            message => "calculated file(s): for " 
                . $self->generic_artifact_prefix()  
                . join(" ", @postfixes) 
                . " don't exist"});

}

sub calc_file_name($%) 
{
    my ($self, %opts) = @_;

    foreach($opts{type}) {
        if($_ eq "dsc") {
            return $self->get_or_init_generic_artifact_name(".dsc", "dsc");
        }
        elsif($_ eq "changes") {
            return $self->get_or_init_generic_artifact_name(".changes", "changes");
        }
        elsif($_ eq "orig_tarball") {
            return $self->get_or_init_generic_artifact_name([".orig.tar.gz", ".orig.tar.xz"], "orig_tarball");
        }
        elsif($_ eq "source_directory") {
            my $d = $self->directory() . "/" .  $self->name() . "-" . $self->upstream_version();
            Debian::SourcePackage::Error->throw({
                    message => "The source directory doesn't seem to exist!"})
                if not -d  $d;
            return $d;
        }
        else {
            Debian::SourcePackage::Error->throw({
                    message => "Bad type argument for calc_file_name: $_"});
        }
    }
    1
}

sub read_version_from_changelog($%) {
    my ($self, %opts) = @_;

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

    $self->{$_} = $h->{$_} foreach (keys %{$h});
    return $self;
}




sub __get_debian_file {
    my ($self, $name) = @_;

    return join "/", ($self->get_artifact_name(type=>"source_directory"), "debian", $name);
}

sub __checked_get_debian_file {
    my ($self, $name) = @_;

    my $fname = $self->__get_debian_file($name);

    Debian::SourcePackage::Error->throw({
            message => "$fname doesn't exist"}) if not -e $fname;
    return $fname;
}

sub open_control_file {

    my ($self, %opts) = @_;

    my $control_filename = $self->__checked_get_debian_file("control");

    my $cntrl = Debian::ControlFile->new(control_filename=>$control_filename, 
                                         parent_source=>$self) or do 
    {
        Debian::SourcePackage::Error->throw({
                message => "Unable to init control file: $control_filename"});
    };

    return $cntrl;

}

sub set_watch {

    my ($self, %opts) = @_;

    Debian::SourcePackage::Error->throw({
            message => "Undefined option argument 'text'"})
        if not exists $opts{text};

    my $fname = $self->__get_debian_file("watch") ;
    open my $fh, ">", $fname or do 
    {
        Debian::SourcePackage::Error->throw({
                message => "Can't open file: $!"});
    };

    print $fh $opts{text};
    close $fh;
    return 1;
}

sub open_changelog {
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
        Debian::SourcePackage::Error->throw{(
                message => "Uname to open $fname for appending: $!"});
    };

    say $fh $opts{tag};

    close $fh;
    return "overridden";
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
