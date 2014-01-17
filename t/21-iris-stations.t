#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;

use DateTime;
use Test::More tests => 10;

BEGIN {
	use_ok('Travel::Status::DE::IRIS::Stations');
}
require_ok('Travel::Status::DE::IRIS::Stations');

is_deeply(
	[],
	[ Travel::Status::DE::IRIS::Stations::get_station('doesnotexist') ],
	'get_station: returns empty list for no match'
);

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
	[ [ 'EG', 'Gelsenk Hbf' ], [ 'EGZO', 'Gelsenk Zoo' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('Gelsenk') ],
	'get_station: partial match by name works'
);

is_deeply(
	[ [ 'EG', 'Gelsenk Hbf' ], [ 'EGZO', 'Gelsenk Zoo' ] ],
	[ Travel::Status::DE::IRIS::Stations::get_station('gelsenk') ],
	'get_station: partial match by name is case insensitive'
);
