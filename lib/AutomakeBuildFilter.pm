package AutomakeBuildFilter;
use BuildRunner;
use MakeBuildFilter;
use IPC::Cmd qw[can_run];
use Moose;

with 'BuildFilter';

has '_make_filter' => (
    is => 'rw',
    isa => 'MakeBuildFilter',
);

sub BUILD {
    my ($self) = @_;

    if (not -x "./configure") {
        push @{$self->build_sequence}, "autoreconf -i";
    }
    push @{$self->build_sequence}, "./configure";
    push @{$self->build_sequence}, MakeBuildFilter->new;
    $self->_write_name("automake");

    1;
}

sub will_run {
    return (-e "./configure.ac" or -x "./configure");
}

sub filter_line {
    my ($self, $line) = @_;
    if ($line =~ m/error:/i) {
        return ($line, BuildRunner::ERROR);
    }
    elsif($line =~ m/warn(ing)?:/i) {
        return ($line, BuildRunner::WARN);
    }
    return ($line, BuildRunner::VERBOSE);
}

sub next_build_command {
    my ($self) = @_;
    if (@{$self->build_sequence}) {
        return shift @{$self->build_sequence};
    }
    return;
}

1;
