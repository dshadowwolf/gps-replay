use Test::Most tests => 1;

use lib 'lib';
use lib '/home/skylos/Replay/lib';
use GPSMessage;
use Replay::Message;

my $message = GPSMessage->new(
    Time_UTC  => 5,
    Velocity  => 6,
    Heading   => 7,
    Latitude  => 8,
    Longitude => 9,
)->marshall;

    use Data::Dumper;
    warn Dumper $message;

my $clone = Replay::Message->new($message);

delete $message->{CreatedTime};
delete $message->{EffectiveTime};
delete $message->{ReceivedTime};
delete $message->{Replay};
delete $message->{UUID};
is_deeply $message,
    {
    MessageType => 'GPS',
    Message => {
        Longitude => 9,
        Latitude  => 8,
        Heading   => 7,
        Velocity  => 6,
        Time_UTC  => 5
    }
    },
    'message is as expected';

