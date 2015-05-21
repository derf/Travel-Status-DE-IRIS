#!/usr/bin/env perl
use strict;
use warnings;
use 5.014;
use utf8;

use Data::Dumper;
use DateTime;
use Test::More tests => 18;
use Test::Fatal;

use Travel::Status::DE::IRIS;

my $status = Travel::Status::DE::IRIS->new(
	iris_base => 'file:t/in',
	station   => 'EBO',
	datetime  => DateTime->new(
		year      => 2015,
		month     => 5,
		day       => 20,
		hour      => 17,
		minute    => 1,
		time_zone => 'Europe/Berlin'
	)
);

my @results = $status->results;

my $abr89476 = $results[22];
my $abr89536 = $results[21];
my $abr89473 = $results[33];
my $abr89533 = $results[34];

is($abr89476->train_no, 89476, 'train_no');
is($abr89536->train_no, 89536, 'train_no');

ok($abr89536->is_wing, 'is_wing');
ok(! $abr89476->is_wing, 'is_wing');
is(scalar $abr89536->arrival_wings, undef, 'wing has no wings');
is(scalar $abr89536->departure_wings, undef, 'wing has no wings');
is(scalar $abr89476->arrival_wings, 1, 'num arrival_wings');
is(scalar $abr89476->departure_wings, 1, 'num departure_wings');
is(($abr89476->departure_wings)[0]->train_no, 89536, 'departure_wings[0]');

is($abr89533->train_no, 89533, 'train_no');
is($abr89473->train_no, 89473, 'train_no');

ok($abr89473->is_wing, 'is_wing');
ok(! $abr89533->is_wing, 'is_wing');
is(scalar $abr89473->arrival_wings, undef, 'wing has no wings');
is(scalar $abr89473->departure_wings, undef, 'wing has no wings');
is(scalar $abr89533->arrival_wings, 1, 'num arrival_wings');
is(scalar $abr89533->departure_wings, 1, 'num departure_wings');
is(($abr89533->departure_wings)[0]->train_no, 89473, 'departure_wings[0]');
