#!/usr/bin/perl

=head1 NAME

spdy-server - Example Net::SPDY server

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

spdy-server <listen-uri> <ssl-certificate> <ssl-certificate-key>

=head1 DESCRIPTION

B<spdy-server> is a toy SPDY web server, showcasing L<Net::SPDY>
capabilities.

It's hardly of any useful use.

=cut

use strict;
use warnings;

use Net::SPDY::Session;
use IO::Socket::SSL;
use URI;
use Errno qw/EINTR/;

my $listen = shift @ARGV or die 'Missing listen URI';
my $cert = shift @ARGV or die 'Missing SSL certificate';
my $key = shift @ARGV or die 'Missing SSL key';
$listen = new URI($listen);
die 'Bad protocol given' unless $listen->scheme eq 'https';

my $server = new IO::Socket::SSL (
	LocalAddr => $listen->host.':'.$listen->port,
	ReuseAddr => 1,
	SSL_server => 1,
	SSL_cert_file => $cert,
	SSL_key_file => $key,
	SSL_npn_protocols => ['spdy/3'])
	or die IO::Socket::SSL::errstr;

$SIG{CHLD} = sub { wait };
$server->listen or die $!;
while (1) {
	my $client = $server->accept;
	next if $!{EINTR};
	last unless $client;

	die 'No NPN' unless $client->next_proto_negotiated;
	die 'Bad protocol' unless 'spdy/3' eq $client->next_proto_negotiated;
	next if fork;

	my $session = new Net::SPDY::Session ($client);
	while (my %frame = $session->process_frame) {
	}
}

=head1 EXAMPLES

=over

=item B<spdy-server https://localhost:8443/ cert.pem key.pem>

Just listen. Listen.

=back

=head1 SEE ALSO

=over

=item *

L<https://developers.google.com/speed/spdy/> -- SPDY project web site

=item *

L<spdy-client> -- Comparably useful client

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
