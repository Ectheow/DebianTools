package Debian::PackageBuilder;
use Debian::SourcePackage;
use BerkeleyDB::Hash;
use BerkeleyDB;
use File::Basename;
use Debian::Util qw[pkgname_from_orig dirname_for_orig];
use Carp;
use v5.20;

my $DONE='done';

=head1

Package for handling the repeated building, modification, and re-building if
packages in debian source format. Wraps a SourcePackage object and re-builds it,
and saves the state of the build. Give it a path to an orig tarball, and it will
save a file in that directory containing the state of the build, and try not to
re-do these parts.

=cut
sub new {
    my $class = shift;

    my $self = bless {
        dir => undef,
        name => undef,
        orig_tarball=>undef,
        @_,
    }, $class;

    $self->init() or do 
    {
        carp "Couldn't initialize the PackageBuilder.";
        return undef;
    };

    return $self;
}


sub init
{
    my $self = shift;

    my $pkgname = undef;
    my $dir = undef;

    if (defined $self->{dir} and defined $self->{name})
    {
        $pkgname = $self->{name};
        $dir = $self->{dir};
    }
    elsif(defined $self->{orig_tarball} and -f $self->{orig_tarball}) 
    {
        ($pkgname = pkgname_from_orig($self->{orig_tarball}))
            or do
        {
            carp "Undefined packagename";
            return undef;
        };
        $dir = dirname ($self->{orig_tarball});
    }
    else 
    {
        carp "Insufficient parameters for cunstruction of package";
        return undef;
    }

    %{$self->{state_hash}} = ();

    $self->{state_fname} = $dir
        . $pkgname
        . ".buildstate");

    my $flags = 0;
    $flags |= DB_CREATE if not -f $self->{state_fname};

    tie %{$self->{state_hash}}, 'BerkeleyDB::Hash', 
        -Filename => $self->{state_fname},
        -Flags => $flags or do 
    {
        carp "Couldn't tie hash to "
            . $self->{state_fname} 
            . " $!";
        return undef;
    };


     if($self->{state_hash}->{control} eq $DONE
             and $self->{state_hash}->{dsc_file})
     {
         if(not -f $self->{state_hash}->{dsc_file})
         {
             carp "DSC file defined in saved hash doesn't exist: "
                    . $self->{state_hash}->{dsc_file};
             return undef;
         }
         $self->{source_pkg} = Debian::SourcePackage->new(
             dsc_file=>$self->{state_hash}->{dsc_file})
             or do 
         {
             carp "Can't init hash from DSC file: "
                . $self->{state_hash}->{dsc_file};
            return undef;
         };
     }
     else
     {
         $self->{source_pkg} = Debian::SourcePackage->new(
             orig_tar=>$self->{orig_tarball})
             or do
         {
             carp "Can't create a new SourcePackage";
             return undef;
         };

    }
    
   1;
}


sub edit_control
{
    my ($self, %opts) = @_;

    if ($self->{state_hash}->{control} eq $DONE)
    {
        return 1;
    }

    my %control_fields_write = %{$opts{control_fields_write}};
    my %control_fields_move = %{$opts{control_fields_move}};
    my $spkg = $self->{source_pkg};
    

    (my $ctrl = $spkg->get_control_file())
        or do 
    {
        carp "Can't get control file from source package";
        return undef;
    };

    my $source_paragraph = $ctrl->source_control();

    foreach my $key (keys %{$source_paragraph})
    {
        if (exists $control_fields_move{$key})
        {
            $source_paragraph->{$control_fields_move{$key}}
                = $source_paragraph->{$key};
        }
    }

    foreach my $key (keys %control_fields_write)
    {
        $source_paragraph->{$key} = $control_fields_write{$key};
    }

    $ctrl->save
        or do
    {
        carp "Couldn't save control file";
        return undef;
    };
    $self->{state_hash}->{control} = $DONE;

    1;
}

sub add_changelog_entry
{
    my ($self, %opts) = @_;

    if ($self->{state_hash}->{changelog} eq $DONE)
    {
        return 1;
    }

    $self->{source_pkg}->append_changelog_entry(%opts)
        or do
    {
        carp "Can't append changelog entry";
        return undef;
    };

    $self->{state_hash}->{changelog} = $DONE;
    return 1;
}

