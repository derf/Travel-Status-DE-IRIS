#!/usr/bin/env perl

use strict;
use warnings;
use Module::Build;

Module::Build->new(

	build_requires => {
		'File::Slurp' => 9999.19,
		'JSON' => 0,
		'Test::Compile' => 0,
		'Test::Fatal' => 0,
		'Test::More' => 0,
		'Test::Number::Delta' => 0,
		'Test::Pod' => 0,
		'Text::CSV' => 0,
	},
	configure_requires => {
		'Module::Build' => 0.40,
	},
	module_name => 'Travel::Status::DE::IRIS',
	license => 'perl',
	recommends => {
		'Cache::File' => 0,
	},
	requires => {
		'perl' => '5.14.2',
		'Carp' => 0,
		'Class::Accessor' => 0,
		'DateTime' => 0,
		'DateTime::Format::Strptime' => 0,
		'Encode' => 0,
		'Geo::Distance' => '!= 0.21',
		'Getopt::Long' => 0,
		'List::Compare' => '0.29',
		'List::MoreUtils' => 0,
		'List::Util' => 0,
		'List::UtilsBy' => 0,
		'LWP::UserAgent' => 0,
		'LWP::Protocol::https' => 0,
		'Text::LevenshteinXS' => 0,
		'XML::LibXML' => 0,
	},
	sign => 1,
    meta_merge => {
        resources => {
            repository => 'https://github.com/derf/Travel-Status-DE-IRIS'
        }
    },

)->create_build_script();
