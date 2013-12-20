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
package Travel::Status::DE::IRIS::Acronyms;

use strict;
use warnings;
use 5.010;
use utf8;

our $VERSION = '0.00';

my @acronyms = (
EOF

while (my $line = <STDIN>) {
	chomp $line;

	if ($line =~ $re_line) {
		my ($acronym, $name) = @+{qw{acronym name}};
		$name =~ s{'}{\\'}g;

		printf("\t['%s','%s'],\n", $acronym, $name);
	}
}

say <<'EOF';
);

sub get_acronyms {
	return @acronyms;
}

1;
EOF
