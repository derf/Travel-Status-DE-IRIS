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
	qw(arrival date datetime delay departure line_no raw_id
	  route_start route_end
	  sched_arrival sched_departure
	  start stop_no time train_id train_no type unknown_t unknown_o)
);

sub new {
	my ( $obj, %opt ) = @_;

	my $ref = \%opt;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	my ( $train_id, $start_ts, $stop_no ) = split( /.\K-/, $opt{raw_id} );

	$ref->{start} = $strp->parse_datetime($start_ts);

	$ref->{train_id} = $train_id;
	$ref->{stop_no}  = $stop_no;

	my $ar = $ref->{arrival} = $ref->{sched_arrival}
	  = $strp->parse_datetime( $opt{arrival_ts} );
	my $dp = $ref->{departure} = $ref->{sched_departure}
	  = $strp->parse_datetime( $opt{departure_ts} );

	if ( not( $ar or $dp ) ) {
		cluck(
			sprintf(
				"Neither arrival '%s' nor departure '%s' are valid "
				  . "timestamps - can't handle this train",
				$opt{arrival_ts}, $opt{departure_ts}
			)
		);
	}

	my $dt = $ref->{datetime} = $ar // $dp;

	$ref->{date} = $dt->strftime('%d.%m.%Y');
	$ref->{time} = $dt->strftime('%H:%M');

	$ref->{route_pre} = $ref->{sched_route_pre}
	  = [ split( qr{\|}, $ref->{route_pre} // q{} ) ];
	$ref->{route_post} = $ref->{sched_route_post}
	  = [ split( qr{\|}, $ref->{route_post} // q{} ) ];

	$ref->{route_end} = $ref->{sched_route_end} = $ref->{route_post}[-1]
	  || $ref->{station};
	$ref->{route_start} = $ref->{sched_route_start} = $ref->{route_pre}[0]
	  || $ref->{station};

	return bless( $ref, $obj );
}

sub add_ar {
	my ( $self, %attrib ) = @_;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	if ( $attrib{arrival_ts} ) {
		$self->{arrival} = $strp->parse_datetime( $attrib{arrival_ts} );
		$self->{delay}
		  = $self->arrival->subtract_datetime( $self->sched_arrival )
		  ->in_units('minutes');
	}
}

sub add_dp {
	my ( $self, %attrib ) = @_;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	if ( $attrib{departure_ts} ) {
		$self->{departure} = $strp->parse_datetime( $attrib{departure_ts} );
		$self->{delay}
		  = $self->departure->subtract_datetime( $self->sched_departure )
		  ->in_units('minutes');
	}
}

sub add_tl {
	my ( $self, %attrib ) = @_;

	# TODO

	return $self;
}

sub origin {
	my ($self) = @_;

	return $self->route_start;
}

sub destination {
	my ($self) = @_;

	return $self->route_end;
}

sub line {
	my ($self) = @_;

	return
	  sprintf( '%s %s', $self->{type}, $self->{line_no} // $self->{train_no} );
}

sub route_pre {
	my ($self) = @_;

	return @{ $self->{route_pre} };
}

sub route_post {
	my ($self) = @_;

	return @{ $self->{route_post} };
}

sub route {
	my ($self) = @_;

	return ( $self->route_pre, $self->{station}, $self->route_post );
}

sub train {
	my ($self) = @_;

	return $self->line;
}

sub route_interesting {
	my ( $self, $max_parts ) = @_;

	my @via = $self->route_post;
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
