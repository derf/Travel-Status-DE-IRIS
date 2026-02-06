#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;
use utf8;

use Test::More tests => 17;
use Test::Number::Delta;

BEGIN {
	use_ok('Travel::Status::DE::IRIS::Stations');
}
require_ok('Travel::Status::DE::IRIS::Stations');

my @emptypairs = grep { not( length( $_->[0] ) and length( $_->[1] ) ) }
  Travel::Status::DE::IRIS::Stations::get_stations;

is_deeply( \@emptypairs, [], 'no stations with empty code / name' );

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('EE') ],
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	'get_station: exact match by DS100 works'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station(8000098) ],
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	'get_station: exact match by EVA/UIC works'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('Essen Hbf') ],
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	'get_station: exact match by name works'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('essen hbf') ],
	[ [ 'EE', 'Essen Hbf', 8000098, 7.014793,  51.451355 ] ],
	'get_station: exact match by name is case insensitive'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('essen sued') ],
	[ [ 'EESD', 'Essen Süd', 8001897, 7.023098,  51.439295 ] ],
	'get_station: exact match with normalization (1)'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('Essen-Steele') ],
	[ [ 'EEST', 'Essen-Steele', 8000099, 7.075552,  51.450684 ] ],
	'get_station: exact match by name works by shortest prefix'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('essen-steele') ],
	[ [ 'EEST', 'Essen-Steele', 8000099, 7.075552,  51.450684 ] ],
	'get_station: exact match by name (shortest prefix) is case insensitive'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('mönchengladbach hf') ],
	[ [ 'KM', 'Mönchengladbach Hbf', 8000253, 6.446111,  51.196583 ] ],
	'get_station: close fuzzy match works (one result)'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('MönchenGladbach BBF') ],
	[ [ 'KM', 'Mönchengladbach Hbf', 8000253, 6.446111,  51.196583 ] ],
	'get_station: close fuzzy match is case insensitive'
);

is_deeply(
	[ Travel::Status::DE::IRIS::Stations::get_station('Borbeck') ],
	[
		[ 'EEBE', 'Essen-Bergeborbeck', 8001901, 6.97711100,  51.4803960 ],
		[ 'EEBB', 'Essen-Borbeck', 8001902, 6.94846100,  51.4731030 ],
		[ 'EEBS', 'Essen-Borbeck Süd', 8005031, 6.95392200,  51.4616730 ],
		[ 'KARS', 'Arsbeck', 8000611, 6.206563,  51.152006 ],
		[ 'ELBK', 'Lembeck', 8003630, 7.02548,  51.751244 ],
	],
	'get_station: partial match with substring and levenshtein'
);

is_deeply(
	[ map { [$_->[0][0], $_->[0][1]] } Travel::Status::DE::IRIS::Stations::get_station_by_location(7.02458, 51.43862) ],
	[
		[ 'EESD', 'Essen Süd'        ],
		[ 'EE',   'Essen Hbf'        ],
		[ 'EESA', 'Essen Stadtwald'  ],
		[ 'EEUE', 'Essen-Überruhr'   ],
		[ 'EENW', 'Essen West'       ],
		[ 'EEST', 'Essen-Steele'     ],
		[ 'EEHU', 'Essen-Hügel'      ],
		[ 'EEHH', 'Essen-Holthausen' ],
		[ 'EEKS', 'Essen-Kray Süd'   ],
		[ 'EESO', 'Essen-Steele Ost' ],
	],
	'get_station_by_location: 10 matches for Foobar'
);

is(scalar Travel::Status::DE::IRIS::Stations::get_station_by_location(7.02458, 51.43862, 1),
	1, 'get_station_by_location(Foobar): only one match');

is_deeply(
	(Travel::Status::DE::IRIS::Stations::get_station_by_location(7.02458, 51.43862, 1))[0][0],
	[ 'EESD', 'Essen Süd', 8001897, 7.023098, 51.439295],
	'get_station_by_location(Foobar): correct location data'
);

delta_ok((Travel::Status::DE::IRIS::Stations::get_station_by_location(7.02458, 51.43862, 1))[0][1],
	0.127234298397033, 'get_station_by_location(Foobar): correct distance');
