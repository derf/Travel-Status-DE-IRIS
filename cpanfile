requires 'Cache::File';
requires 'Carp';
requires 'Class::Accessor';
requires 'DateTime';
requires 'DateTime::Format::Strptime';
requires 'Encode';
requires 'Geo::Distance';
requires 'Getopt::Long';
requires 'List::Compare' => '0.29',
requires 'List::MoreUtils';
requires 'List::Util';
requires 'List::UtilsBy';
requires 'LWP::UserAgent';
requires 'Text::LevenshteinXS';
requires 'XML::LibXML';

on test => sub {
	 requires 'File::Slurp';
	 requires 'JSON';
	 requires 'Test::Compile';
	 requires 'Test::Fatal';
	 requires 'Test::More';
	 requires 'Test::Number::Delta';
	 requires 'Test::Pod';
	 requires 'Text::CSV';
};
