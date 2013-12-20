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
	  departure_date departure_datetime departure_time line_no raw_id
	  start_date start_datetime start_time stop_no
	  time train_id train_no
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

Travel::Status::DE::IRIS::Result - Information about a single
arrival/departure received by Travel::Status::DE::IRIS

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

Travel::Status::DE::IRIs::Result describes a single arrival/departure
as obtained by Travel::Status::DE::IRIS.  It contains information about
the platform, time, route and more.

=head1 METHODS

=head2 ACCESSORS

=over

=item $result->arrival_date

=item $result->arrival_datetime

=item $result->arrival_time

=item $result->date

=item $result->datetime

=item $result->departure_date

=item $result->departure_datetime

=item $result->departure_time

=item $result->line_no

=item $result->raw_id

=item $result->start_date

=item $result->start_datetime

=item $result->start_time

=item $result->stop_no

=item $result->time

=item $result->train_id

=item $result->train_no

=item $result->type

=item $result->unknown_t

=item $result->unknown_o

=back

=head2 INTERNAL

=over

=item $result = Travel::Status::DE::IRIS::Result->new(I<%data>)

Returns a new Travel::Status::DE::IRIS::Result object.
You usually do not need to call this.

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

Travel::Status::DE::IRIS(3pm).

=head1 AUTHOR

Copyright (C) 2013 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
