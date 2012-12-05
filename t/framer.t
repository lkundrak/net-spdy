use Test::More tests => 17;
use Test::Deep;
use Net::SPDY::Compressor;

use strict;
use warnings;

# Read chunk of size same as prototype from an IO::Handle and
# compare it against the prototype.
sub readcmp
{
	my $handle = shift;
	my $proto = shift;
	my $msg = shift;

	my $buf;
	my $toread = length $proto;
	while ($toread) {
		my $read = $handle->read ($buf, $toread, (length $proto) - $toread);
		die $! unless defined $read;
		die 'Short read' unless $read;
		$toread -= $read;
	}

	is (join (' ', map { sprintf '%02x', $_ } unpack 'C*', $buf),
		join (' ', map { sprintf '%02x', $_ } unpack 'C*', $proto),
		$msg);
}


BEGIN { use_ok ('Net::SPDY::Framer') };
require_ok ('Net::SPDY::Framer');

pipe (R, W);
my $framer = new Net::SPDY::Framer ({
	compressor => new Net::SPDY::Compressor,
	socket => *W,
});
ok ($framer, 'Created a framer instance');

my $sess1 = fork;
die $! unless defined $sess1;

unless ($sess1) {
	close R;

	$framer->write_frame (
		type	=> Net::SPDY::Framer::SETTINGS,
		id_values => [{
			flags	=> 1,
			value	=> 1000,
			id	=> 4
		}]
	);

	$framer->write_frame (
		type => Net::SPDY::Framer::SYN_STREAM,
		stream_id => 1,
		associated_stream_id => 0,
		priority => 2,
		flags => 0,
		slot => 0,
		headers => [
			':method'	=> 'GET',
			':scheme'	=> 'https',
			':path'		=> '/',
			':version'	=> 'HTTP/1.1',
			':host'		=> 'example.com:443',
		],
	);

	$framer->write_frame (
		type	=> Net::SPDY::Framer::HEADERS,
		flags => 0,
		stream_id => 1,
		headers => [
			'User-Agent'	=> 'spdy-client Net-Spdy/0.1',
		],
	);

	$framer->write_frame (
		type => Net::SPDY::Framer::SYN_STREAM,
		stream_id => 3,
		associated_stream_id => 1,
		priority => 0,
		flags => Net::SPDY::Framer::FLAG_FIN,
		slot => 0,
		headers => [
			':method'	=> 'GET',
			':scheme'	=> 'https',
			':path'		=> '/',
			':version'	=> 'HTTP/1.1',
			':host'		=> 'example.com:443',
			'User-Agent'	=> 'spdy-client Net-Spdy/0.1',
		],
	);

	$framer->write_frame (
		control => 0,
		data => '',
		stream_id => 1,
		flags => Net::SPDY::Framer::FLAG_FIN,
	);


	$framer->write_frame (
		type	=> Net::SPDY::Framer::PING,
		id	=> 0x706c6c6d,
	);

	$framer->write_frame (
		type	=> Net::SPDY::Framer::GOAWAY,
		last_good_stream_id => 3,
		status	=> 0,
	);

	exit 0;
}
close W;

readcmp (*R,
	"\x80\x03\x00\x04".
	"\x00\x00\x00\x0c".
	"\x00\x00\x00\x01".
	"\x01\x00\x00\x04".
	"\x00\x00\x03\xe8",
	'SETTINGS frame read correctly');

readcmp (*R,
	"\x80\x03\x00\x01".
	"\x00\x00\x00\x86".
	"\x00\x00\x00\x01".
	"\x00\x00\x00\x00".
	"\x40\x00".
	"\x78\x3f\xe3\xc6\xa7\xc2\x00\x6c\x00\x93\xff".
	"\x00\x00\x00\x05".
	"\x00\x00\x00\x07:method\x00\x00\x00\x03GET".
	"\x00\x00\x00\x07:scheme\x00\x00\x00\x05https".
	"\x00\x00\x00\x05:path\x00\x00\x00\x01/".
	"\x00\x00\x00\x08:version\x00\x00\x00\x08HTTP/1.1".
	"\x00\x00\x00\x05:host\x00\x00\x00\x0fexample.com:443".
	"\x00\x00\x00\xff\xff",
	'SYN_STREAM frame read correctly');

