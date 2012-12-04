use Test::More tests => 8;

BEGIN { use_ok ('Net::SPDY::Compressor') };
require_ok ('Net::SPDY::Compressor');

my $compr = new Net::SPDY::Compressor;
ok ($compr, 'Created a compressor instance');

is ($compr->uncompress ("\x78\x3f\xe3\xc6\xa7\xc2\x00\x0d\x00\xf2\xff".
	"Hello, World!\x00\x00\x00\xff\xff"), 'Hello, World!',
	'Decompression seems to work');

$compr = new Net::SPDY::Compressor;
is ($compr->uncompress ($compr->compress ('Hello, World!')),
	'Hello, World!', 'Round trip seems to work');
is ($compr->uncompress ($compr->compress ('Hello, World!')),
	'Hello, World!', 'Streams seem to work');

undef $@;
eval { $compr->uncompress ("\x78\x3f\xe3\xc6\xa7\xc2\x00\x0d\x00\xf2\xff".
	"Hello, World!\x00\x00\x00\xff\xff") };
ok ($@, 'Out of order data causes an abort');

$compr = new Net::SPDY::Compressor;
undef $@;
eval { $compr->uncompress ("pllm") };
ok ($@, 'Garbled data causes an abort');
