package Travel::Status::DE::IRIS::Result;

use strict;
use warnings;
use 5.010;

no if $] >= 5.018, warnings => "experimental::smartmatch";

use parent 'Class::Accessor';
use Carp qw(cluck);
use DateTime;
use DateTime::Format::Strptime;

our $VERSION = '0.00';

Travel::Status::DE::IRIS::Result->mk_ro_accessors(
	qw(arrival_date arrival_datetime arrival_time date datetime
	  departure_date departure_datetime departure_time line_no
	  start_date start_datetime start_time stop_no
	  raw_id stop_no time train_id train_no
	  type unknown_t unknown_o)
);

sub new {
	my ( $obj, %opt ) = @_;

	my $ref = \%opt;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	my ( $train_id, $start_ts, $stop_no ) = split( /.\K-/, $opt{raw_id} );

	$ref->{start_datetime} = $strp->parse_datetime($start_ts);
	$ref->{start_date}     = $ref->{start_datetime}->strftime('%d.%m.%Y');
	$ref->{start_time}     = $ref->{start_datetime}->strftime('%H:%M');

	$ref->{train_id} = $train_id;
	$ref->{stop_no}  = $stop_no;

	$ref->{arrival_datetime}   = $strp->parse_datetime( $opt{arrival_ts} );
	$ref->{departure_datetime} = $strp->parse_datetime( $opt{departure_ts} );

	if ( not( $ref->{arrival_datetime} or $ref->{departure_datetime} ) ) {
		cluck(
			sprintf(
				"Neither '%s' nor '%s' are valid timestamps",
				$opt{arrival_ts}, $opt{departure_ts}
			)
		);
	}

	if ( $ref->{arrival_datetime} ) {
		my $dt = $ref->{datetime} = $ref->{arrival_datetime};
		$ref->{arrival_date} = $ref->{date} = $dt->strftime('%d.%m.%Y');
		$ref->{arrival_time} = $ref->{time} = $dt->strftime('%H:%M');
	}
	if ( $ref->{departure_datetime} ) {
		my $dt = $ref->{datetime} = $ref->{departure_datetime};
		$ref->{departure_date} = $ref->{date} = $dt->strftime('%d.%m.%Y');
		$ref->{departure_time} = $ref->{time} = $dt->strftime('%H:%M');
	}

	return bless( $ref, $obj );
}

sub destination {
	my ($self) = @_;

	return $self->{route_end};
}

sub line {
	my ($self) = @_;

	return $self->{train};
}

sub origin {
	my ($self) = @_;

	return $self->{route_end};
}

sub route_interesting {
	my ( $self, $max_parts ) = @_;

	my @via = $self->route;
	my ( @via_main, @via_show, $last_stop );
	$max_parts //= 3;

	for my $stop (@via) {
		if ( $stop =~ m{ ?Hbf}o ) {
			push( @via_main, $stop );
		}
	}
	$last_stop = pop(@via);

	if ( @via_main and $via_main[-1] eq $last_stop ) {
		pop(@via_main);
	}

	if ( @via_main and @via and $via[0] eq $via_main[0] ) {
		shift(@via_main);
	}

	if ( @via < $max_parts ) {
		@via_show = @via;
	}
	else {
		if ( @via_main >= $max_parts ) {
			@via_show = ( $via[0] );
		}
		else {
			@via_show = splice( @via, 0, $max_parts - @via_main );
		}

		while ( @via_show < $max_parts and @via_main ) {
			my $stop = shift(@via_main);
			if ( $stop ~~ \@via_show or $stop eq $last_stop ) {
				next;
			}
			push( @via_show, $stop );
		}
	}

	for (@via_show) {
		s{ ?Hbf}{};
	}

	return @via_show;

}

sub route_timetable {
	my ($self) = @_;

	return @{ $self->{route} };
}

sub TO_JSON {
	my ($self) = @_;

	return { %{$self} };
}

1;

__END__

=head1 NAME

Travel::Status::DE::DeutscheBahn::Result - Information about a single
arrival/departure received by Travel::Status::DE::DeutscheBahn

=head1 SYNOPSIS

	for my $departure ($status->results) {
		printf(
			"At %s: %s to %s from platform %s\n",
			$departure->time,
			$departure->line,
			$departure->destination,
			$departure->platform,
		);
	}

	# or (depending on module setup)
	for my $arrival ($status->results) {
		printf(
			"At %s: %s from %s on platform %s\n",
			$arrival->time,
			$arrival->line,
			$arrival->origin,
			$arrival->platform,
		);
	}

=head1 VERSION

version 1.02

=head1 DESCRIPTION

Travel::Status::DE::DeutscheBahn::Result describes a single arrival/departure
as obtained by Travel::Status::DE::DeutscheBahn.  It contains information about
the platform, time, route and more.

=head1 METHODS

=head2 ACCESSORS

=over

=item $result->date

Arrival/Departure date in "dd.mm.yyyy" format.

=item $result->delay

Returns the train's delay in minutes, or undef if it is unknown.

=item $result->info

Returns additional information, for instance the reason why the train is
delayed. May be an empty string if no (useful) information is available.

=item $result->line

=item $result->train

Returns the line name, either in a format like "S 1" (S-Bahn line 1)
or "RE 10111" (RegionalExpress train 10111, no line information).

=item $result->platform

Returns the platform from which the train will depart / at which it will
arrive.

=item $result->route

Returns a list of station names the train will pass between the selected
station and its origin/destination.

=item $result->route_end

Returns the last element of the route.  Depending on how you set up
Travel::Status::DE::DeutscheBahn (arrival or departure listing), this is
either the train's destination or its origin station.

=item $result->destination

=item $result->origin

Convenience aliases for $result->route_end.

=item $result->route_interesting([I<max>])

Returns a list of up to I<max> (default: 3) interesting stations the train
will pass on its journey. Since deciding whether a station is interesting or
not is somewhat tricky, this feature should be considered experimental.

The first element of the list is always the train's next stop. The following
elements contain as many main stations as possible, but there may also be
smaller stations if not enough main stations are available.

In future versions, other factors may be taken into account as well.  For
example, right now airport stations are usually not included in this list,
although they should be.

Note that all main stations will be stripped of their "Hbf" suffix.

=item $result->route_raw

Returns the raw string used to create the route array.

Note that canceled stops are filtered from B<route>, but still present in
B<route_raw>.

=item $result->route_timetable

Similar to B<route>.  however, this function returns a list of array
references of the form C<< [ arrival time, station name ] >>.

=item $result->time

Returns the arrival/departure time as string in "hh:mm" format.

=back

=head2 INTERNAL

=over

=item $result = Travel::Status::DE::DeutscheBahn::Result->new(I<%data>)

Returns a new Travel::Status::DE::DeutscheBahn::Result object.
You usually do not need to call this.

Required I<data>:

=over

=item B<time> => I<hh:mm>

=item B<train> => I<string>

=item B<route_raw> => I<string>

=item B<route> => I<arrayref>

=item B<route_end> => I<string>

=item B<platform> => I<string>

=item B<info_raw> => I<string>

=back

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item Class::Accessor(3pm)

=back

=head1 BUGS AND LIMITATIONS

None known.

=head1 SEE ALSO

Travel::Status::DE::DeutscheBahn(3pm).

=head1 AUTHOR

Copyright (C) 2011 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
