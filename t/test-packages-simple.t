use Debian::SourcePackage;
use Debian::BinaryPackage;
use Debian::Package;
use Test::More;
use strict;
use warnings;
use v5.2;

my $dp = Debian::Package->new;

ok($dp->name('openssh') eq 'openssh', 'set name');
ok($dp->upstream_version('7p1') eq '7p1', 'set upstream');
ok($dp->debian_version('2+deb8u1') eq '2+deb8u1', 'set debian');

ok($dp->version eq '7p1-2+deb8u1', 'total version');

my $dps = Debian::SourcePackage->new(
    upstream_version=>'16.04',
    name=>'dpdk',
    debian_version=>'+hpelinux0');
ok($dps->isa('Debian::Package'), 'inheritance worked out');
ok($dps->debian_version eq '+hpelinux0', 'debian version for source works: '. $dps->debian_version);
ok($dps->upstream_version eq '16.04', 'upstream version works');


my $dpb = Debian::BinaryPackage->new(
            parent_source=>$dps);
ok(defined $dpb, 'binary package defined');
ok($dpb->isa('Debian::Package'), 'inheritance works');
ok($dpb->version eq $dps->version, 'copy version info works');
ok($dpb->debian_version eq $dps->debian_version, 'debian version works');
ok($dpb->upstream_version eq $dps->upstream_version, 'upstream verisoning works');
ok($dpb->parent_source == $dps, 'parent version reference is correct');
done_testing;
