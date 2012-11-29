package Net::SPDY::Session;

=head1 NAME

Net::SPDY::Session - Handle SPDY protocol connection

=head1 ALPHA WARNING

B<Please read carefully:> This is an ALPHA stage software.
In particular this means that even though it probably won't kill your cat,
re-elect George W. Bush nor install Solaris 11 Express edition to your hard
drive, it is in active development, functionality is missing and no APIs are
stable.

See F<TODO> file in the distribution to learn about missing and planned
functionality. You are more than welcome to join the development and submit
patches with fixes or enhancements.  Bug reports are probably not very useful
at this point.

=head1 SYNOPSIS

  use Net::SPDY::Session;

  my $server = new IO::Socket::SSL (
      LocalAddr => 'localhost:443',
      ReuseAddr => 1,
      SSL_server => 1,
      SSL_cert_file => $cert,
      SSL_key_file => $key,
      SSL_npn_protocols => ['spdy/3'])
      or die IO::Socket::SSL::errstr;

  while (my $client = $server->accept) {
      # Fork a child to handle the connection
      my $kidpid = fork;
      die $! unless defined $kidpid;
      # Proceed with next connection
      next if $kidpid;

      my $session = new Net::SPDY::Session ($client);
      while ($session->process_frame) {
           ...
      }
  }

=head1 DESCRIPTION

B<Net::SPDY::Session> represents the single stateful SPDY connection along
with its state, which in called a session.

It provides access to the underlying protocol and convenience functions to
access the state and communicate via the protocol.

=cut

use strict;
use warnings;

use Net::SPDY::Framer;
use Net::SPDY::Compressor;

our $VERSION = '0.1';

=head1 PROPERTIES

=over 4

=item compressor

L<Net::SPDY::Compressor> object representing the Zlib streams (one in each
direction) used by the framer. A new one is created upon session construction.

=item socket

L<IO::Handle> instance that is used for actual network communication.

=item framer

L<Net::SPDY::Framer> the protocol implementation on top of I<socket> and
I<compressor> it is coupled with. A new one is created upon session construction.

=back

=head1 METHODS

=over 4

=item new SOCKET

Creates a new session instance. First argument is the socket (either server
or client, it does not matter) for the network communication.

=cut

sub new
{
	my $class = shift;
	my $self = bless {}, $class;

	# Couple with framer
	$self->{compressor} = new Net::SPDY::Compressor ();
	$self->{socket} = shift;

	$self->{framer} = new Net::SPDY::Framer ({
		compressor => $self->{compressor},
		socket => $self->{socket},
	});

	return $self;
}

=item process_frame

Read a single frame from the framer and process it, which may include changing
session state and and eventually sending an appropriate response.

=cut

sub process_frame
{
	my $self = shift;

	my %frame = $self->{framer}->read_frame ();
	return () unless %frame;

	if (not $frame{control}) {
		warn 'Not implemented: Data frame received';
		return %frame;
	}

	if ($frame{type} == Net::SPDY::Framer::SYN_STREAM) {
		my $body = 'Hello, World!';

		$self->{framer}->write_syn_reply (
			stream_id => $frame{stream_id},
			flags => 0,
			headers => [
			      ':status' => '200 Ok',
			      ':version' => 'HTTP/1.1',
			      'content-length' => length($body),
			]
		);
		$self->{framer}->write_frame (
			control => 0,
			stream_id => $frame{stream_id},
			flags => Net::SPDY::Framer::FLAG_FIN,
			data => $body,
		);
	} elsif ($frame{type} == Net::SPDY::Framer::SETTINGS) {
		# We should remember values gotten here
		warn 'Not implemented: Got settings frame'
	} elsif ($frame{type} == Net::SPDY::Framer::PING) {
		$self->{framer}->write_ping (
			flags => 0,
			data => $frame{data},
		);
	} elsif ($frame{type} == Net::SPDY::Framer::GOAWAY) {
		$self->close (0);
	} elsif ($frame{type} == Net::SPDY::Framer::HEADERS) {
		# We should remember values gotten here for stream
		warn 'Not implemented: Got headers frame'
	} else {
		die 'Unknown frame type '.$frame{type};
	}

	return %frame;
}

=item close

Do whatever is needed to terminate a connection.
May involve sending a C<GOAWAY> frame and closing the socket.

=cut

sub close
{
	my $self = shift;
	my $status = shift;

	$self->{framer}->write_goaway (
		last_good_stream_id	=> 0,
		status			=> $status,
	);
	$self->{framer}{socket}->close;
	$self->{framer}{socket} = undef;
}

=back

=head1 SEE ALSO

=over

=item *

L<https://developers.google.com/speed/spdy/> -- SPDY project web site

=item *

L<IO::Socket::SSL> -- SSL/TLS socket bindings with NPN support

=item *

L<Net::SPDY::Framer> -- SPDY protocol implementation

=item *

L<Net::SPDY::Compressor> -- SPDY header compression

=back

=head1 CONTRIBUTING

Source code for I<Net::SPDY> is kept in a public GIT repository.
Visit L<https://github.com/lkundrak/net-spdy>.

Bugs reports and feature enhancement requests are tracked at
L<https://rt.cpan.org/Public/Dist/Display.html?Name=Net::SPDY>.

=head1 COPYRIGHT

Copyright 2012, Lubomir Rintel

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Lubomir Rintel C<lkundrak@v3.sk>

=cut

1;
