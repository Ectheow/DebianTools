package Debian::BinaryPackage;


sub new {
    my ($class, %opts) = @_;

    my $data = {
        control_fields => $opts{control},
        @_,
    };


    my $self = bless $data, $class;
    $self->init()
        or do {
        carp "Can't Initialize binary package";
        return undef;
    };

    return $self;
}


sub init {
}


sub name {
}

sub version {
}
