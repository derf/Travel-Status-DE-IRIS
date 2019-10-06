package Travel::Status::DE::IRIS;

use strict;
use warnings;
use 5.014;

no if $] >= 5.018, warnings => 'experimental::smartmatch';

our $VERSION = '1.33';

use Carp qw(confess cluck);
use DateTime;
use DateTime::Format::Strptime;
use List::Util qw(first);
use List::MoreUtils qw(uniq);
use List::UtilsBy qw(uniq_by);
use LWP::UserAgent;
use Travel::Status::DE::IRIS::Result;
use XML::LibXML;

sub try_load_xml {
	my ($xml) = @_;

	my $tree;

	eval { $tree = XML::LibXML->load_xml( string => $xml ) };

	if ($@) {
		return ( undef, $@ );
	}
	return ( $tree, undef );
}

sub new {
	my ( $class, %opt ) = @_;

	if ( not $opt{station} ) {
		confess('station flag must be passed');
	}

	my $self = {
		datetime => $opt{datetime}
		  // DateTime->now( time_zone => 'Europe/Berlin' ),
		developer_mode => $opt{developer_mode},
		iris_base      => $opt{iris_base}
		  // 'http://iris.noncd.db.de/iris-tts/timetable',
		lookahead  => $opt{lookahead}  // ( 2 * 60 ),
		lookbehind => $opt{lookbehind} // ( 0 * 60 ),
		main_cache => $opt{main_cache},
		rt_cache   => $opt{realtime_cache},
		serializable    => $opt{serializable},
		user_agent      => $opt{user_agent},
		with_related    => $opt{with_related},
		departure_by_id => {},
		strptime_obj => $opt{strptime_obj} // DateTime::Format::Strptime->new(
			pattern   => '%y%m%d%H%M',
			time_zone => 'Europe/Berlin',
		),
		xp_ar => XML::LibXML::XPathExpression->new('./ar'),
		xp_dp => XML::LibXML::XPathExpression->new('./dp'),
		xp_tl => XML::LibXML::XPathExpression->new('./tl'),

	};

	bless( $self, $class );

	if ( not $self->{user_agent} ) {
		my %lwp_options = %{ $opt{lwp_options} // { timeout => 10 } };
		$self->{user_agent} = LWP::UserAgent->new(%lwp_options);
		$self->{user_agent}->env_proxy;
	}

	my ( $station, @related_stations ) = $self->get_station(
		name      => $opt{station},
		root      => 1,
		recursive => $opt{with_related},
	);

	$self->{station}          = $station;
	$self->{related_stations} = \@related_stations;

	for my $ref (@related_stations) {
		my $ref_status = Travel::Status::DE::IRIS->new(
			datetime       => $self->{datetime},
			developer_mode => $self->{developer_mode},
			lookahead      => $self->{lookahead},
			lookbehind     => $self->{lookbehind},
			station        => $ref->{uic},
			main_cache     => $self->{main_cache},
			realtime_cache => $self->{rt_cache},
			strptime_obj   => $self->{strptime_obj},
			user_agent     => $self->{user_agent},
			with_related   => 0,
		);
		if ( not $ref_status->errstr ) {
			push( @{ $self->{results} }, $ref_status->results );
		}
	}

	if ( $self->{errstr} ) {
		return $self;
	}

	my $lookahead_steps = int( $self->{lookahead} / 60 );
	if ( ( 60 - $self->{datetime}->minute ) < ( $self->{lookahead} % 60 ) ) {
		$lookahead_steps++;
	}
	my $lookbehind_steps = int( $self->{lookbehind} / 60 );
	if ( $self->{datetime}->minute < ( $self->{lookbehind} % 60 ) ) {
		$lookbehind_steps++;
	}

	my $dt_req = $self->{datetime}->clone;
	$self->get_timetable( $self->{station}{uic}, $dt_req );
	for ( 1 .. $lookahead_steps ) {
		$dt_req->add( hours => 1 );
		$self->get_timetable( $self->{station}{uic}, $dt_req );
	}
	$dt_req = $self->{datetime}->clone;
	for ( 1 .. $lookbehind_steps ) {
		$dt_req->subtract( hours => 1 );
		$self->get_timetable( $self->{station}{uic}, $dt_req );
	}

	$self->get_realtime;

	# tra (transfer?) indicates a train changing its ID, so there are two
	# results for the same train. Remove the departure-only trains from the
	# result set and merge them with their arrival-only counterpart.
	# This way, in case the arrival is available but the departure isn't,
	# nothing gets lost.
	my @merge_candidates
	  = grep { $_->transfer and $_->departure } @{ $self->{results} };
	@{ $self->{results} }
	  = grep { not( $_->transfer and $_->departure ) } @{ $self->{results} };

	for my $transfer (@merge_candidates) {
		my $result
		  = first { $_->transfer and $_->transfer eq $transfer->train_id }
		@{ $self->{results} };
		if ($result) {
			$result->merge_with_departure($transfer);
		}
	}

	@{ $self->{results} } = grep {
		my $d = $_->departure     // $_->arrival;
		my $s = $_->sched_arrival // $_->sched_departure // $_->arrival // $d;
		$d = $d->subtract_datetime( $self->{datetime} );
		$s = $s->subtract_datetime( $self->{datetime} );
		not $d->is_negative and $s->in_units('minutes') < $self->{lookahead}
	} @{ $self->{results} };

	@{ $self->{results} }
	  = sort { $a->{epoch} <=> $b->{epoch} } @{ $self->{results} };

	# wings (different departures which are coupled as one train) contain
	# references to each other. therefore, they must be processed last.
	$self->create_wing_refs;

	# same goes for replacement refs (the <ref> tag in the fchg document)
	$self->create_replacement_refs;

	return $self;
}

