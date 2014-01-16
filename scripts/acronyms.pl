#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

my $re_line = qr{
	^
	(?<acronym> [A-Z]{2}[A-Z ]{0,3} )
	\s
	(?<name> .+)
	$
}x;

say <<'EOF';
package Travel::Status::DE::IRIS::Stations;

use strict;
use warnings;
use 5.014;
use utf8;

use List::MoreUtils qw(firstval);

our $VERSION = '0.00';

my @stations = (
EOF

while (my $line = <STDIN>) {
	chomp $line;

	if ($line =~ $re_line) {
		my ($station, $name) = @+{qw{acronym name}};
		$name =~ s{'}{\\'}g;

		printf("\t['%s','%s'],\n", $station, $name);
	}
}

say <<'EOF';
);

sub get_stations {
	return @stations;
}

sub get_station {
	my ( $name ) = @_;

	my $ds100_match = firstval { $name eq $_->[0] } @stations;

	if ($ds100_match) {
		return ($ds100_match);
	}

	return get_station_by_name($name);
}

sub get_station_by_name {
	my ( $name ) = @_;

	my $nname = lc($name);
	my $actual_match = firstval { $nname eq lc($_->[1]) } @stations;

	if ($actual_match) {
		return ($actual_match);
	}

	return ( grep { $_->[1] =~ m{$name}i } @stations );
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

=back

=head1 BUGS AND LIMITATIONS

There is no support for intelligent whitespaces (to also match "-" and similar)
yet.

=head1 SEE ALSO

Travel::Status::DE::IRIS(3pm).

=head1 AUTHOR

Copyright (C) 2014 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.

EOF