readcmp (*R,
	"\x80\x03\x00\x08".
	"\x00\x00\x00\x3c".
	"\x00\x00\x00\x01".
	"\x00\x2e\x00\xd1\xff".
	"\x00\x00\x00\x01".
	"\x00\x00\x00\x0auser-agent\x00\x00\x00\x18spdy-client Net-Spdy/0.1".
	"\x00\x00\x00\xff\xff",
	'HEADERS frame read correctly');

readcmp (*R,
	"\x80\x03\x00\x01".
	"\x01\x00\x00\xaa".
	"\x00\x00\x00\x03".
	"\x00\x00\x00\x01".
	"\x00\x00\x00\x96".
	"\x00\x69".
	"\xff".
	"\x00\x00\x00\x06".
	"\x00\x00\x00\x07:method\x00\x00\x00\x03GET".
	"\x00\x00\x00\x07:scheme\x00\x00\x00\x05https".
	"\x00\x00\x00\x05:path\x00\x00\x00\x01/".
	"\x00\x00\x00\x08:version\x00\x00\x00\x08HTTP/1.1".
	"\x00\x00\x00\x05:host\x00\x00\x00\x0fexample.com:443".
	"\x00\x00\x00\x0auser-agent\x00\x00\x00\x18spdy-client Net-Spdy/0.1".
	"\x00\x00\x00\xff\xff",
	'SYN_STREAM frame read correctly');

readcmp (*R,
	"\x00\x00\x00\x01".
	"\x01\x00\x00\x00",
	'Data frame read correctly');

readcmp (*R,
	"\x80\x03\x00\x06".
	"\x00\x00\x00\x04".
	"pllm",
	'PING frame read correctly');

readcmp (*R,
	"\x80\x03\x00\x07".
	"\x00\x00\x00\x08".
	"\x00\x00\x00\x03".
	"\x00\x00\x00\x00",
	'GOAWAY frame read correctly');

close R;
kill $sess1;
waitpid $sess1, 0;
undef $framer;

pipe (R, W);
my $sess2 = fork;
die $! unless defined $sess2;

unless ($sess2) {
	close R;

	W->print ("\x80\x03\x00\x04".
		"\x00\x00\x00\x0c".
		"\x00\x00\x00\x01".
		"\x01\x00\x00\x04".
		"\x00\x00\x03\xe8");

	W->print ("\x80\x03\x00\x01".
		"\x00\x00\x00\x86".
		"\x00\x00\x00\x01".
		"\x00\x00\x00\x00".
		"\x40\x00".
		"\x78\x3f\xe3\xc6\xa7\xc2\x00\x6c\x00\x93\xff".
		"\x00\x00\x00\x05".
		"\x00\x00\x00\x07:method\x00\x00\x00\x03GET".
		"\x00\x00\x00\x07:scheme\x00\x00\x00\x05https".
		"\x00\x00\x00\x05:path\x00\x00\x00\x01/".
		"\x00\x00\x00\x08:version\x00\x00\x00\x08HTTP/1.1".
		"\x00\x00\x00\x05:host\x00\x00\x00\x0fexample.com:443".
		"\x00\x00\x00\xff\xff");

	W->print ("\x80\x03\x00\x08".
		"\x00\x00\x00\x3c".
		"\x00\x00\x00\x01".
		"\x00\x2e\x00\xd1\xff".
		"\x00\x00\x00\x01".
		"\x00\x00\x00\x0auser-agent\x00\x00\x00\x18spdy-client Net-Spdy/0.1".
		"\x00\x00\x00\xff\xff");

	W->print ("\x80\x03\x00\x01".
		"\x01\x00\x00\xaa".
		"\x00\x00\x00\x03".
		"\x00\x00\x00\x01".
		"\x00\x00\x00\x96".
		"\x00\x69".
		"\xff".
		"\x00\x00\x00\x06".
		"\x00\x00\x00\x07:method\x00\x00\x00\x03GET".
		"\x00\x00\x00\x07:scheme\x00\x00\x00\x05https".
		"\x00\x00\x00\x05:path\x00\x00\x00\x01/".
		"\x00\x00\x00\x08:version\x00\x00\x00\x08HTTP/1.1".
		"\x00\x00\x00\x05:host\x00\x00\x00\x0fexample.com:443".
		"\x00\x00\x00\x0auser-agent\x00\x00\x00\x18spdy-client Net-Spdy/0.1".
		"\x00\x00\x00\xff\xff");

	W->print ("\x00\x00\x00\x01".
		"\x01\x00\x00\x00");

	W->print ("\x80\x03\x00\x06".
		"\x00\x00\x00\x04".
		"pllm");

	W->print ("\x80\x03\x00\x07".
		"\x00\x00\x00\x08".
		"\x00\x00\x00\x03".
		"\x00\x00\x00\x00");

	exit 0;
}
close W;

