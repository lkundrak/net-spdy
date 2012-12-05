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
use Net::SPDY::Stream;

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

=cut

sub got_settings
{
	my $self = shift;
	my %frame = @_;

	if ($frame{flags} & Net::SPDY::Framer::FLAG_SETTINGS_CLEAR_SETTINGS) {
		$self->{settings} = {};
	}

	my %new_settings;
	foreach my $setting (@{$frame{id_values}}) {
		next if exists $new_settings{$setting->{id}};
		$new_settings{$setting->{id}} = [$setting->{value},
			$setting->{flags}];
	}
	%{$self->{settings}} = (%{$self->{settings}}, %new_settings);
}

=item new SOCKET

Creates a new session instance. First argument is the socket (either server
or client, it does not matter) for the network communication.

=cut

sub new
{
	my $class = shift;
	my $self = shift;

	bless $self, $class;

	# Couple with framer
	$self->{compressor} = new Net::SPDY::Compressor ();
	$self->{framer} = new Net::SPDY::Framer ({
		compressor => $self->{compressor},
		socket => $self->{socket},
	});

	$self->{settings} = {};
	$self->{stream_id} = 0;
	$self->{streams} = {};

	return $self;
}

sub stream
{
	my $self = shift;
	my $stream = shift;

	$self->{stream_id} += 1 + $self->{stream_id} % 2;
	$stream->{stream_id} = $self->{stream_id};
	$stream->{framer} = $self->{framer};

	$stream = new Net::SPDY::Stream ($stream);
	$self->{streams}{$self->{stream_id}} = $stream;

	return $stream;
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
		my $stream = $self->{streams}{$frame{stream_id}}
			or die 'Data for nonexistent stream';
		$stream->got_data (%frame);
		return %frame;
	}

	if ($frame{type} == Net::SPDY::Framer::SYN_STREAM) {
		die 'Stream already exists' if exists $self->{streams}{$frame{stream_id}};

		my $stream = new Net::SPDY::Stream ({
			stream_id => $frame{stream_id},
			framer => $self->{framer},
			got_fin_callback => $self->{got_fin_callback},
		});

		$self->{streams}{$frame{stream_id}} = $stream;
		$stream->got_syn (%frame);

	} elsif ($frame{type} == Net::SPDY::Framer::SYN_REPLY) {
		my $stream = $self->{streams}{$frame{stream_id}}
			or die 'Reply to a nonexistent stream';
		$stream->got_reply (%frame);
	} elsif ($frame{type} == Net::SPDY::Framer::RST_STREAM) {
		my $stream = $self->{streams}{$frame{stream_id}}
			or die 'Reset of a nonexistent stream';
		$stream->got_rst (%frame);
	} elsif ($frame{type} == Net::SPDY::Framer::SETTINGS) {
		$self->got_settings (%frame);
	} elsif ($frame{type} == Net::SPDY::Framer::PING) {
		$self->{framer}->write_ping (
			flags => 0,
			id => $frame{id},
		);
	} elsif ($frame{type} == Net::SPDY::Framer::GOAWAY) {
		$self->close (0);
	} elsif ($frame{type} == Net::SPDY::Framer::HEADERS) {
		my $stream = $self->{streams}{$frame{stream_id}}
			or die 'Headers for nonexistent stream';
		$stream->got_headers (%frame);
		return %frame;
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
