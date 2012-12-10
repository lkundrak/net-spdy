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
use HTTP::Response;
use HTTP::Headers;
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

sub respond_index
{
	my $response = shift;

	$response->header ('Content-Type' => 'text/html');
	#$response->headers->push_header ('Content-Type' => 'text/plain');
	$response->content (<<EOR);
<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 3.2//EN">
<html>
<head>
	<title>Hello, World!</title>
</head>
<body>
	<h1>Hello, World!</h1>
	<p><iframe src="/hello"></iframe></p>
	<p><script>
		xmlhttp = new XMLHttpRequest();
		document.write (xmlhttp);

		xmlhttp.open ("POST", "/long", true);

		xmlhttp.onreadystatechange = function () {
			console.log ("PLLM "+xmlhttp.readyState);
		};
		xmlhttp.onloadstart = function () { console.log ("onloadstart"); };
		xmlhttp.onprogress = function () { console.log ("onprogress"); };
		xmlhttp.onabort = function () { console.log ("onabort"); };
		xmlhttp.onerror = function () { console.log ("onerror"); };
		xmlhttp.onload = function () { console.log ("onload"); };
		xmlhttp.ontimeout = function () { console.log ("ontimeout"); };
		xmlhttp.onloadend = function () { console.log ("onloadend"); };

		xmlhttp.onprogress = function () {
			//document.write ("a");
			console.log ("onprogress");
		};

		xmlhttp.send ("pllm");

	</script></p>
</body>
</html>
EOR
}

sub respond_hello
{
	my $response = shift;
	$response->content ($response->request->as_string);
}

sub respond_404
{
	my $response = shift;
	$response->code (404);
	$response->message ('Not funny');
	$response->content ('Resource not found');
}

my @longones = ();
$SIG{ALRM} = sub {
	local $!;
	foreach (@longones) {
		$_->send_data ("lololo($_->{stream_id})\n");
	}
	alarm 1;
};

sub respond
{
	my $self = shift;

	my $response = new HTTP::Response (200 => 'Ok',
		new HTTP::Headers (Server => 'spdy-server.pl Net-SPDY/0.1'));
	$response->request ($self->{request});
	$response->protocol ('HTTP/1.1');
	$response->header ('Content-Type' => 'text/plain');

	my $path = $self->{request}->uri->path;
	if ($path eq '/') {
		respond_index ($response);
	} elsif ($path eq '/hello') {
		respond_hello ($response);
	} elsif ($path ne '/long') {
		respond_404 ($response);
	}

	$self->{response} = $response;
	$self->send_reply ($response);
	if ($response->content) {
		$self->send_data ($response->content);
		$self->finish;
	}

	if ($path eq '/long') {
		push @longones, $self;
	}
}

$SIG{CHLD} = sub {
	local $!;
	wait;
};
$server->listen or die $!;
while (1) {
	my $client = $server->accept;
	next if $!{EINTR};
	last unless $client;

	die 'No NPN' unless $client->next_proto_negotiated;
	die 'Bad protocol' unless 'spdy/3' eq $client->next_proto_negotiated;
	next if fork;

	$SIG{ALRM}->();
	my $session = new Net::SPDY::Session ({
		socket => $client,
		got_fin_callback => \&respond,
	});
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
