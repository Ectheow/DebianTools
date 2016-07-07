package AutomakeBuildFilter;
use BuildRunner;
use IPC::Cmd qw[can_run];
use Moose;

with 'BuildFilter';

has '_make_filter' => (
    is => 'rw',
    isa => 'MakeBuildFilter',
);

sub BUILD {
    my ($self) = @_;


    if (not -x "configure") {
        push @{$self->build_binary_sequence}, "autoreconf -i";
    }

    push @{$self->build_binary_sequence}, "./configure";
    push @{$self->build_binary_sequence}, MakeBuildFilter->new;
}

sub will_run {
    return (-e "./configure.ac" or -x "./configure");
}

sub filter_line {
    my ($self, $line) = @_;
    return ($line, BuildRunner::VERBOSE);
}

sub next_build_command {
    my ($self) = @_;
    if (@{$self->build_binary_sequence}) {
        return shift @{$self->build_binary_sequence};
    }
    return;
}

1;