$framer = new Net::SPDY::Framer ({
	compressor => new Net::SPDY::Compressor,
	socket => *R,
});

cmp_deeply ({$framer->read_frame}, {
	control	=> 1,
	version	=> 3,
	flags	=> 0,
	length	=> 12,

	entries	=> 1,
	type	=> Net::SPDY::Framer::SETTINGS,
	id_values => [{
		flags	=> 1,
		value	=> 1000,
		id	=> 4
}],
}, 'SETTINGS frame written correctly');

cmp_deeply ({$framer->read_frame}, {
	control	=> 1,
	version	=> 3,
	flags	=> 0,
	length	=> 134,

	type => Net::SPDY::Framer::SYN_STREAM,
	stream_id => 1,
	associated_stream_id => 0,
	priority => 2,
	flags => 0,
	slot => 0,
	headers => [
		':method'	=> 'GET',
		':scheme'	=> 'https',
		':path'		=> '/',
		':version'	=> 'HTTP/1.1',
		':host'		=> 'example.com:443',
	],
}, 'SYN_STREAM frame written correctly');

cmp_deeply ({$framer->read_frame}, {
	control	=> 1,
	version	=> 3,
	flags	=> 0,
	length	=> 60,

	type	=> Net::SPDY::Framer::HEADERS,
	flags => 0,
	stream_id => 1,
	headers => [
		'user-agent'	=> 'spdy-client Net-Spdy/0.1',
	],
}, 'SETTINGS frame written correctly');

cmp_deeply ({$framer->read_frame}, {
	control	=> 1,
	version	=> 3,
	flags	=> 0,
	length	=> 170,

	type => Net::SPDY::Framer::SYN_STREAM,
	stream_id => 3,
	associated_stream_id => 1,
	priority => 0,
	flags => Net::SPDY::Framer::FLAG_FIN,
	slot => 0,
	headers => [
		':method'	=> 'GET',
		':scheme'	=> 'https',
		':path'		=> '/',
		':version'	=> 'HTTP/1.1',
		':host'		=> 'example.com:443',
		'user-agent'	=> 'spdy-client Net-Spdy/0.1',
	],
}, 'SYN_STREAM frame written correctly');

cmp_deeply ({$framer->read_frame}, {
	control => 0,
	flags	=> 0,
	length	=> 0,

	data => '',
	stream_id => 1,
	flags => Net::SPDY::Framer::FLAG_FIN,
}, 'Data frame written correctly');

cmp_deeply ({$framer->read_frame}, {
	control	=> 1,
	version	=> 3,
	flags	=> 0,
	length	=> 4,

	type	=> Net::SPDY::Framer::PING,
	id	=> 0x706c6c6d,
}, 'PING frame written correctly');

cmp_deeply ({$framer->read_frame}, {
	control	=> 1,
	version	=> 3,
	flags	=> 0,
	length	=> 8,

	type	=> Net::SPDY::Framer::GOAWAY,
	last_good_stream_id => 3,
	status	=> 0,
}, 'GOAWAY frame written correctly');

kill $sess2;
waitpid $sess2, 0;
