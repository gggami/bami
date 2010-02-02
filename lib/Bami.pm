package Bami;
use strict;
use warnings;
use base qw(Class::Accessor);

use AnyEvent;
use AnyEvent::IRC;
use AnyEvent::IRC::Client;
use AnyEvent::IRC::Connection;
use Test::More;
use YAML;
use Path::Class;
use Text::MeCab;
use UNIVERSAL::require;

use Bami::DBI;

__PACKAGE__->mk_accessors(
    qw(server port channel nick password datasource dbi),
    qw(say_interval say_delay say_special_threshold last_say_time),
);


sub new {
    my ($class,%args) = @_;
    my $conf = YAML::LoadFile($args{conf});
    bless $conf, $class;
}

sub process {
    my $instance = shift;
    my $c = AnyEvent->condvar;
    my $con;
    my $mecab = Text::MeCab->new;
    $instance->dbi(Bami::DBI->new(%{$instance->datasource}));

    $con = AnyEvent::IRC::Client->new;
    $con->reg_cb(
        'connect' => sub {
            my ($con, $err) = @_;
            if (defined $err) {
                BAIL_OUT "Connect ERROR! => $err\n";
                $c->broadcast;
            } else {
                print "connected \n";
            }
            $con->send_msg("NICK", $instance->nick);
            $con->send_msg ("USER", $instance->nick, "*", "0", $instance->nick);
        },
        'registered' => sub {
            my ($self) = @_;
            print "join " . $instance->channel . "\n";
            $con->enable_ping(60);
            $con->send_srv("JOIN", $instance->channel);

        },
        irc_privmsg => sub {
            my ($self, $msg) = @_;
            _debug($msg);

            my $t = time;
            if ( $instance->last_say_time &&
                    ($instance->last_say_time + $instance->say_interval) > $t ) {
                return;
            }

            my $stmt = $msg->{params}->[1];
            my $user = ((split /!/, $msg->{prefix})[0]);  
            $user =~ s/_+$//; 

            my $reply;
            unless ( $t % $instance->say_special_threshold ) {
                $reply = $instance->select_special_msg($user);
            }

            unless ( $reply ) {
                my @symbols;
                for (my $node = $mecab->parse($stmt); $node; $node = $node->next) {
                    print $node->surface, "\n";
                    push @symbols, {
                        surface => $node->surface,
                        feature => $node->feature,
                    };
                }
                _debug(\@symbols);
                for my $s (@symbols) {
                    if ((split /,/, $s->{feature})[0] eq '名詞') {
                        $reply = $instance->select_msg($s->{surface});
                        last if $reply;
                    }
                }
                unless ( $reply ) {
                    $reply = $instance->select_random_msg();
                }
            }

            sleep $instance->say_delay;
            $con->send_chan($instance->channel, "NOTICE", $instance->channel, $reply);
            $instance->last_say_time($t);
        },
        disconnect => sub {
            BAIL_OUT "Oh, got a disconnect: $_[1], exiting...\n";
        },
    );

    $con->connect(
        $instance->server,
        $instance->port,
        {
            nick     => $instance->nick,
            user     => $instance->nick,
            real     => $instance->nick,
            password => $instance->password,
        },
    );

    $c->recv;
}

sub select_msg {
    my ($self,@bind) = @_;
    my $sth = $self->dbi->execute("select * from msg where match(keyword) against(?) order by RAND() limit 0, 1",@bind);

    my $records = $sth->fetchall_arrayref( +{} );
    $sth->finish;
    if ($records) {
        _debug($records->[0]);
        return $records->[0]->{msg};
    }
}

sub select_special_msg {
    my ($self,@bind) = @_;
    my $sth = $self->dbi->execute("select * from special_msg where nick = ? order by RAND() limit 0, 1",@bind);
    my $records = $sth->fetchall_arrayref( +{} );
    $sth->finish;
    if ($records) {
        _debug($records->[0]);
        return $records->[0]->{msg};
    }
}

sub select_random_msg {
    my ($self) = @_;
    my $sth = $self->dbi->execute("select * from msg where keyword is null order by RAND() limit 0, 1");
    my $records = $sth->fetchall_arrayref( +{} );
    $sth->finish;
    if ($records) {
        return $records->[0]->{msg};
    }
}

our $Debug = 1;
sub _debug {
    my $msg = shift;
    if ($Debug) {
        $msg = ' ' unless defined $msg;
        if (ref $msg) {
            Data::Dumper->require;
            warn Data::Dumper::Dumper($msg);
        } else {
            warn $msg;
        }
    }
}


1;
