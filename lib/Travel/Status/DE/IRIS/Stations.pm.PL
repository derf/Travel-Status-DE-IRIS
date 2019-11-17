#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;
use utf8;
use File::Slurp qw(read_file write_file);
use JSON;

my $json_str = read_file('share/stations.json');
my $stations = JSON->new->utf8->decode($json_str);

my $buf = <<'EOF';
package Travel::Status::DE::IRIS::Stations;

# vim:readonly
# This module has been automatically generated from share/stations.json
# by lib/Travel/Status/DE/IRIS/Stations.pm.PL.
# Do not edit, changes will be lost.

use strict;
use warnings;
use 5.014;
use utf8;

use Geo::Distance;
use List::Util qw(min);
use List::UtilsBy qw(uniq_by);
use List::MoreUtils qw(firstval pairwise);
use Text::LevenshteinXS qw(distance);

# TODO Geo::Distance is kinda deprecated, it is recommended to use GIS::Distance
# instead. However, since GIS::Distance is not packaged for Debian, I'll stick
# with Geo::Distance for now (which works fine enough here)

# TODO switch to Text::Levenshtein::XS once AUR/Debian packages become available

our $VERSION = '1.35';

# Automatically generated, see share/stations.json
my @stations = (
EOF

for my $station (@{$stations}) {
	if ($station->{latlong}) {
		$buf .= sprintf(
			"['%s','%s',%s,%s,%s],\n",
			$station->{ds100},
			$station->{name},
			$station->{uic},
			$station->{latlong}[1],
			$station->{latlong}[0],
		);
	}
	else {
		$buf .= sprintf(
			"['%s','%s',%s],\n",
			$station->{ds100},
			$station->{name},
			$station->{uic}
		);
	}
}

$buf .= <<'EOF';
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

	my $eva_match = firstval { defined $_->[2] and $name eq $_->[2] } @stations;

	if ($eva_match) {
		return ($eva_match);
	}

	return get_station_by_name($name);
}

sub get_station_by_location {
	my ( $lon, $lat, $num_matches ) = @_;

	$num_matches //= 10;

	my $geo = Geo::Distance->new();

	# we only use geolocations inside germany.
	# For these, this fast preprocessing step will let through all
	# coordinates inside a 60km radius (and a bunch which are farther out)
	my @candidates = grep {
		      $#{$_} >= 4
		  and abs( $_->[3] - $lon ) < 1
		  and abs( $_->[4] - $lat )
		  < 1
	} @stations;
	my @distances
	  = map { $geo->distance( 'kilometer', $lon, $lat, $_->[3], $_->[4] ) }
	  @candidates;
	my @station_map = pairwise { [ $a, $b ] } @candidates, @distances;

	@station_map = sort { $a->[1] <=> $b->[1] } @station_map;
	splice( @station_map, $num_matches );

	return @station_map;
}

sub get_station_by_name {
	my ($name) = @_;

	my $nname        = lc($name);
	my $actual_match = firstval { $nname eq lc( $_->[1] ) } @stations;

	if ($actual_match) {
		return ($actual_match);
	}

	$nname        = normalize($nname);
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

version 1.09

=head1 DESCRIPTION

This module contains a list of Deutsche Bahn stations, and also some stations
outside of Germany which are served by Deutsche Bahn trains. It offers
several accessors to look up stations based on names or geolocation data and
can also simply dump all known stations.

Each of the following methods returns a list of array references. Each
array reference describes a single station and contains either two or
five elements:

=over

=item * Station code (also known as DS100 / "Druckschrift 100" /
"Richtlinie 100"). A short string used exclusively by Deutsche Bahn APIs. Note
that it may contain space characters.

=item * Station name

=item * International station number (UIC number / IBNR, "Internationale Bahnhofsnummer")

=item * Station longitude, if available

=item * Station latitude, if available

=back

=head1 METHODS

=over

=item Travel::Status::DE::IRIS::Stations::get_stations

Returns a list of all known stations, lexically sorted by station name.

=item Travel::Status::DE::IRIS::Stations::get_station(I<$in>)

Returns a list of stations matching I<$in>.

If a I<$in> is a valid station (either DS100 code or UIC/EVA number),
a single array reference describing the station is returned. Otherwise,
I<$in> is passed to get_station_by_name(I<$in>) (see below).

Note that DS100 code matching is case sensitive.

=item Travel::Status::DE::IRIS::Stations::get_station_by_location(I<$lon>, I<$lat>, I<$num_matches>)

Looks for stations which are close to longitude/latitude I<$lon>/I<$lat> and
returns the closest I<$num_matches> (defaults to 10) matches. Note that
stations which are located more than 70 kilometers away from I<$lon>/I<$lat>
may be ignored when computing the closest matches.

Note that location-based lookup is only supported for stations inside Germany,
since the station list data source does not provide geolocation data for
non-german stations.

=item Travel::Status::DE::IRIS::Stations::get_station_by_name(I<$name>)

Returns a list of stations where the station name matches I<$name>.

Matching happens in two steps: If a case-insensitive exact match exists, only
this one is returned. Otherwise, all stations whose name contains I<$name> as
a substring (also case-insensitive) and all stations whose name has a low
Levenshtein distance to I<$name> are returned.

This two-step behaviour makes sure that not-prefix-free stations can still be
matched directly. For instance, both "Essen-Steele" and "Essen-Steele Ost"
are valid station names, but "essen-steele" will only return "Essen-Steele".

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item * Geo::Distance(3pm)

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

Station data: Copyright (C) 2016 by DB Station&Service AG, Europaplatz 1, 10557 Berlin, Germany

Lookup code: Copyright (C) 2014-2019 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself. Note that the
station data used by this module is also available under a CC-BY 4.0 license on
L<http://data.deutschebahn.com/dataset/data-haltestellen>.
EOF

write_file($ARGV[0], {binmode => ':utf8'}, $buf);