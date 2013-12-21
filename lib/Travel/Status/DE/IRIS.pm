package Travel::Status::DE::IRIS;

use strict;
use warnings;
use 5.018;

no if $] >= 5.018, warnings => "experimental::smartmatch";

our $VERSION = '0.00';

use Carp qw(confess cluck);
use DateTime;
use Encode qw(encode decode);
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
		dt_now     => DateTime->now( time_zone => 'Europe/Berlin' ),
		station    => $opt{station},
		user_agent => $ua,
	};

	bless( $self, $class );

	$ua->env_proxy;

	my $res_st = $ua->get(
		'http://iris.noncd.db.de/iris-tts/timetable/station/' . $opt{station} );

	if ( $res_st->is_error ) {
		$self->{errstr} = $res_st->status_line;
		return $self;
	}

	my $xml_st = XML::LibXML->load_xml( string => $res_st->decoded_content );

	$self->{nodes}{station} = ( $xml_st->findnodes('//station') )[0];

	my $dt_req = $self->{dt_now}->clone;
	for ( 1 .. 3 ) {
		$self->get_timetable( $self->{nodes}{station}->getAttribute('eva'),
			$dt_req );
		$dt_req->add( hours => 1 );
	}

	@{ $self->{results} }
	  = sort { $a->{datetime} <=> $b->{datetime} } @{ $self->{results} };

	return $self;
}

sub get_timetable {
	my ( $self, $eva, $dt ) = @_;
	my $ua = $self->{user_agent};

	my $res = $ua->get(
		$dt->strftime(
			"http://iris.noncd.db.de/iris-tts/timetable/plan/${eva}/%y%m%d/%H")
	);

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

		if ( not $e_tl ) {
			next;
		}

		my %data = (
			raw_id    => $id,
			class     => $e_tl->getAttribute('f'),    # D N S F
			unknown_t => $e_tl->getAttribute('t'),    # p
			train_no  => $e_tl->getAttribute('n'),    # dep number
			type      => $e_tl->getAttribute('c'),    # S/ICE/ERB/...
			line_no   => $e_tl->getAttribute('l'),    # 1 -> S1, ...
			station   => $station,
			unknown_o => $e_tl->getAttribute('o'),    # owner: 03/80/R2/...
		);

		if ($e_ar) {
			$data{arrival_ts} = $e_ar->getAttribute('pt');
			$data{platform}   = $e_ar->getAttribute('pp'); # string, not number!
			$data{route_pre}     = $e_ar->getAttribute('ppth');
			$data{arrival_wings} = $e_ar->getAttribute('wings');
		}

		if ($e_dp) {
			$data{departure_ts} = $e_dp->getAttribute('pt');
			$data{platform} = $e_dp->getAttribute('pp');   # string, not number!
			$data{route_post}      = $e_dp->getAttribute('ppth');
			$data{departure_wings} = $e_dp->getAttribute('wings');
		}

		push(
			@{ $self->{results} },
			Travel::Status::DE::IRIS::Result->new(%data)
		);
	}

	return $self;
}

sub errstr {
	my ($self) = @_;

	return $self->{errstr};
}

sub results {
	my ($self) = @_;

	return @{ $self->{results} };
}

1;

__END__

=head1 NAME

Travel::Status::DE::IRIS - Interface to IRIS based web departure monitors.

=head1 SYNOPSIS

TODO

=head1 VERSION

version 0.00

=head1 DESCRIPTION

TraveL::Status::DE::IRIS is an unofficial interface to IRIS based web
departure monitors such as
L<https://iris.noncd.db.de/wbt/js/index.html?typ=ab&style=qrab&bhf=EE&SecLang=&Zeilen=20&footer=0&disrupt=0>.

=head1 AUTHOR

Copyright (C) 2013 by Daniel Friesel E<lt>derf@finalrewind.orgE<gt>

=head1 LICENSE

This module is licensed under the same terms as Perl itself.
