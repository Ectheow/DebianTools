package Debian::Package;
use Carp;
use autodie;
use Cwd;
use Dpkg::Changelog::Debian;
use strict;
use warnings;
use Archive::Tar;
use File::Basename;
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


}

=item $dirname = $p->get_source_dir()
=cut
sub get_source_dir {
    my ($self, %opts) = @_;

    my $source_orig = $self->get_orig_name();

    if (not defined $source_orig) {
        carp "Can't find orig source tarball";
    }

    my $source_dirname = substr($source_orig, 0, index($source_orig, ".orig"));
    if (not (-d $source_dirname)) {
        say "Source directory didn't exist so creating it...";

        my $tar = Archive::Tar->new();

        $tar->read($source_orig);

        my @files = $tar->extract();

        if (not scalar @files) {
            carp "Extracted no files from orig tarball";
            return undef;
        }
        return $files[0]->name();
    } else {
        return $source_dirname;
    }

    return undef;
}
=item $is_ok = $p->generate_source_artifacts()

Generates source artifacts for the package, using dpkg-source.
Returns success = 1 or failure = undef.

=cut
sub generate_source_artifacts {
    my ($self, %opts) = @_;

    my $source_dir = $self->get_source_dir();

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

=item $result = $p->build()

Builds the package with pbuilder.

=cut
sub build {
}

=item $filename = $p->get_orig_name()

Gets the filename for the orig tarball.

=cut 
sub get_orig_name {
    my $self = shift;

    my $root = $self->{package_name}
    . "_"
    . $self->{upstream_version}
    . ".orig.tar";

    if (-f $root . ".gz" ) {
        return $root . ".gz";
    } elsif(-f $root . ".xz") {
        return $root . ".xz";
    } else {
        return undef;
    }
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
    } 
    return undef;
}

sub __checked_get_debian_file {
    my ($self, $name) = @_;

    my $name = join "/", ($self->get_source_dir(), "debian", $name);

    unless(-f $name) {
        carp "$name doesn't exist";
        return undef;
    };
    return $name;
}

sub get_control_file {
    my ($self, %opts) = @_;

    my $control_filename = join "/", ($self->get_source_dir(), "debian", "control");
    unless(-f $control_filename) {
        carp "Debian control file DNE";
        return undef;
    }
    
    my $cntrl = Dpkg::Control->new();

    $cntrl->load($control_filename) or do {
        carp "Control file: $control_filename DNE";
        return undef;
    };

    return $cntrl;

}

sub control_file_save {
    my ($self, %opts) = @_;
    my @save_lines = undef;

    unless (defined $opts{control_file_hash}) {
        carp "I need a control file hash";
        return undef;
    }

    unless($opts{control_file_hash}->isa("Dpkg::Control")) {
        carp "I need a dpkg control object";
        return undef;
    }

    open my $ctrl_fh, "<", $self->__checked_get_debian_file("control");

    while(<$ctrl_fh>) { chomp; last if $_ eq ""; }

    @save_lines = <$ctrl_fh>;


    close $ctrl_fh;

    $opts{control_file_hash}->save($self->__checked_get_debian_file("control"))
        or do {
        carp "Can't save control file hash";
        return undef;
    };

    open $ctrl_fh, ">>", $self->__checked_get_debian_file("control")
        or do {
        carp "Can't open control file";
        return undef;
    }

    print $ctrl_fh, @save_lines;

    close $ctrl_fh;

    return 1;
}

=back
=cut
1;
