#!/usr/bin/perl

=head1 NAME

spdy-client - Example Net::SPDY client

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

spdy-client <session-uri> [<path> ...]

=head1 DESCRIPTION

B<spdy-client> is a toy SPDY client, showcasing L<Net::SPDY> capabilities.

It's hardly of any useful use.

=cut

use strict;
use warnings;

use Net::SPDY::Session;
use Net::SPDY::Framer;
use IO::Socket::SSL;
use HTTP::Request::Common;
use URI;

my $peer = shift @ARGV or die 'Missing argument';
$peer = new URI($peer);
die 'Bad protocol given' unless $peer->scheme eq 'https';

my $client = new IO::Socket::SSL (PeerAddr => $peer->host.':'.$peer->port,
	SSL_npn_protocols => ['spdy/3'])
	or die IO::Socket::SSL::errstr;

die 'No NPN' unless $client->next_proto_negotiated;
die 'Bad protocol' unless $client->next_proto_negotiated eq 'spdy/3';
$client->verify_hostname ($peer->host, 'http')
	or warn 'SSL host name verification failed';

my $session = new Net::SPDY::Session ($client);

my $framer = $session->{framer};
foreach my $path (@ARGV) {

	# Construct a request
	my $u = $peer->clone;
	$u->path ($path);
	my $message = GET ($u);
	$message->protocol ('HTTP/1.1');
	$message->header (Accept => 'text/plain');

	# Construct a stream
	my $stream = $session->stream ($message, sub {
		my $response = shift;
		warn 'Got: '.$response->content;
	});

	# Not implemented by GFE it seems
	$framer->write_frame (
		type	=> Net::SPDY::Framer::HEADERS,
		flags => 0,
		stream_id => $stream->{stream_id},
		headers => [
			'User-Agent'	=> 'spdy-client Net-Spdy/0.1',
		],
	);

	$stream->finish;
}

$framer->write_frame (
	type	=> Net::SPDY::Framer::SETTINGS,
	id_values => [{
		flags	=> 1,
		value	=> 1000,
		id	=> 4
	}]
);

$framer->write_frame (
	type	=> Net::SPDY::Framer::PING,
	id	=> 0x706c6c6d,
);

$framer->write_frame (
	type	=> Net::SPDY::Framer::GOAWAY,
	last_good_stream_id => $session->{stream_id},
	status	=> 0,
);

while (my %frame = $session->process_frame) {
}


=head1 EXAMPLES

=over

=item B<spdy-client https://localhost:8443/ /hello /world>

Do something.

=item B<spdy-client https://clients1.google.com/ /generate_204>

So useful.

=back

=head1 SEE ALSO

=over

=item *

L<https://developers.google.com/speed/spdy/> -- SPDY project web site

=item *

L<spdy-server> -- Comparably useful server

=item *

L<Net::SPDY::Session> -- Use SPDY programatically

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
