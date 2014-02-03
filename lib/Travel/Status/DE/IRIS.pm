package Travel::Status::DE::IRIS;

use strict;
use warnings;
use 5.014;

no if $] >= 5.018, warnings => 'experimental::smartmatch';

our $VERSION = '0.02';

use Carp qw(confess cluck);
use DateTime;
use Encode qw(encode decode);
use List::Util qw(first);
use LWP::UserAgent;
use Travel::Status::DE::IRIS::Result;
use XML::LibXML;

sub new {
	my ( $class, %opt ) = @_;

	my $ua = LWP::UserAgent->new(%opt);

	if ( not $opt{station} ) {
		confess('station flag must be passed');
	}

	my $self = {
		datetime => $opt{datetime}
		  // DateTime->now( time_zone => 'Europe/Berlin' ),
		iris_base => $opt{iris_base}
		  // 'http://iris.noncd.db.de/iris-tts/timetable',
		station    => $opt{station},
		user_agent => $ua,
	};

	bless( $self, $class );

	$ua->env_proxy;

	my $res_st = $ua->get( $self->{iris_base} . '/station/' . $opt{station} );

	if ( $res_st->is_error ) {
		$self->{errstr} = $res_st->status_line;
		return $self;
	}

	my $xml_st = XML::LibXML->load_xml( string => $res_st->decoded_content );

	$self->{nodes}{station} = ( $xml_st->findnodes('//station') )[0];

	if ( not $self->{nodes}{station} ) {
		$self->{errstr}
		  = "The station '$opt{station}' has no associated timetable";
		return $self;
	}

	my $dt_req = $self->{datetime}->clone;
	for ( 1 .. 3 ) {
		$self->get_timetable( $self->{nodes}{station}->getAttribute('eva'),
			$dt_req );
		$dt_req->add( hours => 1 );
	}

	$self->get_realtime;

	@{ $self->{results} } = grep {
		my $d
		  = ( $_->departure // $_->arrival )
		  ->subtract_datetime( $self->{datetime} );
		not $d->is_negative and $d->in_units('hours') < 4
	} @{ $self->{results} };

	@{ $self->{results} }
	  = sort { $a->{datetime} <=> $b->{datetime} } @{ $self->{results} };

	return $self;
}

sub add_result {
	my ( $self, $station, $s ) = @_;

	my $id   = $s->getAttribute('id');
	my $e_tl = ( $s->findnodes('./tl') )[0];
	my $e_ar = ( $s->findnodes('./ar') )[0];
	my $e_dp = ( $s->findnodes('./dp') )[0];

	if ( not $e_tl ) {
		return;
	}

	my %data = (
		raw_id    => $id,
		classes   => $e_tl->getAttribute('f'),    # D N S F
		unknown_t => $e_tl->getAttribute('t'),    # p
		train_no  => $e_tl->getAttribute('n'),    # dep number
		type      => $e_tl->getAttribute('c'),    # S/ICE/ERB/...
		line_no   => $e_tl->getAttribute('l'),    # 1 -> S1, ...
		station   => $station,
		unknown_o => $e_tl->getAttribute('o'),    # owner: 03/80/R2/...
	);

	if ($e_ar) {
		$data{arrival_ts}  = $e_ar->getAttribute('pt');
		$data{platform}    = $e_ar->getAttribute('pp');    # string, not number!
		$data{route_pre}   = $e_ar->getAttribute('ppth');
		$data{route_start} = $e_ar->getAttribute('pde');
		$data{arrival_wings} = $e_ar->getAttribute('wings');
	}

	if ($e_dp) {
		$data{departure_ts} = $e_dp->getAttribute('pt');
		$data{platform}     = $e_dp->getAttribute('pp');   # string, not number!
		$data{route_post}   = $e_dp->getAttribute('ppth');
		$data{route_end}    = $e_dp->getAttribute('pde');
		$data{departure_wings} = $e_dp->getAttribute('wings');
	}

	my $result = Travel::Status::DE::IRIS::Result->new(%data);

	# if scheduled departure and current departure are not within the
	# same hour, trains are reported twice. Don't add duplicates in
	# that case.
	if ( not first { $_->raw_id eq $id } @{ $self->{results} } ) {
		push( @{ $self->{results} }, $result, );
	}

	return $result;
}

sub get_timetable {
	my ( $self, $eva, $dt ) = @_;
	my $ua = $self->{user_agent};

	my $res = $ua->get(
		$dt->strftime( $self->{iris_base} . "/plan/${eva}/%y%m%d/%H" ) );

	if ( $res->is_error ) {
		$self->{errstr} = $res->status_line;
		return $self;
	}

	my $xml = XML::LibXML->load_xml( string => $res->decoded_content );

	#say $xml->toString(1);

	my $station = ( $xml->findnodes('/timetable') )[0]->getAttribute('station');

	for my $s ( $xml->findnodes('/timetable/s') ) {

		$self->add_result( $station, $s );
	}

	return $self;
}

sub get_realtime {
	my ($self) = @_;

	my $eva = $self->{nodes}{station}->getAttribute('eva');
	my $res = $self->{user_agent}->get( $self->{iris_base} . "/fchg/${eva}" );

	if ( $res->is_error ) {
		$self->{errstr} = $res->status_line;
		return $self;
	}

	my $xml = XML::LibXML->load_xml( string => $res->decoded_content );

	my $station = ( $xml->findnodes('/timetable') )[0]->getAttribute('station');

	for my $s ( $xml->findnodes('/timetable/s') ) {
		my $id   = $s->getAttribute('id');
		my $e_tl = ( $s->findnodes('./tl') )[0];
		my $e_ar = ( $s->findnodes('./ar') )[0];
		my $e_dp = ( $s->findnodes('./dp') )[0];
		my @e_ms = $s->findnodes('.//m');

		my %messages;

		my $result = first { $_->raw_id eq $id } $self->results;

		if ( not $result ) {
			$result = $self->add_result( $station, $s );
		}
		if ( not $result ) {
			next;
		}

		$result->add_realtime($s);

		for my $e_m (@e_ms) {
			my $type  = $e_m->getAttribute('t');
			my $value = $e_m->getAttribute('c');
			my $msgid = $e_m->getAttribute('id');
			my $ts    = $e_m->getAttribute('ts');

			if ($value) {
				$messages{$msgid} = [ $ts, $type, $value ];
			}
		}

		$result->add_messages(%messages);

		if ($e_tl) {
			$result->add_tl(
				class     => $e_tl->getAttribute('f'),    # D N S F
				unknown_t => $e_tl->getAttribute('t'),    # p
				train_no  => $e_tl->getAttribute('n'),    # dep number
				type      => $e_tl->getAttribute('c'),    # S/ICE/ERB/...
				line_no   => $e_tl->getAttribute('l'),    # 1 -> S1, ...
				unknown_o => $e_tl->getAttribute('o'),    # owner: 03/80/R2/...
			);
		}
		if ($e_ar) {
			$result->add_ar(
				arrival_ts => $e_ar->getAttribute('ct'),
				platform   => $e_ar->getAttribute('cp'),
				route_pre  => $e_ar->getAttribute('cpth'),
				status     => $e_ar->getAttribute('cs'),
			);
		}
		if ($e_dp) {
			$result->add_dp(
				departure_ts => $e_dp->getAttribute('ct'),
				platform     => $e_dp->getAttribute('cp'),
				route_post   => $e_dp->getAttribute('cpth'),
				status       => $e_dp->getAttribute('cs'),
			);
		}

	}

	return $self;
}

sub errstr {
	my ($self) = @_;

	return $self->{errstr};
}

sub results {
	my ($self) = @_;

	return @{ $self->{results} // [] };
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

version 0.02

=head1 DESCRIPTION

Travel::Status::DE::IRIS is an unofficial interface to IRIS based web
departure monitors such as
L<https://iris.noncd.db.de/wbt/js/index.html?typ=ab&style=qrab&bhf=EE&SecLang=&Zeilen=20&footer=0&disrupt=0>.

=head1 METHODS

=over

=item my $states = Travel::Status::DE::IRIS->new(I<%opt>)

Requests schedule and realtime data for a specific station at a specific
point in time. Returns a new Travel::Status::DE::IRIS object.

Arguments:

=over

=item B<datetime> => I<datetime-obj>

A DateTime(3pm) object specifying the point in time. Optional, defaults to the
current date and time.

=item B<iris_base> => I<url>

IRIS base url, defaults to C<< http://iris.noncd.db.de/iris-tts/timetable >>.

=item B<station> => I<stationcode>

Mandatory: Which station to return departures for. Note that this is not a
station name, but a station code, such as "EE" (for Essen Hbf) or "KA"
(for Aachen Hbf). See Travel::Status::DE::IRIS::Stations(3pm) for a
name to code mapping.

=back

All other options are passed to the LWP::UserAgent(3pm) constructor.

=item $status->errstr

In case of an HTTP request or IRIS error, returns a string describing it.
Returns undef otherwise.

=item $status->results

Returns a list of Travel::Status::DE::IRIS(3pm) objects, each one describing
one arrival and/or departure.

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

Many backend features are not yet exposed.

=head1 SEE ALSO

db-iris(1), Travel::Status::DE::IRIS::Result(3pm),
Travel::Status::DE::IRIS::Stations(3pm)

=head1 AUTHOR

Copyright (C) 2013-2014 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
