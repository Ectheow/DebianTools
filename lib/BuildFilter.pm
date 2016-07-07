package BuildFilter;
use v5.20;
use Carp;
use strict;
use warnings;
use Moose::Role;


has 'build_binary_sequence' => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub {[]},
    writer => '_write_build_binary_sequence',
);

has 'cmdline' => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
    default => sub {[]},
);


requires 'filter_line';
requires 'next_build_command';
requires 'will_run';

1;
