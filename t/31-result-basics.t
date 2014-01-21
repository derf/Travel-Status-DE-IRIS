#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;
use utf8;

use DateTime;
use Test::More tests => 435;
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

is(@results, 135, 'got 135 results');

my $ice645 = $results[0];
my $s1 = $results[1];


# Generic checks: All accessors should work

isa_ok($ice645->arrival, 'DateTime');
isa_ok($ice645->datetime, 'DateTime');
isa_ok($ice645->departure, 'DateTime');
isa_ok($ice645->sched_arrival, 'DateTime');
isa_ok($ice645->sched_departure, 'DateTime');
isa_ok($ice645->start, 'DateTime');
is($ice645->datetime, $ice645->sched_departure, 'datetime is sched_departure');
is_deeply(['F'], [$ice645->classes], '->classes');
is($ice645->date, '03.01.2014', '->date');
is($ice645->delay, 53, '->delay');
is($ice645->destination, 'Berlin Ostbahnhof', '->destination');
ok(! $ice645->is_cancelled, '->is_cancelled for non-cancelled train');
is($ice645->line, 'ICE 645', '->line');
is($ice645->line_no, undef, '->line_no');
is($ice645->origin, 'Köln/Bonn Flughafen', '->origin');
is($ice645->platform, 4, '->platform');
is($ice645->raw_id, '1065350279715650378-1401031812-6', '->raw_id');
is($ice645->route_end, 'Berlin Ostbahnhof', '->routd_end');
is($ice645->route_start, 'Köln/Bonn Flughafen', '->routd_start');
is($ice645->sched_route_end, 'Berlin Ostbahnhof', '->sched_route_end');
is($ice645->sched_route_start, 'Köln/Bonn Flughafen', '->sched_routd_start');
is($ice645->stop_no, 6, '->stop_no');
is($ice645->time, '19:23', '->time');
is($ice645->train, 'ICE 645', '->train');
is($ice645->train_id, '1065350279715650378', '->train_id');
is($ice645->train_no, 645, '->train_no');
is($ice645->type, 'ICE', '->type');

ok($s1->is_cancelled, '->is_cancelled for cancelled train');

# documented aliases should work on all results
for my $i (0 .. $#results) {
	my $r = $results[$i];
	is($r->origin, $r->route_start, "results[$i]: origin == route_start");
	is($r->destination, $r->route_end, "results[$i]: destination == routd_end");
	is($r->train, $r->line, "results[$i]: line == train");
}

$status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'EE',
	datetime  => DateTime->new(
		year      => 2014,
		month     => 1,
		day       => 5,
		hour      => 20,
		minute    => 1,
		time_zone => 'Europe/Berlin'
	)
);

@results = $status->results;

is(@results, 0, 'no data available -> empty result list');
