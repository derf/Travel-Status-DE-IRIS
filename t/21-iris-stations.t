#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;

use Test::More tests => 11;

BEGIN {
	use_ok('Travel::Status::DE::IRIS::Stations');
}
require_ok('Travel::Status::DE::IRIS::Stations');

my @emptypairs = grep { not( length( $_->[0] ) and length( $_->[1] ) ) }
  Travel::Status::DE::IRIS::Stations::get_stations;

is_deeply( \@emptypairs, [], 'no stations with empty code / name' );

is_deeply(
	[ [ 'EE', 'Essen Hbf' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('EE') ],
	'get_station: exact match by DS100 works'
);

is_deeply(
	[ [ 'EE', 'Essen Hbf' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('Essen Hbf') ],
	'get_station: exact match by name works'
);

is_deeply(
	[ [ 'EE', 'Essen Hbf' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('essen hbf') ],
	'get_station: exact match by name is case insensitive'
);

is_deeply(
	[ [ 'EEST', 'Essen-Steele' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('Essen-Steele') ],
	'get_station: exact match by name works by shortest prefix'
);

is_deeply(
	[ [ 'EEST', 'Essen-Steele' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('essen-steele') ],
	'get_station: exact match by name (shortest prefix) is case insensitive'
);

is_deeply(
	[ [ 'KM', 'M\'gladbach Hbf' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('mgladbach hbf') ],
	'get_station: close fuzzy match works (one result)'
);

is_deeply(
	[ [ 'KM', 'M\'gladbach Hbf' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('Mgladbach Bbf') ],
	'get_station: close fuzzy match is case insensitive'
);

is_deeply(
	[
		[ 'NKL',  'Kirchenlaibach' ],
		[ 'KM',   'M\'gladbach Hbf' ],
		[ 'XSRC', 'Reichenbach Kt' ]
	],
	[ Travel::Status::DE::IRIS::Stations::get_station('Moenchengladbach Hbf') ],
	'get_station: partial match works (several results for very fuzzy match)'
);
