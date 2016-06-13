package Debian::ChangelogEntry;
use Carp;
use Cwd;
use Debian::SourcePackage;
use v5.22;

our $CHANGELOG_INDENT="  ";
our $CHANGELOG_AUTHOR_INDENT=" ";
sub new {
    my ($class, %opts) = @_;

    my $self = {
        package => $opts{package},
        distribution => $opts{distribution} // "cattleprod",
        urgency=> $opts{urgency} // "low",
        changes=> $opts{changes} // [],
        author => $opts{author},
        date=> $opts{date} // `date -R`,
    };

    chomp $self->{date};
    if (defined $self->{package} and not $self->{package}->isa("Debian::SourcePackage")) {
        carp "I need a debian package in the package paramenter";
        return undef;
    }
    return bless $self, $class;
}

sub generate_changelog_entry {
    my ($self, %opts) = @_;

    unless(defined $opts{filehandle}) {
        carp "Undefined filehandle";
        return undef;
    };


    my $fh = $opts{filehandle};

    say $fh $self->{package}->name() . " (" . $self->{package}->version() . ") "
            . ($self->{distribution} // $self->{package}->distribution()) . "; urgency=" . $self->{urgency};

    foreach my $entry (@{$self->{changes}}) {
        print $fh "\n";
        say $fh $CHANGELOG_INDENT . "* " . $entry;
    }

    print $fh "\n";

    say $fh $CHANGELOG_AUTHOR_INDENT . "-- " . $self->{author} . "  " . $self->{date};
    print $fh "\n";

}

1;
