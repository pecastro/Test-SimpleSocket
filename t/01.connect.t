use strict;
use warnings;

use FindBin::libs;
use Test::More;
use Test::SimpleSocket;
use Data::Dumper;
use Carp::Always;

# Start a local server
# Tell it out to reply
# Tell it to expect a specific string
# Tell it how to reply to that string

my $hello_msg = "SimpleSocket server\n";
my $bye_msg   = "SimpleSocket server says bye bye\n";
my $list_expect = "ask the server to list\n";
my $list_reply = "server replies\n";

my $test = Test::SimpleSocket->new(
    server_options => {
        Proto => 'tcp',
        Listen   => 1,
        Reuse    => 1,
    },
    hello_msg => $hello_msg,
    server_actions => {
        list => {
            expect => $list_expect,
            reply  => $list_reply,
        },
    },
    bye_msg => $bye_msg,
) or die "death $!";

isa_ok($test,'Test::SimpleSocket');

$test->start;
my $port = $test->server->sockport;

ok($port,"Listening in a random port");
note "Started server in port $port";

sleep 1;
# Talk to our test server
my $sock = IO::Socket::INET->new(PeerPort => $port,
                              Proto => 'tcp',
                              PeerAddr => 'localhost'
                          )
    || IO::Socket::INET->new(PeerPort => $port,
                             Proto => 'tcp',
                             PeerAddr => '127.0.0.1'
                         )
    or die "$! (maybe your system does not have a localhost at all, 'localhost' or 127.0.0.1)";

isa_ok($sock,'IO::Socket::INET',"Got a socket");

is(read_socket($sock),$hello_msg,"Server says hello");

print $sock $list_expect;
is(read_socket($sock),$list_reply,"Server replies to list request");

$sock->close;

#$test->stop;
done_testing;


sub read_socket {
    my ($socket) = @_;
    my $read = <$socket>;
    return $read;
}
