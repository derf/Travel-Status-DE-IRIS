#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;
use utf8;

use Test::More tests => 12;

BEGIN {
	use_ok('Travel::Status::DE::IRIS::Stations');
}
require_ok('Travel::Status::DE::IRIS::Stations');

my @emptypairs = grep { not( length( $_->[0] ) and length( $_->[1] ) ) }
  Travel::Status::DE::IRIS::Stations::get_stations;

is_deeply( \@emptypairs, [], 'no stations with empty code / name' );

is_deeply(
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('EE') ],
	'get_station: exact match by DS100 works'
);

is_deeply(
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('Essen Hbf') ],
	'get_station: exact match by name works'
);

is_deeply(
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('essen hbf') ],
	'get_station: exact match by name is case insensitive'
);

is_deeply(
	[ [ 'EESD', 'Essen Süd', 8001897, 7.023098,  51.439295 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('essen sued') ],
	'get_station: exact match with normalization (1)'
);

is_deeply(
	[ [ 'EEST', 'Essen-Steele', 8000099, 7.075552,  51.450684 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('Essen-Steele') ],
	'get_station: exact match by name works by shortest prefix'
);

is_deeply(
	[ [ 'EEST', 'Essen-Steele', 8000099, 7.075552,  51.450684 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('essen-steele') ],
	'get_station: exact match by name (shortest prefix) is case insensitive'
);

is_deeply(
	[ [ 'KM', 'Mönchengladbach Hbf', 8000253, 6.446111,  51.196583 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('mönchengladbach hf') ],
	'get_station: close fuzzy match works (one result)'
);

is_deeply(
	[ [ 'KM', 'Mönchengladbach Hbf', 8000253, 6.446111,  51.196583 ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('MönchenGladbach BBF') ],
	'get_station: close fuzzy match is case insensitive'
);

is_deeply(
	[
		[ 'EEBE', 'Essen-Bergeborbeck', 8001901, 6.977782,  51.480201 ],
		[ 'EEBB', 'Essen-Borbeck', 8001902, 6.948795,  51.472713 ],
		[ 'EEBS', 'Essen-Borbeck Süd', 8005031, 6.953922,  51.461673 ],
		[ 'EGAR', 'Garbeck', 8002180, 7.839903,  51.321459 ],
	],
	[ Travel::Status::DE::IRIS::Stations::get_station('Borbeck') ],
	'get_station: partial match with substring and levenshtein'
);
