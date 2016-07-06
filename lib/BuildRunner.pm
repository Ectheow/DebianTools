package BuildRunner::Error;
use Moose;
extends 'Throwable::Error';


package BuildRunner;
use v5.20;
use Data::Dumper;
use IPC::Cmd qw[can_run];
use Fcntl qw[:DEFAULT];
use POSIX ();
use IPC::Open3;
use Term::ANSIColor qw[:constants];
use Moose;
use constant {
ERROR => 1,
WARN => 2,
VERBOSE=> 3,
};

use constant {
    AUTOMAKE => "automake",
    MAKE => "make",
    DEBIAN => "debian",
};

=head

BuildRunner is a package for running a build of something w/ Makefile or
pbuilder chroot etc.  w/o clogging up your screen. 

$b = BuildRunner->new

$b->run(builder=>"make", build_options=>"-j", opts=>{progress => 1, throw_error => 1});

=cut

our $Timeout = 0.001;
our $Bufferlen = 10;

has 'output_level' => (
    is => 'ro',
    isa => 'Int',
    writer => '_write_output_level',
);

has 'log_file' => (
    is => 'ro',
    isa => 'FileHandle',
    writer => '_write_log_file',
);

has 'filter' => (
    is => 'rw',
    isa => 'BuildFilter',
);

sub open_log_file
{
    my ($self, $fname) = @_;
    open my $fh, ">", $fname
        or BuildRunner::Error->throw({
            message => "Error with opening log $fname"});
    1;
}

sub builder_init
{
    my ($self, $pkg) = @_;

    $self->filter($pkg->new());
}

sub get_build_cmd
{
}

sub log_init 
{
    my ($self, $opts) = @_;

    $self->_write_output_level($opts->{output_level}) 
        if(exists $opts->{output_level});

    $self->open_log_file($opts->{log_file})
        if(exists $opts->{log_file});
}

sub pr_err
{
    my ($self, @strs) = @_;
    print RED;
    print "E: ", @strs;
    if (not $strs[$#strs-1] =~ /\n/) {
        print "\n";
    }
    print RESET;
    1;
}

sub pr_verbose
{
    my ($self, @strs) = @_;
    return 1 if ($self->output_level < VERBOSE);
    print @strs;
    1;
}

sub pr_warn
{
    my ($self, @strs) = @_;
    return 1 if($self->output_level < WARN);
    print YELLOW;
    print "W: ", @strs;
    print RESET;
    1;
}

sub run
{
    my ($self, %opts) = @_;

    my ($builder, $build_opts, $opts_h) = 
    (
        $opts{builder},
        $opts{build_options},
        $opts{opts}
    );

    $self->builder_init($opts{builder});
    $self->log_init($opts_h);

    my $build_cmd = can_run($builder)
        or BuildRunner::Error->throw({
            message => "Can't run $builder"});

    $build_cmd .= " " . $build_opts
        if defined $build_opts;

    my ($out, $err);

    my $pid = open3(undef, $out, $err, $build_cmd);
    my $select = IO::Select->new;

    my @fhs = ();
    for my $fh ($out, $err) {
        next if not defined $fh;
        $select->add($fh);
        push @fhs, [$fh, ""]; 
    }

    my @can_read = ();
    my $has_exited = 0;
    my $exit_code = undef;
    while( (not $has_exited) or ((@can_read = $select->can_read($Timeout)) > 0) ) {
        if (@can_read) {
            my $nread = 0;
            foreach my $fh (@can_read) {
                my @fh_ent = grep { $_->[0] eq $fh } @fhs;
                my $offset = length($fh_ent[0]->[1]);
                # $offset = -1 if($offset);
                if(($nread = sysread($fh, $fh_ent[0]->[1], $Bufferlen, $offset)) > 0) {
                    my ($level, $line) = $self->filter->filter_line($fh_ent[0]->[1]);
                    if ($level == WARN) {
                        $self->pr_warn($line);
                    } 
                    elsif($level == ERROR) {
                        $self->pr_err($line);
                    } 
                    else($level == VERBOSE) {
                        $self->pr_verbose($line);
                    }
               } elsif ($nread == 0) {
                    $select->remove($fh);
                }
            } 
            @can_read  = ();
        }
        $has_exited = ((waitpid($pid, POSIX::WNOHANG) > 0) || $has_exited);
        if($has_exited and not defined $exit_code) {
            $exit_code = $? >> 8;
        }
    }

    if ($exit_code != 0) {
        $self->pr_err("Failure: exit code: " . $exit_code);
        return undef;
    }

    1
}

1;
