package Log::Stash::Input::Freeswitch;
use Moose;
use ESL;
use AnyEvent;
use Scalar::Util qw/ weaken /;
use Try::Tiny qw/ try catch /;
use namespace::autoclean;

with qw/
    Log::Stash::Role::Input
/;

has host => (
    isa => 'Str',
    required => 1,
    is => 'ro',
);

has port => (
    isa => 'Int',
    required => 1,
    is => 'ro',
    default => 8201,
);

has secret => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has '_connection' => (
    isa => 'ESL::ESLconnection',
    lazy => 1,
    default => sub {
        my $self = shift;
        my $con = ESL::ESLconnection->new($self->host, $self->port, $self->secret);
        die("Could not connect to freeswitch on " . $self->host . ":" . $self->port);
        $con->events("plain", "all");
        return $con;
    },
    is => 'ro',
    clearer => '_clear_connection',
    handles => {
        _connection_fd => 'socketDescriptor',
    },
);

sub _try_rx {
    my $self = shift;
    my $con = $self->_connection;
    my $e = $con->recvEventTimed(0);

    if ($e) {
        my %data;
        my $h = $e->firstHeader();
        while ($h) {
            $data{$h} = $e->getHeader($h);
            $h = $e->nextHeader();
        }
        $self->output_to->consume(\%data);
        return 1;
    }
    return;
}

has _io_reader => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $weak_self = shift;
        weaken($weak_self);
        AE::io $weak_self->_connection_fd, 0,
            sub { my $more; do { $more = $weak_self->_try_rx } while ($more) };
    },
    clearer => '_clear_io_reader',
);

sub _terminate_connection {
    my $self = shift;
    $self->_clear_io_reader;
    $self->_clear_connection;

}

sub BUILD {
    my $self = shift;
    $self->_io_reader;
    $self->_zmq_timer;
}

1;

=head1 NAME

Log::Stash::Input::ZeroMQ - input logstash messages from ZeroMQ.

=head1 DESCRIPTION

=head1 SEE ALSO

=over

=item L<Log::Stash::ZeroMQ>

=item L<Log::Stash::Output::ZeroMQ>

=item L<Log::Stash>

=item L<ZeroMQ>

=item L<http://www.zeromq.org/>

=back

=head1 SPONSORSHIP

This module exists due to the wonderful people at Suretec Systems Ltd.
<http://www.suretecsystems.com/> who sponsored it's development for its
VoIP division called SureVoIP <http://www.surevoip.co.uk/> for use with
the SureVoIP API - 
<http://www.surevoip.co.uk/support/wiki/api_documentation>

=head1 AUTHOR, COPYRIGHT AND LICENSE

See L<Log::Stash>.

=cut

