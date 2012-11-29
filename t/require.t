use Test::More tests => 6;

BEGIN {
	use_ok ('Net::SPDY::Compressor');
	use_ok ('Net::SPDY::Framer');
	use_ok ('Net::SPDY::Session');
}

require_ok ('Net::SPDY::Compressor');
require_ok ('Net::SPDY::Framer');
require_ok ('Net::SPDY::Session');
