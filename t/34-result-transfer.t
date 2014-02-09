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
	station   => 'EDG',
	datetime  => DateTime->new(
		year      => 2014,
		month     => 2,
		day       => 9,
		hour      => 20,
		minute    => 16,
		time_zone => 'Europe/Berlin'
	)
);

my @results = $status->results;

my $re2_a  = $results[13];

is($re2_a->train_no, '30030', 'transfer RE2: train_no is new no');
is($re2_a->old_train_no, '10230', 'transfer RE2: old_train_no is old no');
is($re2_a->train_id, '7760830705227608221', 'transfer RE2: train_id is new id');
is($re2_a->old_train_id, '5716084173145223820', 'transfer RE2: old_train_id is new id');
