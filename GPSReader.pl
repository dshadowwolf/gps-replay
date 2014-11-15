#!/usr/bin/perl

use strict;
use warnings;

package  GPSReader;
our $VERSION = qw/1.0.0/;

use Data::Dumper;
use Replay 0.02;
use Replay::Message;
use GPSMessage;
use EV;
use Readonly;
use Config::Locale;
use Device::SerialPort qw/:ALL/;
use GPSTestRule;

# the following Config::Locale related stuff needs modification
# for production use
my @values     = ['json'];
my $config_dir = './conf';

my $config = Config::Locale->new(
    identity  => \@values,
    directory => $config_dir
);

my %NMEADATA = ( INIT => 1 );

Readonly my $DEFAULT_GPS_BAUD => 57_600;
Readonly my $DEFAULT_GPS_PORT => '/dev/ttyUSB0';

# the defaults given here match the setup of the testing/development
# equipment and should be changed to match the production equipment
my $gps_port = $config->config->{GPS_PORT} || $DEFAULT_GPS_PORT;
my $gps_baud = $config->config->{GPS_BAUD} || $DEFAULT_GPS_BAUD;

my $gps = open_port( $gps_port, $gps_baud );

# this works for here, needs changed for production
my $replay = Replay->new(
    rules => [ GPSTestRule->new() ],
    config =>
      { QueueClass => 'Replay::EventSystem::Null', StorageMode => 'Memory' }
);
$replay->worm;
$replay->reducer;
$replay->mapper;

# $NEGATE is needed because negative degrees indicate a 'S' latitude
# or a 'W' latitude. $DEGREE_DIVISOR is part of extracting just the
# degrees from the NMEA 0183 format coordinates and is also used as
# a multiplier in part of the code. $MINUTES_CONVERT is the divisor
# used to convert the remaining 'true minutes' over to decimal-degrees
# minutes.
Readonly my $NEGATE          => -1;
Readonly my $DEGREE_DIVISOR  => 100;
Readonly my $MINUTES_CONVERT => 60;
my $buffer = qw//;

my $w = EV::io $gps->{FD}, EV::READ, \&read_port;
Readonly my %CALLBACKS => (
    GGA => \&GGA,
    GLL => \&GLL,
    GSA => \&GSA,
    GSV => \&GSV,
    RMC => \&RMC,
    ZDA => \&ZDA,
    VTG => \&VTG,
);

