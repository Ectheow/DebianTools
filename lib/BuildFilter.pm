package BuildFilter;
use v5.20;
use Carp;
use strict;
use warnings;
use Moose::Role;


has 'build_command' => (
    is => 'ro',
    isa => 'Str'
);

requires 'filter_line';