sub get_with_cache {
	my ( $self, $cache, $url ) = @_;

	if ( $self->{developer_mode} ) {
		say "GET $url";
	}

	if ($cache) {
		my $content = $cache->thaw($url);
		if ($content) {
			if ( $self->{developer_mode} ) {
				say '  cache hit';
			}
			return ( ${$content}, undef );
		}
	}

	if ( $self->{developer_mode} ) {
		say '  cache miss';
	}

	my $ua  = $self->{user_agent};
	my $res = $ua->get($url);

	if ( $res->is_error ) {
		return ( undef, $res->status_line );
	}
	my $content = $res->decoded_content;

	if ($cache) {
		$cache->freeze( $url, \$content );
	}

	return ( $content, undef );
}

sub get_station {
	my ( $self, %opt ) = @_;

	my $iter_depth = 0;
	my @ret;
	my @queue = ( $opt{name} );
	my @seen;

	while ( @queue and $iter_depth < 12 ) {
		my $station = shift(@queue);
		push( @seen, $station );
		$iter_depth++;

		my ( $raw, $err )
		  = $self->get_with_cache( $self->{main_cache},
			$self->{iris_base} . '/station/' . $station );
		if ($err) {
			if ( $opt{root} ) {
				$self->{errstr} = "Failed to fetch station data: $err";
				return;
			}
			else {
				$self->{warnstr}
				  = "Failed to fetch station data for '$station': $err\n";
				next;
			}
		}

		my ( $xml_st, $xml_err ) = try_load_xml($raw);
		if ($xml_err) {
			$self->{errstr} = 'Failed to parse station data: Invalid XML';
			return;
		}

		my $station_node = ( $xml_st->findnodes('//station') )[0];

		if ( not $station_node ) {
			if ( $opt{root} ) {
				$self->{errstr}
				  = "Station '$station' has no associated timetable";
				return;
			}
			else {
				$self->{warnstr}
				  = "Station '$station' has no associated timetable";
				next;
			}
			next;
		}

		push( @seen, $station_node->getAttribute('eva') );

		if ( $station_node->getAttribute('name') =~ m{ ZOB} ) {

			# There are no departures from a ZOB ("Zentraler Omnibus-Bahnhof" /
			# Central Omnibus Station). Ignore it entirely.
			next;
		}

		push(
			@ret,
			{
				uic   => $station_node->getAttribute('eva'),
				name  => $station_node->getAttribute('name'),
				ds100 => $station_node->getAttribute('ds100'),
			}
		);

		if ( $self->{developer_mode} ) {
			printf( " -> %s (%s / %s)\n", @{ $ret[-1] }{qw{name uic ds100}} );
		}

		if ( $opt{recursive} and defined $station_node->getAttribute('meta') ) {
			my @refs
			  = uniq( split( m{ \| }x, $station_node->getAttribute('meta') ) );
			@refs = grep { not( $_ ~~ \@seen or $_ ~~ \@queue ) } @refs;
			push( @queue, @refs );
			$opt{root} = 0;
		}
	}

	if (@queue) {
		cluck(  "Reached $iter_depth iterations when tracking station IDs. "
			  . "This is probably a bug" );
	}

	@ret = uniq_by { $_->{uic} } @ret;

	return @ret;
}

