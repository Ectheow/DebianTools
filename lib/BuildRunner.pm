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
our $WarningPrefix = "W: ";
our $ErrorPrefix = "E: ";

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
    writer => '_write_builder_stack',
);

has 'filter' => (
    is => 'ro',
    does => 'BuildFilter',
    writer => '_write_filter',
);

has 'colorize' => (
    is => 'rw',
    isa => 'Bool',
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
    $self->_write_builder_stack([$pkg->new(options => $opts)]);
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

sub pr 
{
    my ($self, $color, $prefix, @strs) = @_;

    print $color if $self->colorize and defined $color;
    print $prefix if defined $prefix;
    print @strs;
    if (index($strs[$#strs-1], "\n") == -1) {
        print "\n";
    }
    print RESET if $self->colorize;

}
sub pr_err
{
    my ($self, @strs) = @_;
    $self->pr(
        RED,
        $ErrorPrefix,
        @strs);
    1;
}

sub pr_verbose
{
    my ($self, @strs) = @_;
    return 1 if ($self->output_level < VERBOSE);
    $self->pr(
        undef,
        undef,
        @strs);
    1;
}

sub pr_success 
{
    my ($self, @strs) = @_;

    $self->pr(
        GREEN,
        undef,
        @strs);
    1;
}


sub pr_warn
{
    my ($self, @strs) = @_;
    return 1 if($self->output_level < WARN);
    $self->pr(
        YELLOW,
        $WarningPrefix,
        @strs);
    1;
}

sub run
{
    my ($self, %opts) = @_;

    my ($builder, $build_opts, $opts_h) = 
    (
        $opts{builder},
        $opts{build_options},
        $opts{opts},
    );

    BuildRunner::Error->throw({
            message => "Undefined builder"})
        if not defined $builder;

    $self->colorize($opts{colorize});
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

=head
    $s->get_next_build_command
returns an execable build command, the whole damn thing.

THere is a stack of build command objects since a build filter can
return to you another build filter, ex:

[ <autoreconf build filter>, <Configure build filter>, <Make build filter> ].

Then we take the 0th element, and:
1. ) If it is a string
    shift it off
    return that command (it will be executed)
2. ) If it is not a string
    assert that it is a BuildFIlter reference
    unshift it's command onto the queue by calling it's next_build_command method
        (this may be undef and willl be taken care of in (3))
    set the current filter object to this filter.
    call self again
3. ) If it is undef
    shift off the queue
    call self again.
(*bad*)

=cut

sub get_next_build_command {
    my ($self) = @_;

    if (not @{$self->builder_stack}) {
        return undef;
    }

    my $builder = $self->builder_stack()->[0];

    if (not(blessed($builder)) and (ref $builder eq '')) {
        return shift @{$self->builder_stack};
    }
    elsif(blessed($builder) and $builder->does('BuildFilter')) {
        my $cmd = $self->builder_stack->[0]->next_build_command();
        unshift @{$self->builder_stack}, $cmd;
        $self->_write_filter($builder);
        return $self->get_next_build_command;
    }
    elsif(not defined $builder) {
        shift @{$self->builder_stack};
        return $self->get_next_build_command;
    }
    else {
        BuildRunner::Error->throw({
                message => "Bad builder object or string: $builder"});
    }
    return;
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
    else {
        $self->pr_success("Build '" 
            . ($self->filter->name // '(undefined)') 
            . "' succeeded, code 0");
    }

    1;
}


1;
