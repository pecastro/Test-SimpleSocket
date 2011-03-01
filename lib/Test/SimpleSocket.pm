package Test::SimpleSocket;

#  ABSTRACT: a totally cool way to do totally great stuff

our $VERSION   = '0.001';
$VERSION = eval $VERSION;
our $AUTHORITY = 'cpan:PECASTRO';

use Moose;

use AnyEvent;
use IO::Pipe;
use IO::Socket::INET;
use Proc::Fork;
use List::Util 'first';
use IO::Socket;

#use Test::Builder;
has 'debug' => ( is => 'ro', isa => 'Int');

has 'server_options' => ( is => 'rw', isa => 'HashRef', required => 1);
has 'server' => ( is => 'rw', isa => 'IO::Socket', builder => '_build_server');
has 'client' => ( is => 'rw', isa => 'IO::Socket::INET');
has 'hello_msg' => ( is => 'rw', isa => 'Str');
has 'server_actions' => ( is => 'rw', isa => 'HashRef');
has 'bye_msg' => ( is => 'rw', isa => 'Str');

# list of the methods at which we'll randomly disconnect
has 'random_die_at' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] });

# list of the methods at which we'll just disconnect
has 'die_at' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] });

has 'pipe' => ( is => 'rw', isa => 'IO::Pipe');
has 'message_queue' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] });


sub _build_server {
    my ($self, $params ) = @_;

    my $temp_server = IO::Socket::INET->new( %{ $self->server_options } )
        or die "can't build server :$!";
    # I think that just returning might be to fast for it ?!?!?
    print "Building server...\n";
    return $temp_server;
}


=head2 start

Loads up the data provided in the method to the various components of a simple responder.
We have an hello_msg and a list of server_actions, and .... bye_msg

=cut

sub start {
    my ($self) = @_;
    $self->create_server_actions_methods();
    sleep 1;
    print "About to start server $$ ...\n";

    $self->pipe( IO::Pipe->new );
    run_fork {
        parent {
            my $child = shift;
            $self->pipe->writer;
            # waitpid $child,0; # wait for child
        }
        child {
            print "Forked child $$ ...\n";
            $self->pipe->reader;

            my $parent_ready = AnyEvent->condvar;
            # Set up parent comunication
            my $parent_event = $self->setup_parent_child_comms($parent_ready);

                my $w1 = AnyEvent->io (
                    fh   => $self->server,
                    poll => "r",
                    cb   => sub {
                        my $client = $self->server->accept;
                        $self->client($client);
                        $self->handle_client();
                    }
                );

            $parent_ready->recv;
            $self->listen_to_parent;
            print "Whitin While loop...\n";
            }
    };
    print "About to exit the fork $$ ...\n";
}


=head2 handle_client

Whilst I handle the client , my father might want me to do something for him...

=cut

sub handle_client {
    my ($self) = @_;

    # Say hello
    $self->client->print($self->hello_msg);

    # #PEC TODO wrap this in an alarm
    #print "Client's still connected...\n";
    while (
        $self->client->connected
            && $self->listen_to_parent
            && defined(my $line = $self->client->getline)
    ) {
        $self->match_command($line);
        print "done handling the client 0...\n";
    }
    print "done handling the client 1...\n";
}


sub match_command {
    my ($self,$line) = @_;

    my $match_method="";
    my $reply_command;

    foreach my $action (keys %{$self->server_actions}) {
        if ($line =~ $self->server_actions->{$action}->{expect}) {
            $match_method = $action;
            $reply_command = $self->can($match_method . "_reply") if $match_method;
        }
    }

    if ($reply_command) {
        &$reply_command
    }
    else {
        $self->client->print("# Unknown command.\n");
    }
    print "done matching the command for action $match_method...\n";
}


sub stop {
    my ($self) = @_;
    $self->speak_to_child("_stop_server");
}

sub _stop_server {
    my ($self) = @_;
    print "Should be exiting NOW...\n";
    $self->client->close;
    exit 0;

}


=head2 setup_parent_child_comms

=cut

sub setup_parent_child_comms {
    my ($self,$parent_ready) = @_;

    print "I'm setup_parent_child_comms ...\n";
    my $parent = $self->pipe;

    my $w = AnyEvent->io (
        fh   => $parent,
        poll => "r",
        cb   => sub {
            print "I'm setup_parent_child_comms ...\n";
            my $line = <$parent>;
            if ($line) {
                print "I'm populating the message queue with line $line...\n";
                push @{$self->message_queue},$line;
                print "pushed line into message_queue\n";
                $parent_ready->send;
            } else {
                print "Didn't push a line into message_queue\n";
            }
        }
    );

}


=head2 listen_to_parent


=cut

sub listen_to_parent {
    my ($self) = @_;

    if (defined( my $parent_said = shift @{ $self->message_queue })) {
        chomp $parent_said;
        print "CHILD<-PARENT : $parent_said\n";
        my $selfdo = $self->can($parent_said);
        return &$selfdo;
    } else {
        print "CHILD : Didn't hear from parent...\n";
    }
    return 1;
}

=head2 speak_to_child

=cut

sub speak_to_child {
    my ($self,$sentence) = @_;

    my $child = $self->pipe;
    print "FATHER->CHILD : $sentence\n";
    print $child $sentence . "\n";
}


### Perhaps this code could become it's own module ###

my $default_sub_ref_reply_method = sub {
    my ($args,$action)= @_;
    return sub {
        my ($self) = @_;
        print "Running action $action ..\n";

        #  Check if we might want to die whilst we perform
        my $random_die_at = ( first { $_ eq $action }
                                  @{ $self->random_die_at } ) || '';
        my $die_at = ( first { $_ eq $action }
                           @{ $self->die_at } ) || '';
        my $command_length = length($args->{$action}{reply});
        # PEC TODO, If random is 1 the client dies and throws a different message
        my $random = int(rand( $command_length ));
        my $counter=0;
        $self->debug && print "stop $random_die_at : length $command_length : random $random\n";

        # print in "slow" motion
        # so we can interrupt as well
        for my $p ( split(//,$args->{$action}{reply}) ) {
            if ( $die_at || ( $random_die_at && $random == $counter ) ) {
                #$self->client->print("\n"); # Send a new line to confuse matters even more.
                $self->_stop_server ;
            } else {
                $self->client->print($p);
            }
            $counter++;
        }
    }
};


sub create_server_actions_methods {
    my ($self,$args) = @_;

    $args ||= $self->server_actions;

    $self->_server_actions_validate_params($args);

    # Cycle through the action list and create the "reply" methods
    foreach my $action (keys %{$args}) {

        if (ref $args->{$action}{reply} eq 'CODE' ) {
            $self->meta->add_method( $action . "_reply" => $args->{$action}{reply} );
        } else {
            $self->meta->add_method( $action . "_reply" => $default_sub_ref_reply_method->($args,$action) );
        }
     }
}

# Stub to be filled with validating code .
sub _server_actions_validate_params {
    my ($self,$args) = @_;

    # check if the die methods have any matching params
    my %a1;
    if (defined $self->random_die_at && defined $self->die_at) {
        # Search for potential intersection
        $a1{$_}++ for @{$self->random_die_at};
        my @a2 = grep { defined $a1{$_} || () } @{$self->die_at};
        die "Can't have both args (random_die_at,die_at) sharing common methods (@a2) to die at..."
            if @a2;
    }
    return;
}

sub DESTROY {
    my $self = shift;
    print "DESTROYING ".__PACKAGE__."...\n";
    $self->stop;

}

1;

