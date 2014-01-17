#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;

use DateTime;
use Test::More tests => 274;

BEGIN {
	use_ok('Travel::Status::DE::IRIS');
}
require_ok('Travel::Status::DE::IRIS');

my $status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'EE',
	datetime  => DateTime->new(
		year   => 2014,
		month  => 1,
		day    => 3,
		hour   => 20,
		minute => 1,
		time_zone => 'Europe/Berlin',
	)
);

isa_ok( $status, 'Travel::Status::DE::IRIS' );
can_ok( $status, qw(errstr results) );

for my $result ( $status->results ) {
	isa_ok( $result, 'Travel::Status::DE::IRIS::Result' );
	can_ok(
		$result, qw(
		  arrival classes date datetime delay departure is_cancelled line_no
		  platform raw_id realtime_xml route_start route_end sched_arrival
		  sched_departure sched_route_start sched_route_end start stop_no time
		  train_id train_no type unknown_t unknown_o
		  origin destination delay_messages qos_messages messages
		  info line route_pre route_post route train route_interesting
		  sched_route_pre sched_route_post sched_route TO_JSON)
	);
}