sub add_result {
	my ( $self, $station_name, $station_uic, $s ) = @_;

	my $id   = $s->getAttribute('id');
	my $e_tl = ( $s->findnodes( $self->{xp_tl} ) )[0];
	my $e_ar = ( $s->findnodes( $self->{xp_ar} ) )[0];
	my $e_dp = ( $s->findnodes( $self->{xp_dp} ) )[0];

	if ( not $e_tl ) {
		return;
	}

	my %data = (
		raw_id       => $id,
		classes      => $e_tl->getAttribute('f'),    # D N S F
		train_no     => $e_tl->getAttribute('n'),    # dep number
		type         => $e_tl->getAttribute('c'),    # S/ICE/ERB/...
		station      => $station_name,
		station_uic  => $station_uic + 0,            # UIC IDs are numbers
		strptime_obj => $self->{strptime_obj},

		#unknown_o    => $e_tl->getAttribute('o'),    # owner: 03/80/R2/...
		#unknown_t    => $e_tl->getAttribute('t'),    # p
	);

	if ($e_ar) {
		$data{arrival_ts}  = $e_ar->getAttribute('pt');
		$data{line_no}     = $e_ar->getAttribute('l');
		$data{platform}    = $e_ar->getAttribute('pp');    # string, not number!
		$data{route_pre}   = $e_ar->getAttribute('ppth');
		$data{route_start} = $e_ar->getAttribute('pde');
		$data{transfer}    = $e_ar->getAttribute('tra');
		$data{arrival_wing_ids} = $e_ar->getAttribute('wings');

		#$data{unk_ar_hi}        = $e_ar->getAttribute('hi');
	}

	if ($e_dp) {
		$data{departure_ts} = $e_dp->getAttribute('pt');
		$data{line_no}      = $e_dp->getAttribute('l');
		$data{platform}     = $e_dp->getAttribute('pp');   # string, not number!
		$data{route_post}   = $e_dp->getAttribute('ppth');
		$data{route_end}    = $e_dp->getAttribute('pde');
		$data{transfer}     = $e_dp->getAttribute('tra');
		$data{departure_wing_ids} = $e_dp->getAttribute('wings');

		#$data{unk_dp_hi}          = $e_dp->getAttribute('hi');
	}

	if ( $data{arrival_wing_ids} ) {
		$data{arrival_wing_ids} = [ split( /\|/, $data{arrival_wing_ids} ) ];
	}
	if ( $data{departure_wing_ids} ) {
		$data{departure_wing_ids}
		  = [ split( /\|/, $data{departure_wing_ids} ) ];
	}

	my $result = Travel::Status::DE::IRIS::Result->new(%data);

	# if scheduled departure and current departure are not within the
	# same hour, trains are reported twice. Don't add duplicates in
	# that case.
	if ( not $self->{departure_by_id}{$id} ) {
		push( @{ $self->{results} }, $result, );
		$self->{departure_by_id}{$id} = $result;
	}

	return $result;
}

