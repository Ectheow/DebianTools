package MakeBuildFilter;
use v5.20;
use strict;
use warnings;
use BuildRunner;
use IPC::Cmd qw[can_run];
use Moose;

with 'BuildFilter';

has 'options' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub {{}},
);

sub BUILD {
    my ($self) = @_;

    my $cmd = can_run("make");
    if (not $cmd) {
        BuildRunner::Error->throw({
                message => "Can't run 'make'"});
    }
    $cmd .= " " .  join " ", @{$self->options->{cmdline}}
        if defined $self->options and exists $self->options->{cmdline};
    $self->_write_build_binary_sequence([$cmd]);
}

sub will_run {
    my ($class) = @_;

    if (-f 'Makefile' or -f 'makefile') {
        return 1;
    }

    return;
}

sub filter_line {
    my ($self, $line) = @_;

    if ($line =~ m/error:/
        or $line =~ m/make:\s*\*\*\*\s+/) {
        return ($line, BuildRunner::ERROR);
    } 
    elsif ($line =~ m/warn/) {
        return ($line, BuildRunner::WARN);
    } 
    else {
        return ($line, BuildRunner::VERBOSE);
    }
    return;
}

sub next_build_command {
    my ($self) = @_;
    if (@{$self->build_binary_sequence}) {
        return shift @{$self->build_binary_sequence};
    }
    return;
};

1;
