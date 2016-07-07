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
use BuildFilter;
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

our $Timeout = 0.01;
our $Bufferlen = 8192;

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

has 'builder_stack' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub{[]},
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
    my ($self, $pkg, $opts) = @_;
    require $pkg . ".pm";
    $self->filter($pkg->new(options => $opts));
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

    BuildRunner::Error->throw({
            message => "Undefined builder"})
        if not defined $builder;
    $self->builder_init($builder, $opts_h);
    $self->log_init($opts_h);

    while ((my $build_cmd = $self->get_next_build_command())) {
        $self->run_command($build_cmd) or do 
        {
            return undef;
        };
    }
    
    1
}
sub get_next_build_command {
    my ($self) = @_;

    my $builder = $self->builder_stack()->[0]

    if (blessed($builder)) {
        my $cmd = undef;
        BuildRunnner::Error->throw({
                message => "builder $builder is not a BuildRunner"});
        $cmd = $builder->next_build_command;
        if($cmd) {
            return $cmd;
        }
        else {
            pop @{$self->builder_stack};
            return $self->get_next_build_command;
        }
    }
    else {
        return pop @{$self->builder_stack};
    }
}

sub run_command {
    my ($self, $build_cmd) = @_;
    my ($out, $err);

    my $pid = open3(undef, $out, $err, $build_cmd);
    my $select = IO::Select->new;

    my @fhs = ();
    for my $fh ($out, $err) {
        next if not defined $fh;
        my $flags = fcntl ($fh, F_GETFL, 0);
        fcntl($fh, F_SETFL, $flags|O_NONBLOCK) or do 
        {
            BuildRunner::Error->throw({
                    message => "Can't set O_NONBLOCK for file descriptor"});
        };
        $select->add($fh);
        push @fhs, [$fh, ""]; 
    }

    my @can_read = ();
    my $has_exited = 0;
    my $exit_code = undef;
    while( ((@can_read = $select->can_read($Timeout)) > 0) or  (not $has_exited)) {
        if (@can_read) {
            my $nread = 0;
            foreach my $fh (@can_read) {
                my ($fh_ent) = grep { $_->[0] eq $fh } @fhs;
                my $offset = length($fh_ent->[1]);
                if(($nread = sysread($fh, $fh_ent->[1], $Bufferlen, $offset)) > 0) {
                    while((my $idx = index ($fh_ent->[1], "\n")) != -1) {
                        my $line_string = substr($fh_ent->[1], 0, $idx+1);
                        my ($line, $level) = $self->filter->filter_line($line_string);
                        if ($level == WARN) {
                            $self->pr_warn($line);
                        } 
                        elsif($level == ERROR) {
                            $self->pr_err($line);
                        } 
                        elsif($level == VERBOSE) {
                            $self->pr_verbose($line);
                        }
                        else {
                            BuildRunner::Error->throw({
                                    message => "Invalid level: $level"});
                        }
                        substr($fh_ent->[1], 0, $idx+1) = '';
                    }
                } 
                elsif ($nread == 0) {
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

    1;
}


1;
