package Debian::PbuilderPackageBuilder;
use IPC::Cmd qw[
can_run
run
run_forked];
use File::Path;
use IPC::Open3;
use v5.20;
use Debian::SourcePackageBuilder;
use File::Basename;
use Curses;
use Moose;
our $PBUILDER_PATH="/usr/sbin/pbuilder";

with 'Debian::SourcePackageBuilder';

has 'debbuildopts' => (
    is => 'rw',
    isa => 'Str',
    default => "'-j -sa'",
);

sub build {
    my ($self) = @_;

    if (not $self->source_package->source_built) {
        $self->source_package->build_source;
    }

    my $dsc_file = $self->source_package->calc_file_name(type=>"dsc");

    my $d = Util::Dirstack->new();

    $d->pushd(dirname $dsc_file);
    $dsc_file =  basename $dsc_file;

    (my $sudo_path = can_run("sudo")) or do
    {
        Debian::SourcePackageBuilder::Error->throw({
                message => "Cannot find the 'sudo' command!"});
    };

    Debian::SourcePackageBuilder::Error->throw({
            message => "pbuilder doesn't exist at $PBUILDER_PATH"})
        if not -x $PBUILDER_PATH;

    my $cmd = $sudo_path . " " . $PBUILDER_PATH
        . " build "
        . "--buildresult " . $self->build_output_directory() . " ";
    $cmd .=  "--debbuildopts " . $self->debbuildopts() . " " if $self->debbuildopts;
    $cmd .= " " . $dsc_file;
    
    my ($code, $pid, $fh_out, $fh_err);

    $pid = open3(undef, $fh_out, $fh_err, $cmd) or do 
    {    
        Debian::SourcePackageBuilder::Error->throw({
                message => "couldn't open pbuilder pipe: $!"});
    };

    my $screen = newterm(undef, *STDOUT, *STDIN);
    cbreak();
    noecho();

    my $COL_MAX = 20;

    my $start_bar = sub {
        print "[" . (" " x $COL_MAX) . "]";
        print ("\b" x ($COL_MAX+1));
    };

    print "\r\n";
    $start_bar->();
    my $col = 0;
    my $s  = IO::Select->new;

    foreach my $fh, ($fh_out, $fh_err) {
        my $flags = fcntl ($fh_out, F_GETFL, 0);
        $flags |= O_NONBLOCK;
        fcntl($fh_out, F_SETFL, $flags)
            or Debian::SourcePackage::Error->throw({
                message => "Can't set flags for filehandle in pbuilder";
            });
        $s->add($fh);
    }


    while(waitpid($pid, WNOHANG) <= 0) {
        my @ready_fh = $s->can_read($timeout);
        foreach my $fh (@ready_fh) {
            my $nread = 0;
            my $buf = "";
            if(($nread = sysread $fh, $buf, $length) <= 0) {
                next;
            }
            else {
                if($buf =~ m/
            }
        }
    }
    foreach my $fh ($fh_out, $fh_err) {
        while(my $line = <$fh>) {
            $col++;
            if ($col > $COL_MAX) {
                print "\r";
                $start_bar->();
            }
            if ($line =~ m/^E/ or $line =~ m/Error:/) {
                print ("\r\n\tpbuilder error:\r\n$line\r\n");
                $col = 0;
                $start_bar->();
            }
            print ".";
        }
        close $fh;
    }

    echo();
    nocbreak();
    delscreen($screen);

    waitpid($pid, 0);
    if($? >> 8 != 0){
        Debian::SourcePackageBuilder::Error->throw({
                message => "Couldn't build package: " . ($? >> 8)});
    }

    1
}

1
