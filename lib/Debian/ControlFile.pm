package Debian::ControlFile;
use Carp;
use autodie;
use Cwd;
use Dpkg::Control;
use v5.22;

sub new {
    my ($class, %opts) = @_;

    my $self= undef;
    my $internal = {
        packages=>[],
        source_control=>undef,
        control_filename=>$opts{control_filename},
    };

    $self =  bless $internal, $class;

    $self->parse() or do {
        carp "Can't parse debian control info";
        return undef;
    };

    return $self;
}

sub parse {
    my ($self, %opts) = @_;

    my ($source_control, $packages) = ("", []);
    my $cur_control_para = "";
    my $parse_fh=undef;
    open my $fh, "<", $self->{control_filename} or do {
        carp "Can't open $self->{control_filename} for reading";
        return undef;
    };

    my $line = <$fh>;

     while(1) { 
        $source_control .= $line; 
        last if $line =~ /^\s*$/; 
    } continue {
        $line = <$fh>;
    }

    $self->{source_control} = Dpkg::Control->new(); 
    open $parse_fh, "<", \$source_control;
    $self->{source_control}->parse($parse_fh, "First paragraph of $self->{control_filename}") or do{
        carp "Can't parse source control info in first paragraph";
        return undef;
    };
    close $parse_fh;

    $line = <$fh>;
    while(1) {
        $cur_control_para .= $line if defined $line;

        if ($line =~ /^\s*$/ or (not defined $line)) {
            if ($cur_control_para =~ /\S/) {
                my $control_obj = Dpkg::Control->new();
                open $parse_fh, "<", \$cur_control_para;
                $control_obj->parse($parse_fh, "Package paragraph") or do {
                    carp "Can't parse a package paragraph in control file: $self->{control_filename}: $cur_control_para";
                    return undef;
                };
                print "parsed an extra paragraph\n";
                push @{$self->{packages}}, $control_obj;

                close $parse_fh;
            }

            if (not defined $line) {
                last;
            } else {
                $cur_control_para = "";
                $line = "";
            }
        }
    } continue {
        $line = <$fh>;
    }

    return 1;
}

sub packages {
    return $_[0]->{packages};
}

sub source_control {
    return $_[0]->{source_control};
}

sub save {
    my ($self, %opts) = @_;

    my $str_fh = undef;
    my $tmp_para = "";

    open my $fh, ">", $self->{control_filename} or do {
        carp "Can't open $self->{control_filename}";
        return undef;
    };

    open $str_fh, ">", \$tmp_para;
    $self->{source_control}->output($str_fh) or do{
        carp "can't save source control information";
        return undef;
    };

    say $fh $tmp_para;

    foreach my $para (@{$self->{packages}}) {
        $tmp_para ="";
        open $str_fh, ">", \$tmp_para;
        $para->output($str_fh) or do {
            carp "Can't save control paragraph";
            return undef;
        };
        close $str_fh;
        say $fh $tmp_para;
    }

    close $fh;

    return 1;
}
1;
