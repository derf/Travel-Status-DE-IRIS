package Travel::Status::DE::IRIS::Result;

use strict;
use warnings;
use 5.010;
use utf8;

no if $] >= 5.018, warnings => "experimental::smartmatch";

use parent 'Class::Accessor';
use Carp qw(cluck);
use DateTime;
use DateTime::Format::Strptime;
use List::MoreUtils qw(uniq);

our $VERSION = '0.00';

sub translate_msg {
	my ( $self, $msg ) = @_;

	my %translation = (
		2  => 'Polizeiliche Ermittlung',
		3  => 'Feuerwehreinsatz neben der Strecke',
		5  => 'Ärztliche Versorgung eines Fahrgastes',
		7  => 'Personen im Gleis',
		8  => 'Notarzteinsatz am Gleis',
		10 => 'Ausgebrochene Tiere im Gleis',
		11 => 'Unwetter',
		15 => 'Beeinträchtigung durch Vandalismus',
		16 => 'Entschärfung einer Fliegerbombe',
		17 => 'Beschädigung einer Brücke',
		18 => 'Umgestürzter Baum im Gleis',
		19 => 'Unfall an einem Bahnübergang',
		20 => 'Tiere im Gleis',
		21 => 'Warten auf weitere Reisende',
		22 => 'Witterungsbedingte Störung',
		23 => 'Feuerwehreinsatz auf Bahngelände',
		24 => 'Verspätung aus dem Ausland',
		25 => 'Warten auf verspätete Zugteile',
		28 => 'Gegenstände im Gleis',
		31 => 'Bauarbeiten',
		32 => 'Verzögerung beim Ein-/Ausstieg',
		33 => 'Oberleitungsstörung',
		34 => 'Signalstörung',
		35 => 'Streckensperrung',
		36 => 'Technische Störung am Zug',
		38 => 'Technische Störung an der Strecke',
		39 => 'Anhängen von zusätzlichen Wagen',
		40 => 'Stellwerksstörung/-ausfall',
		41 => 'Störung an einem Bahnübergang',
		42 => 'Außerplanmäßige Geschwindigkeitsbeschränkung',
		43 => 'Verspätung eines vorausfahrenden Zuges',
		44 => 'Warten auf einen entgegenkommenden Zug',
		45 => 'Überholung durch anderen Zug',
		46 => 'Warten auf freie Einfahrt',
		47 => 'Verspätete Bereitstellung',
		48 => 'Verspätung aus vorheriger Fahrt',
		80 => 'Abweichende Wagenreihung',
		83 => 'Fehlender Zugteil',
		86 => 'Keine Reservierungsanzeige',
		90 => 'Kein Bordrestaurant/Bordbistro',
		91 => 'Keine Fahrradmitnahme',
		92 => 'Rollstuhlgerechtes WC in einem Wagen ausgefallen',
		93 => 'Kein rollstuhlgerechtes WC',
		98 => 'Kein rollstuhlgerechter Wagen',
		99 => 'Verzögerungen im Betriebsablauf',
	);

	return $translation{$msg} // "?($msg)";
}

