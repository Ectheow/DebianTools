package BuildFilter;
use v5.20;
use Carp;
use strict;
use warnings;
use Moose::Role;


has 'build_sequence' => (
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {[]},
    writer => '_write_build_sequence',
);

has 'name' => (
    is => 'ro',
    isa => 'Str',
    default => '',
    writer => '_write_name',
);



requires 'filter_line';
requires 'next_build_command';
requires 'will_run';

1;
