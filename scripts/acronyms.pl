#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;
use Encode qw(encode);
use Text::CSV;

say <<'EOF';
package Travel::Status::DE::IRIS::Stations;

use strict;
use warnings;
use 5.014;
use utf8;

use List::Util qw(min);
use List::UtilsBy qw(uniq_by);
use List::MoreUtils qw(firstval pairwise);
use Text::LevenshteinXS qw(distance);

# TODO switch to Text::Levenshtein::XS once AUR/Debian packages become available

our $VERSION = '1.05';

my @stations = (
EOF

my $csv = Text::CSV->new({binary => 1, sep_char => q{;}});
while (my $line = <STDIN>) {
#	chomp $line;
#	$line = decode('UTF-8', $line);

	my $status = $csv->parse($line);
	my @fields = $csv->fields;

	if ($fields[0] eq 'Abk') {
		next;
	}

	my ($station, $name, $country, $location, $valid_since) = @fields;

	$name =~ s{!}{ }g;
	$name =~ s{^\s+}{};
	$name =~ s{\s+$}{};
	$name =~ s{\s+}{ }g;
	$name =~ s{'}{\\'}g;

	printf("\t['%s','%s'],\n", encode('UTF-8', $station), encode('UTF-8', $name));
}

say <<'EOF';
);

sub get_stations {
	return @stations;
}

sub normalize {
	my ($val) = @_;

	$val =~ s{Ä}{Ae}g;
	$val =~ s{Ö}{Oe}g;
	$val =~ s{Ü}{Ue}g;
	$val =~ s{ä}{ae}g;
	$val =~ s{ö}{oe}g;
	$val =~ s{ß}{sz}g;
	$val =~ s{ü}{ue}g;

	return $val;
}

sub get_station {
	my ($name) = @_;

	my $ds100_match = firstval { $name eq $_->[0] } @stations;

	if ($ds100_match) {
		return ($ds100_match);
	}

	return get_station_by_name($name);
}

sub get_station_by_name {
	my ($name) = @_;

	my $nname = lc($name);
	my $actual_match = firstval { $nname eq lc( $_->[1] ) } @stations;

	if ($actual_match) {
		return ($actual_match);
	}

	$nname = normalize($nname);
	$actual_match = firstval { $nname eq normalize( lc( $_->[1] ) ) } @stations;
	if ($actual_match) {
		return ($actual_match);
	}

	my @distances   = map { distance( $nname, $_->[1] ) } @stations;
	my $min_dist    = min(@distances);
	my @station_map = pairwise { [ $a, $b ] } @stations, @distances;

	my @substring_matches = grep { $_->[1] =~ m{$name}i } @stations;
	my @levenshtein_matches
	  = map { $_->[0] } grep { $_->[1] == $min_dist } @station_map;

	return uniq_by { $_->[0] } ( @substring_matches, @levenshtein_matches );
}

1;

__END__

=head1 NAME

Travel::Status::DE::IRIS::Stations - Station name to station code mapping

=head1 SYNOPSIS

    use Travel::Status::DE::IRIS::Stations;

    my $name = 'Essen Hbf';
    my @stations = Travel::Status::DE::IRIS::Stations::get_station_by_name(
      $name);

    if (@stations < 1) {
      # no matching stations
    }
    elsif (@stations > 1) {
      # too many matches
    }
    else {
      printf("Input '%s' matched station code %s (as '%s')\n",
        $name, @{$stations[0]});
    }

=head1 VERSION

version 0.00

=head1 DESCRIPTION

This module contains a mapping of DeutscheBahn station names to station codes.
A station name is a (perhaps slightly abbreviated) string naming a particular
station; a station code is a two to five character denoting a station for the
IRIS web service.

Example station names (code in parentheses) are:
"Essen HBf" (EE), "Aachen Schanz" (KASZ), "Do UniversitE<auml>t" (EDUV).

B<Note:> Station codes may contain whitespace.

=head1 METHODS

=over

=item Travel::Status::DE::IRIS::get_stations

Returns a list of [station code, station name] listrefs lexically sorted by
station name.

=item Travel::Status::DE::IRIS::get_station(I<$in>)

Returns a list of [station code, station name] listrefs matching I<$in>.

If a I<$in> is a valid station code, only one element ([I<$in>, related name])
is returned. Otherwise, it is passed to get_station_by_name(I<$in>) (see
below).

Note that station codes matching is case sensitive and must be exact.

=item Travel::Status::DE::IRIS::get_station_by_name(I<$name>)

Returns a list of [station code, station name] listrefs where the station
name matches I<$name>.

Matching happens in two steps: If a case-insensitive exact match exists, only
this one is returned. Otherwise, all stations whose name contains I<$name> as
a substring (also case-insensitive) are returned.

This two-step behaviour makes sure that not prefix-free stations can still be
matched directly. For instance, both "Essen-Steele" and "Essen-Steele Ost"
are valid station names, but "essen-steele" will only return "Essen-Steele".

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item * List::MoreUtils(3pm)

=item * List::Util(3pm)

=item * Text::LevenshteinXS(3pm)

=back

=head1 BUGS AND LIMITATIONS

There is no support for intelligent whitespaces (to also match "-" and similar)
yet.

=head1 SEE ALSO

Travel::Status::DE::IRIS(3pm).

=head1 AUTHOR

Copyright (C) 2014-2015 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

EOF
