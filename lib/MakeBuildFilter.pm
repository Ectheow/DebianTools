package MakeBuildFilter;
use BuildRunner;
use Moose;

with 'BuildFilter';
sub BUILDARGS {
    my $self = shift;

    $self->_write_build_command("make");
}

sub filter_line {
    my ($self, $line) = @_;

    if ($line =~ m/error:/) {
        return ($line, BuildRunner::ERROR);
    } 
    elsif ($line =~ m/warn/) {
        return ($line, BuildRunner::WARN);
    } 
    else {
        return ($line, BUildRunner::VERBOSE);
    }
}
