use strict;
use warnings;

use Module::Build;

my $build = Module::Build->new(
	module_name => 'Net::SPDY',
	license => 'perl',
	dist_author => 'Lubomir Rintel <lkundrak@v3.sk>',
	dist_version => '0.1_2',
	meta_merge => {
		resources => {
			bugtracker => 'http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-SPDY',
			repository => 'https://github.com/lkundrak/net-spdy',
		}
	},
	requires => {
		'IO::Socket::SSL' => 0,
		'Compress::Zlib' => 0,
		'URI' => 0,
	},
	build_requires => {
		'Test::Pod' => 0,
	},
);

$build->create_build_script;
