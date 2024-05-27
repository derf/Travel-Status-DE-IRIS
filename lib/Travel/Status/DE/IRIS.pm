package Travel::Status::DE::IRIS;

use strict;
use warnings;
use 5.014;

our $VERSION = '1.96';

use Carp qw(confess cluck);
use DateTime;
use DateTime::Format::Strptime;
use List::Util      qw(none first);
use List::MoreUtils qw(uniq);
use List::UtilsBy   qw(uniq_by);
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

# "station" parameter must be an EVA or DS100 ID.
sub new_p {
	my ( $class, %opt ) = @_;
	my $promise = $opt{promise}->new;

	if ( not $opt{station} ) {
		return $promise->reject('station flag must be passed');
	}

	my $self = $class->new( %opt, async => 1 );
	$self->{promise} = $opt{promise};

	my $lookahead_steps = int( $self->{lookahead} / 60 );
	if ( ( 60 - $self->{datetime}->minute ) < ( $self->{lookahead} % 60 ) ) {
		$lookahead_steps++;
	}
	my $lookbehind_steps = int( $self->{lookbehind} / 60 );
	if ( $self->{datetime}->minute < ( $self->{lookbehind} % 60 ) ) {
		$lookbehind_steps++;
	}

	my @candidates = $opt{get_station}( $opt{station} );

	if ( @candidates != 1 and $opt{station} =~ m{^\d+$} ) {
		@candidates = (
			[
				"D$opt{station}", "Betriebsstelle nicht bekannt $opt{station}",
				$opt{station}
			]
		);
	}

	if ( @candidates == 0 ) {
		return $promise->reject('station not found');
	}
	if ( @candidates >= 2 ) {
		return $promise->reject('station identifier is ambiguous');
	}

	# "uic" is deprecated
	$self->{station} = {
		ds100 => $candidates[0][0],
		eva   => $candidates[0][2],
		name  => $candidates[0][1],
		uic   => $candidates[0][2],
	};
	$self->{related_stations} = [];

	my @queue = ( $self->{station}{eva} );
	my @related_reqs;
	my @related_stations;
	my %seen       = ( $self->{station}{eva} => 1 );
	my $iter_depth = 0;

	while ( @queue and $iter_depth < 12 and $opt{with_related} ) {
		my $eva = shift(@queue);
		$iter_depth++;
		for my $ref ( @{ $opt{meta}{$eva} // [] } ) {
			if ( not $seen{$ref} ) {
				push( @related_stations, $ref );
				$seen{$ref} = 1;
				push( @queue, $ref );
			}
		}
	}

	for my $eva (@related_stations) {
		@candidates = $opt{get_station}($eva);

		if ( @candidates == 1 ) {

			# "uic" is deprecated
			push(
				@{ $self->{related_stations} },
				{
					ds100 => $candidates[0][0],
					eva   => $candidates[0][2],
					name  => $candidates[0][1],
					uic   => $candidates[0][2],
				}
			);
		}
	}

	my $dt_req = $self->{datetime}->clone;
	my @timetable_reqs
	  = ( $self->get_timetable_p( $self->{station}{eva}, $dt_req ) );

	for my $eva (@related_stations) {
		push( @timetable_reqs, $self->get_timetable_p( $eva, $dt_req ) );
	}

	for ( 1 .. $lookahead_steps ) {
		$dt_req->add( hours => 1 );
		push( @timetable_reqs,
			$self->get_timetable_p( $self->{station}{eva}, $dt_req ) );
		for my $eva (@related_stations) {
			push( @timetable_reqs, $self->get_timetable_p( $eva, $dt_req ) );
		}
	}

	$dt_req = $self->{datetime}->clone;
	for ( 1 .. $lookbehind_steps ) {
		$dt_req->subtract( hours => 1 );
		push( @timetable_reqs,
			$self->get_timetable_p( $self->{station}{eva}, $dt_req ) );
		for my $eva (@related_stations) {
			push( @timetable_reqs, $self->get_timetable_p( $eva, $dt_req ) );
		}
	}

	$self->{promise}->all(@timetable_reqs)->then(
		sub {
			my @realtime_reqs
			  = ( $self->get_realtime_p( $self->{station}{eva} ) );
			for my $eva (@related_stations) {
				push( @realtime_reqs, $self->get_realtime_p( $eva, $dt_req ) );
			}
			return $self->{promise}->all_settled(@realtime_reqs);
		}
	)->then(
		sub {
			my @realtime_results = @_;

			for my $realtime_result (@realtime_results) {
				if ( $realtime_result->{status} eq 'rejected' ) {
					$self->{warnstr} //= q{};
					$self->{warnstr}
					  .= "Realtime data request failed: $realtime_result->{reason}. ";
				}
			}

			$self->postprocess_results;
			$promise->resolve($self);
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject($err);
			return;
		}
	)->wait;

	return $promise;
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
		  // 'https://iris.noncd.db.de/iris-tts/timetable',
		keep_transfers  => $opt{keep_transfers},
		lookahead       => $opt{lookahead}  // ( 2 * 60 ),
		lookbehind      => $opt{lookbehind} // ( 0 * 60 ),
		main_cache      => $opt{main_cache},
		rt_cache        => $opt{realtime_cache},
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

	my $lookahead_steps = int( $self->{lookahead} / 60 );
	if ( ( 60 - $self->{datetime}->minute ) < ( $self->{lookahead} % 60 ) ) {
		$lookahead_steps++;
	}
	my $lookbehind_steps = int( $self->{lookbehind} / 60 );
	if ( $self->{datetime}->minute < ( $self->{lookbehind} % 60 ) ) {
		$lookbehind_steps++;
	}

	if ( $opt{async} ) {
		return $self;
	}

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

		# We (the parent) perform transfer processing, so child requests must not
		# do it themselves. Otherwise, trains from child requests will be
		# processed twice and may be lost.
		# Similarly, child requests must not perform requests to related
		# stations -- we're already doing that right now.
		my $ref_status = Travel::Status::DE::IRIS->new(
			datetime       => $self->{datetime},
			developer_mode => $self->{developer_mode},
			iris_base      => $self->{iris_base},
			lookahead      => $self->{lookahead},
			lookbehind     => $self->{lookbehind},
			station        => $ref->{eva},
			main_cache     => $self->{main_cache},
			realtime_cache => $self->{rt_cache},
			strptime_obj   => $self->{strptime_obj},
			user_agent     => $self->{user_agent},
			keep_transfers => 1,
			with_related   => 0,
		);
		if ( not $ref_status->errstr ) {
			push( @{ $self->{results} }, $ref_status->results );
		}
	}

	if ( $self->{errstr} ) {
		return $self;
	}

	my $dt_req = $self->{datetime}->clone;
	$self->get_timetable( $self->{station}{eva}, $dt_req );
	for ( 1 .. $lookahead_steps ) {
		$dt_req->add( hours => 1 );
		$self->get_timetable( $self->{station}{eva}, $dt_req );
	}
	$dt_req = $self->{datetime}->clone;
	for ( 1 .. $lookbehind_steps ) {
		$dt_req->subtract( hours => 1 );
		$self->get_timetable( $self->{station}{eva}, $dt_req );
	}

	$self->get_realtime;

	$self->postprocess_results;

	return $self;
}

