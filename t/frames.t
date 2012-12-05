use Test::More tests => 10;
use Test::Deep;
use Net::SPDY::Compressor;
use Net::SPDY::Framer;

use strict;
use warnings;

# Pipe given frame through a framer pair and expect the
# frame to be read as it was written
sub docmp
{
	my $msg = pop;
	my %frame = @_;

	pipe my ($r, $w);
	my $sess = fork;
	die $! unless defined $sess;

	unless ($sess) {
		close $r;
		my $framer = new Net::SPDY::Framer ({
			compressor => new Net::SPDY::Compressor,
			socket => $w,
		});

		$framer->write_frame (%frame);
		exit 0;
	}

	close $w;
	my $framer = new Net::SPDY::Framer ({
		compressor => new Net::SPDY::Compressor,
		socket => $r,
	});
	kill $sess;
	waitpid $sess, 0;

	cmp_deeply ({$framer->read_frame}, superhashof (\%frame), $msg);
}

docmp (
	type => Net::SPDY::Framer::SYN_STREAM,
	stream_id => 1,
	associated_stream_id => 666,
	priority => 2,
	flags => 3,
	slot => 5,
	headers => [
		':method'	=> 'GET',
		':scheme'	=> 'https',
		':path'		=> '/',
		':version'	=> 'HTTP/1.1',
		':host'		=> 'example.com:443',
		'content-type'	=> 'text/html',
	],
	'SYN_STREAM frame processed correctly'
);

docmp (
	type => Net::SPDY::Framer::SYN_REPLY,
	flags => 5,
	stream_id => 5,
	headers => [
		':status'	=> '500 Front Fell Off',
		':version'	=> 'HTTP/1.1',
		'content-type'	=> 'text/plain',
	],
	'SYN_REPLY frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::RST_STREAM,
	flags => 5,
	stream_id => 5,
	status => 666,
	'RST_STREAM frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::SETTINGS,
	id_values => [{
		flags	=> 1,
		value	=> 1000,
		id	=> 4
	}],
	'SETTINGS frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::PING,
	id	=> 0x706c6c6d,
	'PING frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::GOAWAY,
	last_good_stream_id => 3,
	status	=> 666,
	'GOAWAY frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::HEADERS,
	flags => 3,
	stream_id => 666,
	headers => [
		'accept'	=> 'heavy/metal',
		'user-agent'	=> 'spdy-client Net-Spdy/0.1',
	],
	'HEADERS frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::WINDOW_UPDATE,
	stream_id => 3,
	delta_window_size => 666,
	'WINDOW_UPDATE frame processed correctly'
);

docmp (
	type	=> Net::SPDY::Framer::CREDENTIAL,
	slot	=> 666,
	proof	=> 'pllm',
	certificates => [ 'hello', 'world' ],
	'CREDENTIAL frame processed correctly'
);

docmp (
	flags	=> 64,
	stream_id => 666,
	data	=> 'Hello',
	'Data frame processed correctly'
);
