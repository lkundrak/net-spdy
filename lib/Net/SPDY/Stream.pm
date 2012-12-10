package Net::SPDY::Stream;

=head1 NAME

Net::SPDY::Stream - Handle SPDY stream

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

  use Net::SPDY::Stream;

=head1 DESCRIPTION

B<Net::SPDY::Stream> represents a single HTTP request over SPDY connection.

=cut

use strict;
use warnings;

use HTTP::Response;
use HTTP::Request;
use HTTP::Headers;
use URI;

our $VERSION = '0.1';

=head1 PROPERTIES

=over 4

=item framer

L<Net::SPDY::Framer> the protocol implementation on top of I<socket> and
I<compressor> it is coupled with. A new one is created upon session construction.

=back

=head1 METHODS

=over 4

=item new

=cut

sub new
{
	my $class = shift;
	my $self = shift;

	$self->{received_data} = '';
	bless $self, $class;

	return $self;
}

sub finish
{
	my $self = shift;

	$self->{framer}->write_frame (
		stream_id => $self->{stream_id},
		flags => Net::SPDY::Framer::FLAG_FIN,
		data => '',
	);
}

sub check_fin
{
	my $self = shift;
	my %frame = @_;

	if ($frame{flags} & Net::SPDY::Framer::FLAG_FIN) {
		if ($self->{response}) {
			$self->{response}->content ($self->{data});
		}
		$self->{got_fin_callback} and $self->{got_fin_callback}->($self);
	}
}

sub got_syn
{
	my $self = shift;
	my %frame = @_;

	my %headers = @{$frame{headers}};

	my $version = delete $headers{':version'};
	my $uri = new URI (delete $headers{':path'}, $headers{':scheme'});
	$uri->host (delete $headers{':host'});
	$uri->scheme (delete $headers{':scheme'});

	my $request = new HTTP::Request (delete $headers{':method'}, $uri,
		new HTTP::Headers (%headers));
	$self->{request} = $request;
	$self->check_fin (%frame);
}

sub send_syn
{
	my $self = shift;
	my $request = shift;

	$self->{request} = $request;
	$self->{framer}->write_frame (
		type => Net::SPDY::Framer::SYN_STREAM,
		stream_id => $self->{stream_id},
		associated_stream_id => 0,
		priority => 2,
		flags => 0,
		slot => 0,
		headers => [
			':method'	=> $request->method,
			':scheme'	=> $request->uri->scheme,
			':path'		=> $request->uri->path,
			':version'	=> $request->protocol,
			':host'		=> $request->uri->host_port,
			%{$request->headers},
		],
	);

}

sub got_reply
{
	my $self = shift;
	my %frame = @_;

	my %headers = @{$frame{headers}};

	my ($code, $status) = (delete $headers{':status'}) =~ /^(\d+)\s*(.*)$/
		or die 'Malformed status line';
	my $version = delete $headers{':version'};

	my $response = new HTTP::Response ($1, $2, new HTTP::Headers (%headers));
	$response->protocol ($version);
	$response->request ($self->{request});
	$self->{response} = $response;
	$self->check_fin (%frame);
}

sub send_reply
{
	my $self = shift;
	my $response = shift;

	$self->{response} = $response;
	$self->{framer}->write_frame (
		type => Net::SPDY::Framer::SYN_REPLY,
		stream_id => $self->{stream_id},
		flags => 0,
		headers => [
			':status' => $response->status_line,
			':version' => $response->protocol,
			%{$response->headers},
		]
	);
}

sub got_data
{
	my $self = shift;
	my %frame = @_;

	if ($self->{got_data_callback}) {
		$self->{got_data_callback}->($self, $frame{data});
	} else {
		$self->{data} .= $frame{data};
	}

	$self->check_fin (%frame);
}

sub send_data
{
	my $self = shift;
	my $data = shift;

	my $response = $self->{response};
	$self->{framer}->write_frame (
		stream_id => $self->{stream_id},
		flags => 0,
		data => $data,
	);
}

sub got_headers
{
	my $self = shift;
	my %frame = @_;

	my $message = $self->{response} || $self->{request};
	die 'Stream not yet estabilished' unless $message;

	while (my $name = shift @{$frame{headers}}) {
		my $value = shift @{$frame{headers}};
		$message->push_header ($name => $value);
	}
}

sub got_rst
{
	my $self = shift;
	my %frame = @_;
}

sub send_rst
{
	my $self = shift;
	my $response = shift;
	my $status = shift;

	$self->{framer}->write_frame (
		type => Net::SPDY::Framer::SYN_REPLY,
		stream_id => $self->{stream_id},
		flags => 0,
		status => $status,
	);
}

1;
