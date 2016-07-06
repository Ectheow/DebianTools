package Debian::SourcePackageBuilder::Error;
use Moose;
extends 'Throwable::Error';
no Moose;

package Debian::SourcePackageBuilder;
use Carp;
use autodie;
use v5.20;
use strict;
use warnings;
use Cwd;
use Moose::Role;


=head

A debian source package builder is an object that wraps a source package and
builds the binary pacakges for that package. This package is an interface.

=item Initialization

takes a source package object only.

=over 

=item setup

There are numerous ways to build a package, the most common and (imo) useful
being with pbuilder, so, initially, we will only support pbuilder but build the
object so that you may use other build methods later, when they get implemented.

=over
=item building

To build a source package do setup and run the build() method.

=over
=cut


has 'success' => (
    is => 'ro',
    isa => 'Bool',
    writer => '_write_success',
);

has 'did_run' => (
    is => 'ro',
    isa => 'Bool',
    writer => '_write_did_run',
);

has 'build_output_directory' => (
    is => 'rw',
    isa => 'Str',
);


has 'source_package' => (
    is => 'ro',
    isa => 'Debian::SourcePackage'
);


requires 'build';

1