Travel::Status::DE::IRIS::Result->mk_ro_accessors(
	qw(arrival date datetime delay departure line_no platform raw_id
	  realtime_xml route_start route_end
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

	my $dt = $ref->{datetime} = $dp // $ar;

	$ref->{date} = $dt->strftime('%d.%m.%Y');
	$ref->{time} = $dt->strftime('%H:%M');

	$ref->{route_pre} = $ref->{sched_route_pre}
	  = [ split( qr{\|}, $ref->{route_pre} // q{} ) ];
	$ref->{route_post} = $ref->{sched_route_post}
	  = [ split( qr{\|}, $ref->{route_post} // q{} ) ];

	$ref->{route_pre_incomplete}  = $ref->{route_end}  ? 1 : 0;
	$ref->{route_post_incomplete} = $ref->{route_post} ? 1 : 0;

	$ref->{route_end}
	  = $ref->{sched_route_end}
	  = $ref->{route_end}
	  || $ref->{route_post}[-1]
	  || $ref->{station};
	$ref->{route_start}
	  = $ref->{sched_route_start}
	  = $ref->{route_start}
	  || $ref->{route_pre}[0]
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

sub add_messages {
	my ( $self, %messages ) = @_;

	$self->{messages} = \%messages;
}

sub add_realtime {
	my ( $self, $xmlobj ) = @_;

	$self->{realtime_xml} = $xmlobj;
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

sub info {
	my ($self) = @_;

	my @messages = sort keys %{ $self->{messages} };
	my @ids = uniq( map { $self->{messages}{$_}->[2] } @messages );

	my @info = map { $self->translate_msg($_) } @ids;

	return @info;
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
	$last_stop
	  = $self->{route_post_incomplete} ? $self->{route_end} : pop(@via);

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

=head1 MESSAGES

A dump of all messages entered for the result is available. Each message
consists of a timestamp (when it was entered), a type (d for delay reasons,
q for other train-related information) and a value (numeric ID).

At the time of this writing, the following messages are known:

=over

=item d  2 : "Polizeiliche Ermittlung"

=item d  3 : "Feuerwehreinsatz neben der Strecke"

=item d  5 : "E<Auml>rztliche Versorgung eines Fahrgastes"

=item d  7 : "Personen im Gleis"

=item d  8 : "Notarzteinsatz am Gleis"

=item d 10 : "Ausgebrochene Tiere im Gleis"

=item d 11 : "Unwetter"

=item d 15 : "BeeintrE<auml>chtigung durch Vandalismus"

=item d 16 : "EntschE<auml>rfung einer Fliegerbombe"

=item d 17 : "BeschE<auml>digung einer BrE<uuml>cke"

=item d 18 : "UmgestE<uuml>rzter Baum im Gleis"

=item d 19 : "Unfall an einem BahnE<uuml>bergang"

=item d 20 : "Tiere im Gleis"

=item d 21 : "Warten auf weitere Reisende"

=item d 22 : "Witterungsbedingte StE<ouml>rung"

=item d 23 : "Feuerwehreinsatz auf BahngelE<auml>nde"

=item d 24 : "VerspE<auml>tung aus dem Ausland"

=item d 25 : "Warten auf verspE<auml>tete Zugteile"

=item d 28 : "GegenstE<auml>nde im Gleis"

=item d 31 : "Bauarbeiten"

=item d 32 : "VerzE<ouml>gerung beim Ein-/Ausstieg"

=item d 33 : "OberleitungsstE<ouml>rung"

=item d 34 : "SignalstE<ouml>rung"

=item d 35 : "Streckensperrung"

=item d 36 : "Technische StE<ouml>rung am Zug"

=item d 38 : "Technische StE<ouml>rung an der Strecke"

=item d 39 : "AnhE<auml>ngen von zusE<auml>tzlichen Wagen"

=item d 40 : "StellwerksstE<ouml>rung/-ausfall"

=item d 41 : "StE<ouml>rung an einem BahnE<uuml>bergang"

=item d 42 : "AuE<szlig>erplanmE<auml>E<szlig>ige GeschwindigkeitsbeschrE<auml>nkung"

=item d 43 : "VerspE<auml>tung eines vorausfahrenden Zuges"

=item d 44 : "Warten auf einen entgegenkommenden Zug"

=item d 45 : "E<Uuml>berholung durch anderen Zug"

=item d 46 : "Warten auf freie Einfahrt"

=item d 47 : "VerspE<auml>tete Bereitstellung"

=item d 48 : "VerspE<auml>tung aus vorheriger Fahrt"

=item q 80 : "Abweichende Wagenreihung"

=item q 83 : "Fehlender Zugteil"

=item q 86 : "Keine Reservierungsanzeige"

=item q 90 : "Kein Bordrestaurant/Bordbistro"

=item q 91 : "Keine Fahrradmitnahme"

=item q 92 : "Rollstuhlgerechtes WC in einem Wagen ausgefallen"

=item q 93 : "Kein rollstuhlgerechtes WC"

=item q 98 : "Kein rollstuhlgerechter Wagen"

=item d 99 : "VerzE<ouml>gerungen im Betriebsablauf"

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
