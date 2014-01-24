#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

Module::Build->new(

	build_requires => {
		'Test::Compile' => 0,
		'Test::Fatal' => 0,
		'Test::More' => 0,
		'Test::Pod' => 0,
	},
	configure_requires => {
		'Module::Build' => 0.40,
	},
	module_name => 'Travel::Status::DE::IRIS',
	license => 'perl',
	requires => {
		'perl' => '5.14.2',
		'Carp' => 0,
		'Class::Accessor' => 0,
		'DateTime' => 0,
		'DateTime::Format::Strptime' => 0,
		'Encode' => 0,
		'Getopt::Long' => 0,
		'List::MoreUtils' => 0,
		'List::Util' => 0,
		'LWP::UserAgent' => 0,
		'XML::LibXML' => 0,
	},
	sign => 1,

)->create_build_script();