sub postprocess_results {
	my ($self) = @_;
	if ( not $self->{keep_transfers} ) {

		# tra (transfer?) indicates a train changing its ID, so there are two
		# results for the same train. Remove the departure-only trains from the
		# result set and merge them with their arrival-only counterpart.
		# This way, in case the arrival is available but the departure isn't,
		# nothing gets lost.
		my @merge_candidates
		  = grep { $_->transfer and $_->departure } @{ $self->{results} };
		@{ $self->{results} }
		  = grep { not( $_->transfer and $_->departure ) }
		  @{ $self->{results} };

		for my $transfer (@merge_candidates) {
			my $result
			  = first { $_->transfer and $_->transfer eq $transfer->train_id }
			  @{ $self->{results} };
			if ($result) {
				$result->merge_with_departure($transfer);
			}
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
}

sub get_with_cache_p {
	my ( $self, $cache, $url ) = @_;

	if ( $self->{developer_mode} ) {
		say "GET $url";
	}

	my $promise = $self->{promise}->new;

	if ($cache) {
		my $content = $cache->thaw($url);
		if ($content) {
			if ( $self->{developer_mode} ) {
				say '  cache hit';
			}
			return $promise->resolve($content);
		}
	}

	if ( $self->{developer_mode} ) {
		say '  cache miss';
	}

	my $res = $self->{user_agent}->get_p($url)->then(
		sub {
			my ($tx) = @_;
			if ( my $err = $tx->error ) {
				$promise->reject(
					"GET $url returned HTTP $err->{code} $err->{message}");
				return;
			}
			my $content = $tx->res->body;
			if ($cache) {
				$cache->freeze( $url, \$content );
			}
			$promise->resolve($content);
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject($err);
			return;
		}
	)->wait;

	return $promise;
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

sub get_station_p {
	my ( $self, %opt ) = @_;

	my $promise = $self->{promise}->new;
	my $station = $opt{name};

	$self->get_with_cache_p( $self->{main_cache},
		$self->{iris_base} . '/station/' . $station )->then(
		sub {
			my ($raw) = @_;
			my ( $xml_st, $xml_err ) = try_load_xml($raw);
			if ($xml_err) {
				$promise->reject('Failed to parse station data: Invalid XML');
				return;
			}
			my $station_node = ( $xml_st->findnodes('//station') )[0];

			if ( not $station_node ) {
				$promise->reject(
					"Station '$station' has no associated timetable");
				return;
			}
			$promise->resolve(
				{
					ds100 => $station_node->getAttribute('ds100'),
					eva   => $station_node->getAttribute('eva'),
					name  => $station_node->getAttribute('name'),
					uic   => $station_node->getAttribute('eva'),
				}
			);
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject($err);
			return;
		}
	)->wait;

	return $promise;
}

sub get_station {
	my ( $self, %opt ) = @_;

	my $iter_depth = 0;
	my @ret;
	my @queue = ( $opt{name} );

	# @seen holds station IDs which were already seen during recursive
	# 'meta' descent. This avoids infinite loops of 'meta' references.
	# Additionally, we use it to skip stations shat should not be referenced.
	# This includes Norddeich / Norddeich Mole (different stations commonly used
	# by identical trains with different departure times), and Essen-Dellwig /
	# Essen-Dellwig Ost (different stations used by different trains, but with
	# identical platform numbers).
	my @seen = ( 8007768, 8004449, 8001903, 8001904 );

	while ( @queue and $iter_depth < 12 ) {
		my $station = shift(@queue);
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
			if ( $self->{developer_mode} ) {
				say '  no timetable';
			}
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

		if ( $station_node->getAttribute('ds100') =~ m{ ^ D \d+ $ }x ) {

			# This used to indicate an invalid DS100 code, at least from DB
			# perspective. It typically referred to subway stations which do not
			# have IRIS departures.
			# However, since Fahrplanwechsel 2022 / 2023, this does not seem
			# to be the case anymore. There are some stations whose DS100 code
			# IRIS does not know, for whatever reason. So for now, accept these
			# stations as well.

			#next;
		}

		push(
			@ret,
			{
				ds100 => $station_node->getAttribute('ds100'),
				eva   => $station_node->getAttribute('eva'),
				name  => $station_node->getAttribute('name'),
				uic   => $station_node->getAttribute('eva'),
			}
		);

		if ( $self->{developer_mode} ) {
			printf( " -> %s (%s / %s)\n", @{ $ret[-1] }{qw{name eva ds100}} );
		}

		if ( $opt{recursive} and defined $station_node->getAttribute('meta') ) {
			my @refs
			  = uniq( split( m{ \| }x, $station_node->getAttribute('meta') ) );
			for my $ref (@refs) {
				if ( none { $_ == $ref } @seen and none { $_ == $ref } @queue )
				{
					push( @queue, $ref );
				}
			}
			$opt{root} = 0;
		}
	}

	if (@queue) {
		cluck(  "Reached $iter_depth iterations when tracking station IDs. "
			  . "This is probably a bug" );
	}

	@ret = uniq_by { $_->{eva} } @ret;

	return @ret;
}

sub add_result {
	my ( $self, $station_name, $station_eva, $s ) = @_;

	my $id   = $s->getAttribute('id');
	my $e_tl = ( $s->findnodes( $self->{xp_tl} ) )[0];
	my $e_ar = ( $s->findnodes( $self->{xp_ar} ) )[0];
	my $e_dp = ( $s->findnodes( $self->{xp_dp} ) )[0];

	if ( not $e_tl ) {
		return;
	}

	my %data = (
		raw_id       => $id,
		classes      => $e_tl->getAttribute('f'), # D N S F
		operator     => $e_tl->getAttribute('o'), # coded operator: 03/80/R2/...
		train_no     => $e_tl->getAttribute('n'), # dep number
		type         => $e_tl->getAttribute('c'), # S/ICE/ERB/...
		station      => $station_name,
		station_eva  => $station_eva + 0,         # EVA IDs are numbers
		station_uic  => $station_eva + 0,         # deprecated
		strptime_obj => $self->{strptime_obj},

		#unknown_t    => $e_tl->getAttribute('t'),    # p
	);

	if ($e_ar) {
		$data{arrival_ts}  = $e_ar->getAttribute('pt');
		$data{line_no}     = $e_ar->getAttribute('l');
		$data{platform}    = $e_ar->getAttribute('pp');    # string, not number!
		$data{route_pre}   = $e_ar->getAttribute('ppth');
		$data{route_start} = $e_ar->getAttribute('pde');
		$data{transfer}    = $e_ar->getAttribute('tra');
		$data{arrival_hidden}   = $e_ar->getAttribute('hi');
		$data{arrival_wing_ids} = $e_ar->getAttribute('wings');
	}

	if ($e_dp) {
		$data{departure_ts} = $e_dp->getAttribute('pt');
		$data{line_no}      = $e_dp->getAttribute('l');
		$data{platform}     = $e_dp->getAttribute('pp');   # string, not number!
		$data{route_post}   = $e_dp->getAttribute('ppth');
		$data{route_end}    = $e_dp->getAttribute('pde');
		$data{transfer}     = $e_dp->getAttribute('tra');
		$data{departure_hidden}   = $e_dp->getAttribute('hi');
		$data{departure_wing_ids} = $e_dp->getAttribute('wings');
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

sub get_timetable_p {
	my ( $self, $eva, $dt ) = @_;

	my $promise = $self->{promise}->new;

	$self->get_with_cache_p( $self->{main_cache},
		$dt->strftime( $self->{iris_base} . "/plan/${eva}/%y%m%d/%H" ) )->then(
		sub {
			my ($raw) = @_;
			my ( $xml, $xml_err ) = try_load_xml($raw);
			if ($xml_err) {
				$promise->reject(
					'Failed to parse a schedule part: Invalid XML');
				return;
			}
			my $station
			  = ( $xml->findnodes('/timetable') )[0]->getAttribute('station');

			for my $s ( $xml->findnodes('/timetable/s') ) {

				$self->add_result( $station, $eva, $s );
			}
			$promise->resolve;
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject($err);
			return;
		}
	)->wait;
	return $promise;
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

	if ( $self->{developer_mode}
		and not scalar $xml->findnodes('/timetable/s') )
	{
		say '  no scheduled trains';
	}

	return $self;
}

sub get_realtime_p {
	my ( $self, $eva ) = @_;

	my $promise = $self->{promise}->new;

	$self->get_with_cache_p( $self->{rt_cache},
		$self->{iris_base} . "/fchg/${eva}" )->then(
		sub {
			my ($raw) = @_;
			my ( $xml, $xml_err ) = try_load_xml($raw);
			if ($xml_err) {
				$promise->reject(
					'Failed to parse a schedule part: Invalid XML');
				return;
			}
			$self->parse_realtime( $eva, $xml );
			$promise->resolve;
			return;
		}
	)->catch(
		sub {
			my ($err) = @_;
			$promise->reject("Failed to fetch realtime data: $err");
			return;
		}
	)->wait;
	return $promise;
}

sub get_realtime {
	my ($self) = @_;

	my $eva = $self->{station}{eva};

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

	$self->parse_realtime( $eva, $xml );
}

sub parse_realtime {
	my ( $self, $eva, $xml ) = @_;
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
				arrival_hidden  => $e_ar->getAttribute('hi'),

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
				departure_hidden  => $e_dp->getAttribute('hi'),
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

Blocking variant:

    use Travel::Status::DE::IRIS;
    
    my $status = Travel::Status::DE::IRIS->new(station => "Essen Hbf");
    for my $r ($status->results) {
        printf(
            "%s %s +%-3d %10s -> %s\n",
            $r->date, $r->time, $r->delay || 0, $r->line, $r->destination
        );
    }

Non-blocking variant (EXPERIMENTAL):

    use Mojo::Promise;
    use Mojo::UserAgent;
    use Travel::Status::DE::IRIS;
    use Travel::Status::DE::IRIS::Stations;
    
    Travel::Status::DE::IRIS->new_p(station => "Essen Hbf",
            promise => 'Mojo::Promise', user_agent => Mojo::UserAgent->new,
            get_station => \&Travel::Status::DE::IRIS::Stations::get_station,
            meta => Travel::Status::DE::IRIS::Stations::get_meta())->then(sub {
        my ($status) = @_;
        for my $r ($status->results) {
            printf(
                "%s %s +%-3d %10s -> %s\n",
                $r->date, $r->time, $r->delay || 0, $r->line, $r->destination
            );
        }
    })->wait;

=head1 VERSION

version 1.96

=head1 DEPRECATION NOTICE

As of May 2024, the backend service that this module relies on is deprecated
and may cease operation in the near future. There is no immediate successor.
Hence, Travel::Status::DE::IRIS is no longer actively maintained.  There is no
promise that issues and merge requests will be reviewed or merged.

The Travel::Status::DE::HAFAS(3pm) module provides similar features. However,
its default "DB" backend is also deprecated. There is no migration path to a
Deutsche Bahn departure monitor that is not deprecated at the moment.

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

=item B<keep_transfers> => I<bool>

A train may change its ID and number at a station, indicating that although the
previous logical train ends here, the physical train will continue its journey
under a new number to a new destination. A notable example is the Berlin
Ringbahn, which travels round and round from Berlin SE<uuml>dkreuz to Berlin
SE<uuml>dkreuz. Each train number corresponds to a single revolution, but the
actual trains just keep going.

The IRIS backend returns two results for each transfer train: An arrival-only
result using the old ID (linked to the new one) and a departure-only result
using the new ID (linked to the old one). By default, this library merges these
into a single result with both arrival and departure time. Train number, ID,
and route are taken from the departure only. The original train ID and number
are available using the B<old_train_id> and B<old_train_no> accessors.

In case this is not desirable (e.g. because you intend to track a single
train to its destination station and do not want to implement special cases
for transfer trains), set B<keep_transfers> to a true value. In this case,
backend data will be reported as-is and transfer trains will not be merged.

=item B<lookahead> => I<int>

Compute only results which are scheduled less than I<int> minutes in the
future.
Default: 120 (2 hours).

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

=item my $promise = Travel::Status::DE::IRIS->new_p(I<%opt>) (B<EXPERIMENTAL>)

Return a promise yielding a Travel::Status::DE::IRIS instance (C<< $status >>)
on success, or an error message (same as C<< $status->errstr >>) on failure.
This function is experimental and may be changed or remove without warning.

In addition to the arguments of B<new>, the following mandatory arguments must
be set:

=over

=item B<promise> => I<promises module>

Promises implementation to use for internal promises as well as B<new_p> return
value. Recommended: Mojo::Promise(3pm).

=item B<get_station> => I<get_station ref>

Reference to Travel::Status::DE::IRIS::Stations::get_station().

=item B<meta> => I<meta dict>

The dictionary returned by Travel::Status::DE::IRIS::Stations::get_meta().

=item B<user_agent> => I<user agent>

User agent instance to use for asynchronous requests. The object must support
promises (i.e., it must implement a C<< get_p >> function). Recommended:
Mojo::UserAgent(3pm).

=back

=item $status->errstr

In case of a fatal HTTP request or IRIS error, returns a string describing it.
Returns undef otherwise.

=item $status->related_stations

Returns a list of hashes describing related stations whose
arrivals/departures are included in B<results>. Only useful when setting
B<with_related> to a true value, see its documentation above for details.

Each hash contains the keys B<eva> (EVA number; often same as UIC station ID),
B<name> (station name), and B<ds100> (station code). Note that stations
returned by B<related_stations> are not necessarily known to
Travel::Status::DE::IRIS::Stations(3pm).

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

Copyright (C) 2013-2024 by Birte Kristina Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