sub get_timetable {
	my ( $self, $eva, $dt ) = @_;

	my ( $raw, $err )
	  = $self->get_with_cache( $self->{main_cache},
		$dt->strftime( $self->{iris_base} . "/plan/${eva}/%y%m%d/%H" ) );

	if ($err) {
		$self->{warnstr} = "Failed to fetch a schedule part: $err";
		return $self;
	}

	my ( $xml, $xml_err ) = try_load_xml($raw);

	if ($xml_err) {
		$self->{warnstr} = 'Failed to parse a schedule part: Invalid XML';
		return $self;
	}

	my $station = ( $xml->findnodes('/timetable') )[0]->getAttribute('station');

	for my $s ( $xml->findnodes('/timetable/s') ) {

		$self->add_result( $station, $eva, $s );
	}

	return $self;
}

sub get_realtime {
	my ($self) = @_;

	my $eva = $self->{station}{uic};

	my ( $raw, $err )
	  = $self->get_with_cache( $self->{rt_cache},
		$self->{iris_base} . "/fchg/${eva}" );

	if ($err) {
		$self->{warnstr} = "Failed to fetch realtime data: $err";
		return $self;
	}

	my ( $xml, $xml_err ) = try_load_xml($raw);

	if ($xml_err) {
		$self->{warnstr} = 'Failed to parse realtime data: Invalid XML';
		return $self;
	}

	my $station = ( $xml->findnodes('/timetable') )[0]->getAttribute('station');

	for my $s ( $xml->findnodes('/timetable/s') ) {
		my $id     = $s->getAttribute('id');
		my $e_ar   = ( $s->findnodes( $self->{xp_ar} ) )[0];
		my $e_dp   = ( $s->findnodes( $self->{xp_dp} ) )[0];
		my @e_refs = $s->findnodes('./ref/tl');
		my @e_ms   = $s->findnodes('.//m');

		my %messages;

		my $result = $self->{departure_by_id}{$id};

		# add_result will return nothing if no ./tl node is present. The ./tl
		# check here is for optimization purposes.
		if ( not $result and ( $s->findnodes( $self->{xp_tl} ) )[0] ) {
			$result = $self->add_result( $station, $eva, $s );
			if ($result) {
				$result->set_unscheduled(1);
			}
		}
		if ( not $result ) {
			next;
		}

		if ( not $self->{serializable} ) {
			$result->set_realtime($s);
		}

		for my $e_m (@e_ms) {
			my $type  = $e_m->getAttribute('t');
			my $value = $e_m->getAttribute('c');
			my $msgid = $e_m->getAttribute('id');
			my $ts    = $e_m->getAttribute('ts');

           # 0 and 1 (with key "f") are related to canceled trains and
           # do not appear to hold information (or at least none we can access).
           # All observed cases of message ID 900 were related to bus
           # connections ("Anschlussbus wartet"). We can't access which bus
           # it refers to, so we don't show that either.
           # ID 1000 is a generic free text message, which (as we lack access
           # to the text itself) is not helpful either.
			if ( defined $value and $value > 1 and $value < 100 ) {
				$messages{$msgid} = [ $ts, $type, $value ];
			}
		}

		$result->set_messages(%messages);

		# note: A departure may also have a ./tl attribute. However, we do
		# not need to process it because it only matters for departures which
		# are not planned (or not in the plans we requested). However, in
		# those cases we already called add_result earlier, which reads ./tl
		# by itself.
		for my $e_ref (@e_refs) {
			$result->add_raw_ref(
				class    => $e_ref->getAttribute('f'),    # D N S F
				train_no => $e_ref->getAttribute('n'),    # dep number
				type     => $e_ref->getAttribute('c'),    # S/ICE/ERB/...
				line_no  => $e_ref->getAttribute('l'),    # 1 -> S1, ...

               #unknown_t => $e_ref->getAttribute('t'),    # p
               #unknown_o => $e_ref->getAttribute('o'),    # owner: 03/80/R2/...
               # TODO ps='a' -> rerouted and normally unscheduled train?
			);
		}
		if ($e_ar) {
			$result->set_ar(
				arrival_ts      => $e_ar->getAttribute('ct'),
				plan_arrival_ts => $e_ar->getAttribute('pt'),
				platform        => $e_ar->getAttribute('cp'),
				route_pre       => $e_ar->getAttribute('cpth'),
				sched_route_pre => $e_ar->getAttribute('ppth'),
				status          => $e_ar->getAttribute('cs'),
				status_since    => $e_ar->getAttribute('clt'),

				# TODO ps='a' -> rerouted and normally unscheduled train?
			);
		}
		if ($e_dp) {
			$result->set_dp(
				departure_ts      => $e_dp->getAttribute('ct'),
				plan_departure_ts => $e_dp->getAttribute('pt'),
				platform          => $e_dp->getAttribute('cp'),
				route_post        => $e_dp->getAttribute('cpth'),
				sched_route_post  => $e_dp->getAttribute('ppth'),
				status            => $e_dp->getAttribute('cs'),
			);
		}

	}

	return $self;
}

