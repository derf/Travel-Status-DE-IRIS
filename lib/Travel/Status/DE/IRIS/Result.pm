package Travel::Status::DE::IRIS::Result;

use strict;
use warnings;
use 5.014;
use utf8;

no if $] >= 5.018, warnings => 'experimental::smartmatch';

use parent 'Class::Accessor';
use Carp qw(cluck);
use DateTime;
use DateTime::Format::Strptime;
use List::MoreUtils qw(none uniq firstval);

our $VERSION = '0.04';

Travel::Status::DE::IRIS::Result->mk_ro_accessors(
	qw(arrival classes date datetime delay departure is_cancelled is_transfer
	  line_no train_no_transfer old_train_id old_train_no platform raw_id
	  realtime_xml route_start route_end sched_arrival sched_departure
	  sched_platform sched_route_start sched_route_end start stop_no time
	  train_id train_no transfer type unknown_t unknown_o)
);

sub new {
	my ( $obj, %opt ) = @_;

	my $ref = \%opt;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	my ( $train_id, $start_ts, $stop_no ) = split( /.\K-/, $opt{raw_id} );

	$train_id =~ s{^-}{};

	$ref->{start} = $strp->parse_datetime($start_ts);

	$ref->{train_id} = $train_id;
	$ref->{stop_no}  = $stop_no;

	if ( $opt{transfer} ) {
		my ($transfer) = split( /.\K-/, $opt{transfer} );
		$transfer =~ s{^-}{};
		$ref->{transfer} = $transfer;
	}

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
	  = [ split( qr{[|]}, $ref->{route_pre} // q{} ) ];
	$ref->{route_post} = $ref->{sched_route_post}
	  = [ split( qr{[|]}, $ref->{route_post} // q{} ) ];

	$ref->{route_pre_incomplete}  = $ref->{route_end}  ? 1 : 0;
	$ref->{route_post_incomplete} = $ref->{route_post} ? 1 : 0;

	$ref->{sched_platform} = $ref->{platform};
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

	$ref->{is_cancelled} = 0;

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

	if ( $attrib{platform} ) {
		$self->{platform} = $attrib{platform};
	}

	if ( $attrib{route_pre} ) {
		$self->{route_pre} = [ split( qr{[|]}, $attrib{route_pre} // q{} ) ];
		$self->{route_start} = $self->{route_pre}[0];
	}

	if ( $attrib{status} and $attrib{status} eq 'c' ) {
		$self->{is_cancelled} = 1;
	}

	return $self;
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

	if ( $attrib{platform} ) {
		$self->{platform} = $attrib{platform};
	}

	if ( $attrib{route_post} ) {
		$self->{route_post} = [ split( qr{[|]}, $attrib{route_post} // q{} ) ];
		$self->{route_end} = $self->{route_post}[-1];
	}

	if ( $attrib{status} and $attrib{status} eq 'c' ) {
		$self->{is_cancelled} = 1;
	}

	return $self;
}

sub add_messages {
	my ( $self, %messages ) = @_;

	$self->{messages} = \%messages;

	return $self;
}

sub add_realtime {
	my ( $self, $xmlobj ) = @_;

	$self->{realtime_xml} = $xmlobj;

	return $self;
}

sub add_ref {
	my ( $self, %attrib ) = @_;

	$self->{train_no_transfer} = $attrib{train_no};

	# TODO

	return $self;
}

sub add_tl {
	my ( $self, %attrib ) = @_;

	# TODO

	return $self;
}

sub merge_with_departure {
	my ( $self, $result ) = @_;

	# result must be departure-only

	$self->{is_transfer} = 1;

	$self->{old_train_id} = $self->{train_id};
	$self->{old_train_no} = $self->{train_no};

	# departure is preferred over arrival, so overwrite default values
	$self->{date}     = $result->{date};
	$self->{time}     = $result->{time};
	$self->{datetime} = $result->{datetime};
	$self->{train_id} = $result->{train_id};
	$self->{train_no} = $result->{train_no};

	$self->{departure}        = $result->{departure};
	$self->{departure_wings}  = $result->{departure_wings};
	$self->{route_end}        = $result->{route_end};
	$self->{route_post}       = $result->{route_post};
	$self->{sched_departure}  = $result->{sched_departure};
	$self->{sched_route_post} = $result->{sched_route_post};

	# update realtime info only if applicable
	$self->{is_cancelled} ||= $result->{is_cancelled};

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

sub delay_messages {
	my ($self) = @_;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	my @keys   = reverse sort keys %{ $self->{messages} };
	my @msgs   = grep { $_->[1] eq 'd' } map { $self->{messages}{$_} } @keys;
	my @msgids = uniq( map { $_->[2] } @msgs );
	my @ret;

	for my $id (@msgids) {
		my $msg = firstval { $_->[2] == $id } @msgs;
		push( @ret,
			[ $strp->parse_datetime( $msg->[0] ), $self->translate_msg($id) ] );
	}

	return @ret;
}

sub qos_messages {
	my ($self) = @_;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	my @keys = sort keys %{ $self->{messages} };
	my @msgs = grep { $_->[1] eq 'q' } map { $self->{messages}{$_} } @keys;
	my @ret;

	for my $msg (@msgs) {
		if ( my @superseded = $self->superseded_messages( $msg->[2] ) ) {
			@ret = grep { not( $_->[2] ~~ \@superseded ) } @ret;
		}
		@ret = grep { $_->[2] != $msg->[2] } @ret;

		# 88 is "no qos shortcomings" and only required to filter previous
		# qos messages
		if ( $msg->[2] != 88 ) {
			push( @ret, $msg );
		}
	}

	@ret = map {
		[ $strp->parse_datetime( $_->[0] ), $self->translate_msg( $_->[2] ) ]
	} reverse @ret;

	return @ret;
}

sub messages {
	my ($self) = @_;

	my $strp = DateTime::Format::Strptime->new(
		pattern   => '%y%m%d%H%M',
		time_zone => 'Europe/Berlin',
	);

	my @messages = reverse sort keys %{ $self->{messages} };
	my @ret      = map {
		[
			$strp->parse_datetime( $self->{messages}->{$_}->[0] ),
			$self->translate_msg( $self->{messages}->{$_}->[2] )
		]
	} @messages;

	return @ret;
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
	if ( @via and $via[-1] eq $last_stop ) {
		pop(@via);
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

sub sched_route_pre {
	my ($self) = @_;

	return @{ $self->{sched_route_pre} };
}

sub sched_route_post {
	my ($self) = @_;

	return @{ $self->{sched_route_post} };
}

sub sched_route {
	my ($self) = @_;

	return ( $self->sched_route_pre, $self->{station},
		$self->sched_route_post );
}

sub superseded_messages {
	my ( $self, $msg ) = @_;

	my %superseded = (
		84 => [ 80, 82, 83, 85 ],
		88 => [ 80, 82, 83, 85, 86, 87, 90, 91, 92, 93, 96, 97, 98 ],
	);

	return @{ $superseded{$msg} // [] };
}

sub translate_msg {
	my ( $self, $msg ) = @_;

	my %translation = (
		2  => 'Polizeiliche Ermittlung',
		3  => 'Feuerwehreinsatz neben der Strecke',
		5  => 'Ärztliche Versorgung eines Fahrgastes',
		6  => 'Betätigen der Notbremse',
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
		64 => 'Weichenstörung',
		55 => 'Technische Störung an einem anderen Zug',        # ?
		57 => 'Zusätzlicher Halt',                              # ?
		80 => 'Abweichende Wagenreihung',
		82 => 'Mehrere Wagen fehlen',
		83 => 'Fehlender Zugteil',
		84 => 'Zug verkehrt richtig gereiht',                    # r 80 82 83 85
		85 => 'Ein Wagen fehlt',
		86 => 'Keine Reservierungsanzeige',
		87 => 'Einzelne Wagen ohne Reservierungsanzeige',
		88 =>
		  'Keine Qualitätsmängel',  # r 80 82 83 85 86 87 90 91 92 93 96 97 98
		89 => 'Reservierungen sind wieder vorhanden',
		90 => 'Kein Bordrestaurant/Bordbistro',
		91 => 'Eingeschränkte Fahrradmitnahme',
		92 => 'Klimaanlage in einzelnen Wagen ausgefallen',
		93 => 'Fehlende oder gestörte behindertengerechte Einrichtung',
		94 => 'Ersatzbewirtschaftung',
		95 => 'Ohne behindertengerechtes WC',
		96 => 'Der Zug ist überbesetzt',
		97 => 'Der Zug ist überbesetzt',
		98 => 'Sonstige Qualitätsmängel',
		99 => 'Verzögerungen im Betriebsablauf',
	);

	return $translation{$msg} // "?($msg)";
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

	for my $result ($status->results) {
		printf(
			"At %s: %s to %s from platform %s\n",
			$result->time,
			$result->line,
			$result->destination,
			$result->platform,
		);
	}

=head1 VERSION

version 0.04

=head1 DESCRIPTION

Travel::Status::DE::IRIs::Result describes a single arrival/departure
as obtained by Travel::Status::DE::IRIS.  It contains information about
the platform, time, route and more.

=head1 METHODS

=head2 ACCESSORS

=over

=item $result->arrival

DateTime(3pm) object for the arrival date and time. undef if the
train starts here. Contains realtime data if available.

=item $result->classes

List of characters indicating the class(es) of this train, may be empty. This
is slighty related to B<type>, but more generic. At this time, the following
classes are known:

    D    Non-DB train. Usually local transport
    D,F  Non-DB train, long distance transport
    F    "Fernverkehr", long-distance transport
    N    "Nahverkehr", local and regional transport
    S    S-Bahn, rather slow local/regional transport

=item $result->date

Scheduled departure date if available, arrival date otherwise (e.g. if the
train ends here). String in dd.mm.YYYY format. Does not contain realtime data.

=item $result->datetime

DateTime(3pm) object for departure if available, arrival otherwise. Does not
contain realtime data.

=item $result->delay

Estimated delay in minutes (integer number). undef when no realtime data is
available, negative if a train ends at the specified station and arrives /
arrived early.

=item $result->delay_messages

Get all delay messages entered for this train. Returns a list of [datetime,
string] listrefs sorted by newest first. The datetime part is a DateTime(3pm)
object corresponding to the point in time when the message was entered, the
string is the message. If a delay reason was entered more than once, only its
most recent record will be returned.

=item $result->departure

DateTime(3pm) object for the departure date and time. undef if the train ends
here. Contains realtime data if available.

=item $result->destination

Aleas for route_end.

=item $result->info

List of information strings. Contains both reasons for delays (which may or
may not be up-to-date) and generic information such as missing carriages or
broken toilets.

=item $result->is_cancelled

True if the train was cancelled, false otherwise. Note that this does not
contain information about replacement trains or route diversions.

=item $result->is_transfer

True if the train changes its ID at the current station, false otherwise.

An ID change means: There are two results in the system (e.g. RE 10228
ME<uuml>nster -> Duisburg, RE 30028 Duisburg -> DE<uuml>sseldorf), but they are
the same train (RE line 2 from ME<uuml>nster to DE<uuml>sseldorf in this case)
and should be treated as such. In this case, Travel::Status::DE::IRIS merges
the results and indicates it by setting B<is_transfer> to a true value.

In case of a transfer, B<train_id> and B<train_no> are set to the "new"
value, the old ones are available in B<old_train_id> and B<old_train_no>.

=item $result->line

Train type with line (such as C<< S 1 >>) if available, type with number
(suc as C<< RE 10126 >>) otherwise.

=item $result->line_no

Number of the line, undef if unknown. Seems to be set only for S-Bahn and
similar trains. Regional and long-distance trains such as C<< RE 10126 >>
usually do not have this field set, even if they have a common line number
(C<< RE 1 >> in this case).

Example: For the line C<< S 1 >>, line_no will return C<< 1 >>.

=item $result->messages

Get all qos and delay messages ever entered for this train. Returns a list of
[datetime, string] listrefs sorted by newest first. The datetime part is a
DateTime(3pm) object corresponding to the point in time when the message was
entered, the string is the message. Note that neither duplicates nor superseded
messages are filtered from this list.

=item $result->old_train_id

Numeric ID of the pre-transfer train. Seems to be unique for a year and
trackable across stations. Only defined if a transfer took place,
see also B<is_transfer>.

=item $result->old_train_no

Number of the pre-tarnsfer train, unique per day. E.g. C<< 2225 >> for
C<< IC 2225 >>. See also B<is_transfer>. Only defined if a transfer took
place, see also B<is_transfer>.

=item $result->origin

Alias for route_start.

=item $result->qos_messages

Get all current qos messages for this train. Returns a list of [datetime,
string] listrefs sorted by newest first. The datetime part is a DateTime(3pm)
object corresponding to the point in time when the message was entered, the
string is the message. Contains neither superseded messages nor duplicates (in
case of a duplicate, only the most recent message is present)

=item $result->platform

Arrival/departure platform as string, undef if unknown. Note that this is
not neccessarily a number, platform sections may be included (e.g.
C<< 3a/b >>).

=item $result->raw_id

Raw ID of the departure, e.g. C<< -4642102742373784975-1401031322-6 >>.
The first part appears to be this train's UUID (can be tracked across
multiple stations), the second the YYmmddHHMM departure timestamp at its
start station, and the third the count of this station in the train's schedule
(in this case, it's the sixth from thestart station).

About half of all departure IDs do not contain the leading minus (C<< - >>)
seen in this example. The reason for this is unknown.

This is a developer option. It may be removed without prior warning.

=item $result->realtime_xml

XML::LibXML::Node(3pm) object containing all realtime data. undef if none is
available.

This is a developer option. It may be removed without prior warning.

=item $result->route

List of all stations served by this train, according to its schedule. Does
not contain realtime data.

=item $result->route_end

Name of the last station served by this train.

=item $result->route_interesting

List of up to three "interesting" stations served by this train, subset of
route_post. Usually contains the next stop and one or two major stations after
that. Does not contain realtime data.

=item $result->route_pre

List of station names the train passed (or will have passed) befoe this stop.

=item $result->route_post

List of station names the train will pass after this stop.

=item $result->route_start

Name of the first station served by this train.

=item $result->sched_arrival

DateTime(3pm) object for the scheduled arrival date and time. undef if the
train starts here.

=item $result->sched_departure

DateTime(3pm) object for the scehduled departure date and time. undef if the
train ends here.

=item $result->sched_platform

Scheduled Arrival/departure platform as string, undef if unknown. Note that
this is not neccessarily a number, platform sections may be included (e.g.  C<<
3a/b >>).

=item $result->sched_route

List of all stations served by this train, according to its schedule. Does
not contain realtime data.

=item $result->sched_route_end

Name of the last station served by this train according to its schedule.

=item $result->sched_route_pre

List of station names the train is scheduled to pass before this stop.

=item $result->sched_route_post

List of station names the train is scheduled to pass after this stop.

=item $result->sched_route_start

Name of the first station served by this train according to its schedule.

=item $result->start

DateTime(3pm) object for the scheduled start of the train on its route
(i.e. the departure time at its first station).

=item $result->stop_no

Number of this stop on the train's route. 1 if it's the start station, 2
for the stop after that, and so on.

=item $result->time

Scheduled departure time if available, arrival time otherwise (e.g. if the
train ends here). String in HH:MM format. Does not contain realtime data.

=item $result->train

Alias for line.

=item $result->train_id

Numeric ID of this train. Seems to be unique for a year and trackable across
stations.

=item $result->train_no

Number of this train, unique per day. E.g. C<< 2225 >> for C<< IC 2225 >>.

=item $result->train_no_transfer

Number of this train after a following transfer, undefined if no such transfer
exists. See B<is_transfer> for a note about this.

Note that unlike B<old_train_no>, this information is always based on realtime
data (not included in any schedule) and only set for stations before the
transfer station, not the transfer station itself.

=item $result->type

Type of this train, e.g. C<< S >> for S-Bahn, C<< RE >> for Regional-Express,
C<< ICE >> for InterCity-Express.

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

=item d  6 : "BetE<auml>tigen der Notbremse"

Source: Correlation between IRIS and DB RIS (bahn.de).

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

=item d 55 : "Technische StE<ouml>rung an einem anderen Zug"

Source: Correlation between IRIS and DB RIS (bahn.de).

=item d 57 : "ZusE<auml>tzlicher Halt"

Source: Correlation between IRIS and DB RIS (bahn.de). Only one entry so far,
so may be wrong.

=item d 64 : "WeichenstE<ouml>rung"

Source: correlation between IRIS and DB RIS (bahn.de).

=item q 80 : "Abweichende Wagenreihung"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 82 : "Mehrere Wagen fehlen"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 83 : "Fehlender Zugteil"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 84 : "Zug verkehrt richtig gereiht"

Obsoletes messages 80, 82, 83, 85.
Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 85 : "Ein Wagen fehlt"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 86 : "Keine Reservierungsanzeige"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 87 : "Einzelne Wagen ohne Reservierungsanzeige"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 88 : "Keine QualitE<auml>tsmE<auml>ngel"

Obsoletes messages 80, 82, 83, 85, 86, 87, 90, 91, 92, 93, 96, 97, 98.
Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 89 : "Reservierungen sind wieder vorhanden"

Obsoletes messages 86, 87.
Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 90 : "Kein Bordrestaurant/Bordbistro"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 91 : "EingeschrE<auml>nkte Fahrradmitnahme"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

Might also mean "Keine Fahrradmitnahme" (source: frubi).

=item q 92 : "Klimaanlage in einzelnen Wagen ausgefallen"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

Might also mean "Rollstuhlgerechtes WC in einem Wagen ausgefallen"
(source: frubi).

=item q 93 : "Fehlende oder gestE<ouml>rte behindertengerechte Einrichtung"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.
Might also mean "Kein rollstuhlgerechtes WC" (source: frubi).

=item q 94 : "Ersatzbewirtschaftung"

Estimated from a comparison with bahn.de/ris messages. Needs to be verified.

=item q 95 : "Ohne behindertengerechtes WC"

Estimated from a comparison with bahn.de/iris messages.

=item q 96 : "Der Zug ist E<uuml>berbesetzt"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 97 : "Der Zug ist E<uuml>berbesetzt"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.

=item q 98 : "Sonstige QualitE<auml>tsmE<auml>ngel"

Verified by L<https://iris.noncd.db.de/irisWebclient/Configuration>.
Might also mean "Kein rollstuhlgerechter Wagen" (source: frubi).

=item d 99 : "VerzE<ouml>gerungen im Betriebsablauf"

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item Class::Accessor(3pm)

=back

=head1 BUGS AND LIMITATIONS

Unknown.

=head1 SEE ALSO

Travel::Status::DE::IRIS(3pm).

=head1 AUTHOR

Copyright (C) 2013-2014 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