sub add_watch
{
    my ($self, %opts) = @_;

    if ($self->{state_hash}->{watch} eq $DONE)
    {
        return 1;
    }

    (my $watch_text = $opts{watch_text})
        or do 
    {
        carp "Undefined watch text";
        return undef;
    };


    $self->{source_pkg}->set_watch(text=>$watch_text)
        or do
    {
        carp "Can't set watch text";
        return undef;
    };

    $self->{state_hash}->{watch} = $DONE;
    1;

}

=head $success = $pkg->override_lintian;

Overrides lintian errors found in lintian output, if they don't already appear
in override files. Returns "try-again", "all-clear" or "unoverridable-errors",
or undef on error.  The package must be in the built state.

unoverridable-errors is returned only when all other errors have been
overridden, that is, only when there are no other successfull overrides. 

try-again is returned when we added an override to the source pacakge, but the
package must be rebuilt and run through lintian again to see if it worked.

all-clear is returned when no errors are detected from lintian whatsoever.

=cut
sub override_lintian
{
    my ($self, %opts) = @_;

    my $count=0;
    my $binary_arts = $self->{source_pkg}->binary_artifacts();

    given($self->{state_hash}->{lintian})
    {
        when("unoverridable-errors")
        {
            carp "There are unoverridable-errors.";
            return undef;
        }
        when("all-clear")
        {
            return "all-clear";
        } 
    }

    my $result = undef;
    foreach my $artifact (@$binary_arts) 
    {
        if (not (-f $artifact)) 
        {
            carp "Artifact: $artifact undefined";
            next;
        }

        open my $lintian, "-|", "lintian $artifact" 
            or do 
        {
            carp "can't run lintian for $artifact";
        };

        while(<$lintian>) 
        {
            next if not m/^E.*$/;
            my (undef, $package, $error) = split /:\s*/, $_;
            $error = (split /\s+/, $error)[0];

            (my $error_result 
                = $self->{source_pkg}->override_lintian(
                    package=>$package,
                    tag=>$error)) or do 
            {
                carp "Can't override tag $error for $package";
                return undef;
            };

            given ($error_result)
            {
                when("overridden")
                {
                    $result =  "try-again";
                }
                when("already-overridden")
                {
                    $result //= "unoverridable-errors";
                }
                default 
                {
                    carp "Bad result: $error_result from override_lintian";
                    return undef;
                }
            };
        }
    }

    $result //= "all-clear";

    given ($result)
    {
        when("all-clear")
        {
            $self->{state_hash}->{lintian} = "all-clear";
        }
        when("unoverridable-errors")
        {
            $self->{state_hash}->{lintian} = "unoverridable-errors";
        }
        when("try-again")
        {
            $self->{state_hash}->{lintian} = "try-again";
        }
    }

    return ($result // "all-clear");
}

sub set_state
{
    my ($self, $state, $name) = @_;

    $state =~ m/(watch|changelog|control|success)/ or do
    {
        carp "Bad state key $state";
        return undef;
    };

    $name =~ m/(undef|done)/ or do
    {
        carp "Bad state value $name";
        return undef;
    };

    $self->{state_hash}->{$state} = $name;
    1;
}

sub build_all
{
    my $self = shift;

    $self->{source_pkg}->source_build
        or do
    {
        carp "Couldn't build source";
        return undef;
    };

    $self->{state_hash}->{dsc_file}
        = $self->{source_pkg}->get_artifact_name(suffix=>".dsc")
            or do
    {
        carp "Undefined dsc file";
        return undef;
    };

    $self->{source_pkg}->build
        or do
    {
        carp "Couldn't do source build";
        return undef;
    };

    $self->{state_hash}->{last_build} = time;
    1;
}

sub source_package
{
    return $_[0]->{source_pkg};
}

sub success
{
    $_[0]->{state_hash}->{success} = "1";
}
sub DESTROY
{
    untie %{$_[0]->{state_hash}};
}
