#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;

use DateTime;
use Test::More tests => 5;
use Test::Fatal;

use Travel::Status::DE::IRIS;

my $status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'EE',
	datetime  => DateTime->new(
		year      => 2014,
		month     => 1,
		day       => 3,
		hour      => 20,
		minute    => 1,
		time_zone => 'Europe/Berlin'
	)
);

is( $status->errstr, undef, 'constructor with data for everything' );

$status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'EE',
	datetime  => DateTime->new(
		year      => 2014,
		month     => 1,
		day       => 3,
		hour      => 19,
		minute    => 1,
		time_zone => 'Europe/Berlin'
	)
);

ok( defined $status->warnstr, 'constructor with missing data has warnstr' );

$status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'doesnotexist',
	datetime  => DateTime->new(
		year      => 2014,
		month     => 1,
		day       => 3,
		hour      => 19,
		minute    => 1,
		time_zone => 'Europe/Berlin'
	)
);

ok( defined $status->errstr, 'constructor with imaginary station has errstr' );

$status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'EBILP',
	datetime  => DateTime->new(
		year      => 2014,
		month     => 1,
		day       => 3,
		hour      => 20,
		minute    => 1,
		time_zone => 'Europe/Berlin'
	)
);

like(
	$status->errstr,
	qr{no associated timetable},
	'constructor with bad station has errstr'
);

ok(
	exception {
		$status = Travel::Status::DE::IRIS->new( iris_base => 'file:t/in' );
	},
	'station parameter is mandatory -> code dies if missing'
);
