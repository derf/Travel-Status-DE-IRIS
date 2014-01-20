#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;
use utf8;

use DateTime;
use Test::More tests => 10;
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
	[ $ice645->route ],
	[ $ice645->sched_route ],
	'route == sched_route'
);
is_deeply(
	[ $ice645->route_pre ],
	[ $ice645->sched_route_pre ],
	'route_pre == sched_route_pre'
);
is_deeply(
	[ $ice645->route_post ],
	[ $ice645->sched_route_post ],
	'route_post == sched_route_post'
);

is_deeply(
	[ $ice645->route ],
	[
		'Köln/Bonn Flughafen',
		'Köln Messe/Deutz Gl.11-12',
		'Düsseldorf Hbf',
		'Düsseldorf Flughafen',
		'Duisburg Hbf',
		'Essen Hbf',
		'Bochum Hbf',
		'Dortmund Hbf',
		'Hamm(Westf)',
		'Bielefeld Hbf',
		'Hannover Hbf',
		'Berlin-Spandau',
		'Berlin Hbf',
		'Berlin Ostbahnhof'
	],
	'route'
);
is_deeply(
	[ $ice645->route_pre ],
	[
		'Köln/Bonn Flughafen',
		'Köln Messe/Deutz Gl.11-12',
		'Düsseldorf Hbf',
		'Düsseldorf Flughafen',
		'Duisburg Hbf'
	],
	'route_pre'
);
is_deeply(
	[ $ice645->route_post ],
	[
		'Bochum Hbf',
		'Dortmund Hbf',
		'Hamm(Westf)',
		'Bielefeld Hbf',
		'Hannover Hbf',
		'Berlin-Spandau',
		'Berlin Hbf',
		'Berlin Ostbahnhof'
	],
	'route_post'
);

is_deeply([$ice645->route_interesting],
	['Bochum', 'Dortmund', 'Bielefeld'], 'route_interesting with just major');
is_deeply([$s1->route_interesting],
	[], 'route_interesting with realtime');
is_deeply([$s9->route_interesting],
	[], 'route_interesting, train ends here');
is_deeply([$abr->route_interesting],
	['Essen-Kray Süd', 'Bochum', 'Witten'], 'route_interesting with minor');