sub read_port {
    my $port = shift;

    my $temp_val_xxx = qw//;
    my @status       = $gps->status;
    my $data_avail   = $status[ST_INPUT];
    my $temp         = $gps->read($data_avail);
    my @ttt          = [];
    $temp_val_xxx = do { @ttt = split //xsm, $temp; $ttt[0] };
    my $is_sigil = defined($temp_val_xxx) ? $temp_val_xxx : '<>';
    my $is_buffer_sigil = '<>';

    if ($buffer) {
        $temp_val_xxx = do { @ttt = split //xsm, $buffer; $ttt[0] };
        $is_buffer_sigil = defined($temp_val_xxx) ? $temp_val_xxx : '<>';
    }

    if ( $is_sigil eq qw/$/ ) {
        if ( $temp =~ /^[\$].*\r/smxi ) {
            chomp $temp;
            parse($temp);
        }
        elsif ( $is_buffer_sigil eq qw/$/ ) {
            if ( $temp =~ /.*\r/xms ) {
                $temp =~ s/(.*)\r(.*)/$1:$2/gxms;
                $temp =~ s/(.*)\n(.*)/$1$2/gxms;
                $buffer = $buffer . $temp;
                my @b = split /:/xms, $buffer;
                $buffer = join qw/:/, @b[ 1 .. $#b ];
                parse( $b[0] );
            }
            else {
                $buffer = $buffer . $temp;
            }
        }
        else {
            $buffer = $temp;
        }
    }
    else {
        # similar to the final 'else' above, actually.
        # but here we need to see if we're completing
        # $buffer at all or if we have a sigil in $temp
        # and can copy out from there into $buffer.
        if ( $is_buffer_sigil eq qw/$/ ) {
            $temp =~ s/(.*)\r(.*)/$1:$2/gxms;
            $temp =~ s/(.*)\n(.*)/$1$2/gxms;
            $buffer = $buffer . $temp;
        }
        else {
            # do nothing - we ignore this line of input
        }

        $temp_val_xxx = do { @ttt = split //xsm, $buffer; $ttt[0] };
        $is_buffer_sigil = defined($temp_val_xxx) ? $temp_val_xxx : '<>';

        if ( $is_buffer_sigil eq qw/$/ && $buffer =~ /^[\$].*\r/xms ) {
            my @blargh = split /:/xms, $buffer;
            $buffer = join qw/:/, @blargh[ 1 .. $#blargh ];
            parse( $blargh[0] );
        }
    }

    return;
}

sub checksum {
    my @dd = split //xms, shift;
    my $cs = 0;
    foreach my $c (@dd) {
        $cs = $cs ^ ord $c;
    }

    return sprintf '%02X', $cs;
}

sub parse {

   # $CS_MARK is how far from the end the asterisk marking the checksum is
   # It is also used for the length of a given message - all known messages are
   # 3 characters while talker ID's, though generally 2 characters, can be more.
   # (note PGRMN and other vendor-specific prefixes - while we are not working
   # with vendor-specific messages, we have to be careful about them)
    Readonly my $CS_MARK => 3;
    Readonly my $CUT_CS  => 4;

    my $line          = shift;
    my $base          = substr $line, 1, length $line;
    my $base_checksum = substr $base, length($line) - $CS_MARK;

    my $base_data = substr $base, 0, length($line) - $CUT_CS;
    my @data = split /,/xms, $base_data;
    my $type = substr $data[0], ( length $data[0] ) - $CS_MARK;

    if ( checksum($base_data) ne $base_checksum ) {
        return;
    }

    if ( defined $CALLBACKS{$type} ) {
        $CALLBACKS{$type}($base_data);
        emit_message();
    }
    else {
        carp 'Unknown Message: ' . $data[0] . " (type: $type)";
    }
    return;
}

sub GSA {
    my $gdata = shift;
    (
        undef,             $NMEADATA{auto_man_D}, $NMEADATA{dimen},
        $NMEADATA{prn01a}, $NMEADATA{prn02a},     $NMEADATA{prn03a},
        $NMEADATA{prn04a}, $NMEADATA{prn05a},     $NMEADATA{prn06a},
        $NMEADATA{prn07a}, $NMEADATA{prn08a},     $NMEADATA{prn09a},
        $NMEADATA{prn10a}, $NMEADATA{prn11a},     $NMEADATA{prn12a},
        $NMEADATA{pdop},   $NMEADATA{hdop},       $NMEADATA{vdop}
    ) = split /,/xms, $gdata;

    return;
}

sub GSV {
    Readonly my $SS => 3;
    my $line = shift;
    my @gdata = split /,/xms, $line;

    my $sentence = $gdata[2];

    if ( $sentence == 1 ) {
        (
            undef,               $NMEADATA{num_sentences},
            $NMEADATA{sentence}, $NMEADATA{num_sat_vis},
            $NMEADATA{prn01},    $NMEADATA{elev_deg1},
            $NMEADATA{az_deg1},  $NMEADATA{sig_str1},
            $NMEADATA{prn02},    $NMEADATA{elev_deg2},
            $NMEADATA{az_deg2},  $NMEADATA{sig_str2},
            $NMEADATA{prn03},    $NMEADATA{elev_deg3},
            $NMEADATA{az_deg3},  $NMEADATA{sig_str3},
            $NMEADATA{prn04},    $NMEADATA{elev_deg4},
            $NMEADATA{az_deg4},  $NMEADATA{sig_str4}
        ) = split /,/xms, $line;

    }
    elsif ( $sentence == 2 ) {
        (
            undef,               $NMEADATA{num_sentences},
            $NMEADATA{sentence}, $NMEADATA{num_sat_vis},
            $NMEADATA{prn05},    $NMEADATA{elev_deg5},
            $NMEADATA{az_deg5},  $NMEADATA{sig_str5},
            $NMEADATA{prn06},    $NMEADATA{elev_deg6},
            $NMEADATA{az_deg6},  $NMEADATA{sig_str6},
            $NMEADATA{prn07},    $NMEADATA{elev_deg7},
            $NMEADATA{az_deg7},  $NMEADATA{sig_str7},
            $NMEADATA{prn08},    $NMEADATA{elev_deg8},
            $NMEADATA{az_deg8},  $NMEADATA{sig_str8}
        ) = split /,/xms, $line;

    }
    elsif ( $sentence == $SS ) {
        (
            undef,               $NMEADATA{num_sentences},
            $NMEADATA{sentence}, $NMEADATA{num_sat_vis},
            $NMEADATA{prn09},    $NMEADATA{elev_deg9},
            $NMEADATA{az_deg9},  $NMEADATA{sig_str9},
            $NMEADATA{prn10},    $NMEADATA{elev_deg10},
            $NMEADATA{az_deg10}, $NMEADATA{sig_str10},
            $NMEADATA{prn11},    $NMEADATA{elev_deg11},
            $NMEADATA{az_deg11}, $NMEADATA{sig_str11},
            $NMEADATA{prn12},    $NMEADATA{elev_deg12},
            $NMEADATA{az_deg12}, $NMEADATA{sig_str12}
        ) = split /,/xms, $line;
    }

    return;
}

sub GLL {
    my $data = shift;
    (
        undef, $NMEADATA{lat_ddmm_low}, $NMEADATA{lat_NS},
        $NMEADATA{lon_ddmm_low},
        $NMEADATA{lon_EW}, $NMEADATA{time_utc}, $NMEADATA{data_valid}
    ) = split /,/xms, $data;

    return;
}

sub GGA {
    my $line = shift;
    (
        undef,                       $NMEADATA{time_utc},
        $NMEADATA{lat_ddmm},         $NMEADATA{lat_NS},
        $NMEADATA{lon_ddmm},         $NMEADATA{lon_EW},
        $NMEADATA{fixq012},          $NMEADATA{num_sat_tracked},
        $NMEADATA{hdop},             $NMEADATA{alt_meters},
        $NMEADATA{alt_meters_units}, $NMEADATA{height_above_wgs84},
        $NMEADATA{height_units},     $NMEADATA{sec_since_last_dgps_update},
        $NMEADATA{dgps_station_id}
    ) = split /,/xms, $line;
    $NMEADATA{time_utc} =~ s/(\d\d)(\d\d)(\d\d)/$1:$2:$3/gxms;
    return;
}

sub VTG {
    my $line = shift;
    (
        undef, $NMEADATA{true_course},    undef, $NMEADATA{mag_course},
        undef, $NMEADATA{speed_in_knots}, undef, $NMEADATA{speed_in_kph},
        undef, $NMEADATA{mode}
    ) = split /,/xms, $line;
    return;
}

sub RMC {
    my $line = shift;
    (
        undef,                       $NMEADATA{time_utc},
        $NMEADATA{data_valid},       $NMEADATA{lat_ddmm},
        $NMEADATA{lat_NS},           $NMEADATA{lon_ddmm},
        $NMEADATA{lon_EW},           $NMEADATA{speed_over_ground},
        $NMEADATA{course_made_good}, $NMEADATA{ddmmyy},
        $NMEADATA{mag_var},          $NMEADATA{mag_var_EW}
    ) = split /,/xms, $line;

    $NMEADATA{time_utc} =~ s/(\d\d)(\d\d)(\d\d)/$1:$2:$3/gxms;

    return;
}

sub ZDA {
    Readonly my $DAY_LOC   => 2;
    Readonly my $MONTH_LOC => 3;
    Readonly my $YEAR_LOC  => 4;
    Readonly my $TZ_LOC    => 5;

    my $line = shift;
    my @data = split /,/xms, $line;

    $NMEADATA{time_utc} = $data[1];
    $NMEADATA{date} =
      $data[$DAY_LOC] . qw/-/ . $data[$MONTH_LOC] . qw/-/ . $data[$YEAR_LOC];
    $NMEADATA{tz_hours} = $data[$TZ_LOC];
    $NMEADATA{time_utc} =~ s/(\d\d)(\d\d)(\d\d)/$1:$2:$3/gxms;
    return;
}

sub get_position {
    return (
        $NMEADATA{lat_NS}, $NMEADATA{lat_ddmm},
        $NMEADATA{lon_EW}, $NMEADATA{lon_ddmm}
    );
}

sub convert_to_decimal {
    my $var      = shift;
    my $base     = shift;
    my $mult     = 1;
    my $base_deg = 0;
    my $frac_deg = 0;

    if (   $var eq 'W'
        || $var eq 'S' )
    {
        $mult = $NEGATE;
    }

    $base_deg = int( $base / $DEGREE_DIVISOR );
    $frac_deg = $base - ( $base_deg * $DEGREE_DIVISOR );
    return ( ( $base_deg + ( $frac_deg / $MINUTES_CONVERT ) ) * $mult );
}

sub emit_message {
    if (   defined $NMEADATA{time_utc}
        && defined $NMEADATA{lat_ddmm}
        && defined $NMEADATA{lon_ddmm}
        && defined $NMEADATA{true_course}
        && defined $NMEADATA{speed_in_kph} )
    {
        #emit actual message
        my ( $ns, $lat_ddmm, $ew, $lon_ddmm ) = get_position;
        my $time = $NMEADATA{time_utc};
        my $date = $NMEADATA{ddmmyy};
        $date =~ s/(\d\d)(\d\d)(\d\d)/$1\/$2\/$3/gxms;
        my $velocity = $NMEADATA{speed_in_kph};
        my $heading  = $NMEADATA{true_course};

        my $out_lat = convert_to_decimal( $ns, $lat_ddmm );
        my $out_lon = convert_to_decimal( $ew, $lon_ddmm );

        my $message = GPSMessage->new(
            {
                Time_UTC  => $time,
                Velocity  => $velocity,
                Heading   => $heading,
                Latitude  => $out_lat,
                Longitude => $out_lon
            }
        );
        $replay->eventSystem->origin->emit($message);
    }
    else {
        return;
    }
    return;
}

sub open_port {
    Readonly my $NMEA_NUM_DATA_BITS => 8;
    Readonly my $NMEA_NUM_STOP_BITS => 1;
    my $port = shift;
    my $baud = shift;

    my $portobj = Device::SerialPort->new($port);
    $portobj->baudrate($baud);
    $portobj->parity('none');
    $portobj->databits($NMEA_NUM_DATA_BITS);
    $portobj->stopbits($NMEA_NUM_STOP_BITS);
    $portobj->write_settings;
    return $portobj;
}

$replay->eventSystem->run;
__END__

