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
use 5.018;
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
EOF
