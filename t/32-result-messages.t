#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;
use utf8;

use DateTime;
use Test::More tests => 4;
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

my @results = $status->results;

my $ice645 = $results[0];
my $s1     = $results[1];
my $s9     = $results[8];
my $hkx    = $results[10];
my $abr    = $results[13];

is_deeply(
	[ $ice645->info ],
	[ 'Witterungsbedingte Störung', 'Unwetter', 'Abweichende Wagenreihung' ],
	'info: no dups, sorted, msg+qos'
);

is_deeply(
	[ $ice645->messages ],
	[
		[ '2014-01-03T20:02:00', 'Abweichende Wagenreihung' ],
		[ '2014-01-03T20:01:00', 'Unwetter' ],
		[ '2014-01-03T20:00:00', 'Witterungsbedingte Störung' ],
		[ '2014-01-03T19:59:00', 'Witterungsbedingte Störung' ],
		[ '2014-01-03T19:58:00', 'Witterungsbedingte Störung' ],
		[ '2014-01-03T19:48:00', 'Witterungsbedingte Störung' ],
		[ '2014-01-03T19:15:00', 'Witterungsbedingte Störung' ],
		[ '2014-01-03T19:03:00', 'Witterungsbedingte Störung' ]
	],
	'messages: with dups'
);

is_deeply(
	[ $ice645->qos_messages ],
	[ [ '2014-01-03T20:02:00', 'Abweichende Wagenreihung' ] ],
	'qos_messages'
);

is_deeply(
	[ $ice645->delay_messages ],
	[
		[ '2014-01-03T20:01:00', 'Unwetter' ],
		[ '2014-01-03T20:00:00', 'Witterungsbedingte Störung' ]
	],
	'delay_messages: no dups'
);