sub get_result_by_id {
	my ( $self, $id ) = @_;

	my $res = first { $_->wing_id eq $id } @{ $self->{results} };
	return $res;
}

sub get_result_by_train {
	my ( $self, $type, $train_no ) = @_;

	my $res = first { $_->type eq $type and $_->train_no eq $train_no }
	@{ $self->{results} };
	return $res;
}

sub create_wing_refs {
	my ($self) = @_;

	for my $r ( $self->results ) {
		if ( $r->{departure_wing_ids} ) {
			for my $wing_id ( @{ $r->{departure_wing_ids} } ) {
				my $wingref = $self->get_result_by_id($wing_id);
				if ($wingref) {
					$r->add_departure_wingref($wingref);
				}
			}
		}
		if ( $r->{arrival_wing_ids} ) {
			for my $wing_id ( @{ $r->{arrival_wing_ids} } ) {
				my $wingref = $self->get_result_by_id($wing_id);
				if ($wingref) {
					$r->add_arrival_wingref($wingref);
				}
			}
		}
	}

}

sub create_replacement_refs {
	my ($self) = @_;

	for my $r ( $self->results ) {
		for my $ref_hash ( @{ $r->{refs} // [] } ) {
			my $ref = $self->get_result_by_train( $ref_hash->{type},
				$ref_hash->{train_no} );
			if ($ref) {
				$r->add_reference($ref);
			}
		}
	}
}

sub station {
	my ($self) = @_;

	return $self->{station};
}

sub related_stations {
	my ($self) = @_;

	return @{ $self->{related_stations} };
}

sub errstr {
	my ($self) = @_;

	return $self->{errstr};
}

sub results {
	my ($self) = @_;

	return @{ $self->{results} // [] };
}

sub warnstr {
	my ($self) = @_;

	return $self->{warnstr};
}

1;

__END__

=head1 NAME

Travel::Status::DE::IRIS - Interface to IRIS based web departure monitors.

=head1 SYNOPSIS

    use Travel::Status::DE::IRIS;
    use Travel::Status::DE::IRIS::Stations;

    # Get station code for "Essen Hbf" (-> "EE")
    my $station = (Travel::Status::DE::IRIS::Stations::get_station_by_name(
        'Essen Hbf'))[0][0];
    
    my $status = Travel::Status::DE::IRIS->new(station => $station);
    for my $r ($status->results) {
        printf(
            "%s %s +%-3d %10s -> %s\n",
            $r->date, $r->time, $r->delay || 0, $r->line, $r->destination
        );
    }

=head1 VERSION

version 1.33

=head1 DESCRIPTION

Travel::Status::DE::IRIS is an unofficial interface to IRIS based web
departure monitors such as
L<https://iris.noncd.db.de/wbt/js/index.html?typ=ab&style=qrab&bhf=EE&SecLang=&Zeilen=20&footer=0&disrupt=0>.

=head1 METHODS

=over

=item my $status = Travel::Status::DE::IRIS->new(I<%opt>)

Requests schedule and realtime data for a specific station at a specific
point in time. Returns a new Travel::Status::DE::IRIS object.

Arguments:

=over

=item B<datetime> => I<datetime-obj>

A DateTime(3pm) object specifying the point in time. Optional, defaults to the
current date and time.

=item B<iris_base> => I<url>

IRIS base url, defaults to C<< http://iris.noncd.db.de/iris-tts/timetable >>.

=item B<lookahead> => I<int>

Compute only results which are scheduled less than I<int> minutes in the
future.
Default: 180 (3 hours).

Note that the DeutscheBahn IRIS backend only provides schedules up to four to
five hours into the future. So in most cases, setting this to a value above 240
minutes will have little effect. However, as the IRIS occasionally contains
unscheduled departures or qos messages known far in advance (e.g. 12 hours from
now), any non-negative integer is accepted.

=item B<lookbehind> => I<int>

Also check trains whose scheduled departure lies up to I<int> minutes in the
past. Default: 0.

This is useful when requesting departures shortly after a full hour. If,
for example, a train was scheduled to depart on 11:59 and has 5 minutes delay,
it will not be shown when requesting departures on or after 12:00 unless
B<lookbehind> is set to a value greater than zero.

Note that trains with significant delay (e.g. +30) may still be shown in this
case regardless of the setting of B<lookbehind>, since these receive special
treatment by the IRIS backend.

=item B<lwp_options> => I<\%hashref>

Passed on to C<< LWP::UserAgent->new >>. Defaults to C<< { timeout => 10 } >>,
you can use an empty hashref to unset the default.

=item B<main_cache> => I<$ojj>

A Cache::File(3pm) object used to cache station and timetable requests. Optional.

=item B<realtime_cache> => I<$ojj>

A Cache::File(3pm) object used to cache realtime data requests. Optional.

=item B<station> => I<stationcode>

Mandatory: Which station to return departures for. Note that this is not a
station name, but a station code, such as "EE" (for Essen Hbf) or "KA"
(for Aachen Hbf). See Travel::Status::DE::IRIS::Stations(3pm) for a
name to code mapping.

=item B<with_related> => I<bool>

Sometimes, Deutsche Bahn splits up major stations in the IRIS interface.  For
instance, "KE<ouml>ln Messe/Deutz" actually consists of "KE<ouml>ln
Messe/Deutz" (KKDZ), "KE<ouml>ln Messe/Deutz Gl. 9-10" (KKDZB) and "KE<ouml>ln
Messe/Deutz (tief)" (KKDT).

By default, Travel::Status::DE::IRIS only returns departures for the specified
station. When this option is set to a true value, it will also return
departures for all related stations.

=back

=item $status->errstr

In case of a fatal HTTP request or IRIS error, returns a string describing it.
Returns undef otherwise.

=item $status->results

Returns a list of Travel::Status::DE::IRIS::Result(3pm) objects, each one describing
one arrival and/or departure.

=item $status->warnstr

In case of a (probably) non-fatal HTTP request or IRIS error, returns a string
describing it.  Returns undef otherwise.

=back

=head1 DIAGNOSTICS

None.

=head1 DEPENDENCIES

=over

=item * DateTime(3pm)

=item * List::Util(3pm)

=item * LWP::UserAgent(3pm)

=item * XML::LibXML(3pm)

=back

=head1 BUGS AND LIMITATIONS

Some backend features are not yet exposed.

=head1 SEE ALSO

db-iris(1), Travel::Status::DE::IRIS::Result(3pm),
Travel::Status::DE::IRIS::Stations(3pm)

=head1 REPOSITORY

L<https://github.com/derf/Travel-Status-DE-IRIS>

=head1 AUTHOR

Copyright (C) 2013-2019 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
