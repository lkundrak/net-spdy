use Test::More tests => 4;
use Test::Deep;
use Net::SPDY::Session;
use Net::SPDY::Framer;
use Socket;

use strict;
use warnings;

socketpair (S, C, AF_UNIX, SOCK_STREAM, PF_UNSPEC);

my $sess1 = fork;
die $! unless defined $sess1;

# Spawn a client
unless ($sess1) {
	close S;

	my $framer = new Net::SPDY::Framer ({
		compressor => new Net::SPDY::Compressor,
		socket => *C,
	});

	$framer->write_frame (
		type	=> Net::SPDY::Framer::SETTINGS,
		id_values => [{
			flags	=> 0x0,
			value	=> 1000,
			id	=> Net::SPDY::Framer::SETTINGS_MAX_CONCURRENT_STREAMS,
		}, {
			flags	=> Net::SPDY::Framer::FLAG_SETTINGS_PERSIST_VALUE,
			value	=> 666,
			id	=> Net::SPDY::Framer::SETTINGS_DOWNLOAD_BANDWIDTH,
		}],
	);

	$framer->write_frame (
		type	=> Net::SPDY::Framer::SETTINGS,
		id_values => [{
			flags	=> 0x0,
			value	=> 8086,
			id	=> Net::SPDY::Framer::SETTINGS_DOWNLOAD_BANDWIDTH,
		}, {
			flags	=> Net::SPDY::Framer::FLAG_SETTINGS_PERSIST_VALUE,
			value	=> 1337,
			id	=> Net::SPDY::Framer::SETTINGS_UPLOAD_BANDWIDTH,
		}, {
			flags	=> 0x0,
			value	=> 1024,
			id	=> Net::SPDY::Framer::SETTINGS_UPLOAD_BANDWIDTH,
		}],
	);

	$framer->write_frame (
		type	=> Net::SPDY::Framer::SETTINGS,
		flags	=> Net::SPDY::Framer::FLAG_SETTINGS_CLEAR_SETTINGS,
		id_values => [{
			flags	=> 0x0,
			value	=> 1024,
			id	=> Net::SPDY::Framer::SETTINGS_UPLOAD_BANDWIDTH,
		}],
	);

	exit 0;
}
close C;

my $session = new Net::SPDY::Session (*S);
ok ($session, 'Created a session instance');

$session->process_frame;
cmp_deeply ($session->{settings}, {
	Net::SPDY::Framer::SETTINGS_MAX_CONCURRENT_STREAMS
		=> [ 1000, 0x0 ],
	Net::SPDY::Framer::SETTINGS_DOWNLOAD_BANDWIDTH
		=> [ 666, Net::SPDY::Framer::FLAG_SETTINGS_PERSIST_VALUE ],
}, 'Got initial SETTINGS');


$session->process_frame;
cmp_deeply ($session->{settings}, {
	Net::SPDY::Framer::SETTINGS_MAX_CONCURRENT_STREAMS
		=> [ 1000, 0x0 ],
	Net::SPDY::Framer::SETTINGS_DOWNLOAD_BANDWIDTH
		=> [ 8086, 0x0 ],
	Net::SPDY::Framer::SETTINGS_UPLOAD_BANDWIDTH,
		=> [ 1337, Net::SPDY::Framer::FLAG_SETTINGS_PERSIST_VALUE ],
}, 'Processed more SETTINGS');

$session->process_frame;
cmp_deeply ($session->{settings}, {
	Net::SPDY::Framer::SETTINGS_UPLOAD_BANDWIDTH,
		=> [ 1024, 0x0 ],
}, 'Overrode SETTINGS');

close S;
kill $sess1;
waitpid $sess1, 0;
