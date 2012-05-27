package Log::Stash::Input::Freeswitch;
use Moose;
use AnyEvent;
use Scalar::Util qw/ weaken /;
use Try::Tiny qw/ try catch /;
use namespace::autoclean;

our $VERSION = '0.001';

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
    default => 8021,
);

has secret => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has connection_retry_timeout => (
    is => 'ro',
    isa => 'Int',
    default => 3,
);

has '_connection' => (
    isa => 'ESL::ESLconnection',
    lazy => 1,
    default => sub {
        my $self = shift;
        require ESL;
        # FIXME Retarded SWIG bindings want the port number as a string, not an int
        #       so we explicitly stringify it
        my $con = new ESL::ESLconnection($self->host, $self->port."", $self->secret);
        unless ($con) {
            warn("Could not connect to freeswitch on " . $self->host . ":" . $self->port);
            $self->_terminate_connection($self->connection_retry_timeout);
            $con = bless {}, 'ESL::ESLconnection';
        }
        $con->events("plain", "all");
        $con->connected() || do {
            $con->disconnect;
            $self->_terminate_connection($self->connection_retry_timeout);
        };
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
    if (!$con->connected) {
        $self->_terminate_connection;
        return;
    }
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
        my $fd =  $weak_self->_connection_fd;
        return unless $fd >= 0;
        AE::io $fd, 0,
            sub { my $more; do { $more = $weak_self->_try_rx } while ($more) };
    },
    clearer => '_clear_io_reader',
);

sub _terminate_connection {
    my ($self, $retry) = @_;
    $retry ||= 0;
    weaken($self);
    # Push building the io reader here as an idle task,
    # to avoid blowing up the stack.... (We're already in a callback here)
    # This probably isn't totally necessary, but avoids potential recursion issues.
    my $i; $i = AnyEvent->timer(
        after => $retry,
        cb => sub {
            undef $i;
            $self->_clear_io_reader;
            $self->_clear_connection;
            $self->_io_reader;
        },
    );
}

has _connection_checker => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;
        weaken($self);
        AnyEvent->timer( after => $self->connection_retry_timeout, every => $self->connection_retry_timeout,
            cb => sub {
                $self->_try_rx;
            },
        );
    },
);

sub BUILD {
    my $self = shift;
    $self->_io_reader;
    $self->_connection_checker;
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

