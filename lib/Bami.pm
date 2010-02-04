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
use Time::HiRes qw(sleep);

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

            my $stmt = $msg->{params}->[1];
            my $user = ((split /!/, $msg->{prefix})[0]);
            $user =~ s/_+$//; 
            my $symbols = $instance->parse_msg($stmt);

            my $reply = $instance->select_first_msg($stmt);
            return $instance->reply($con,$reply,0.2) if $reply;

            my $t = time;
            if ( $instance->last_say_time &&
                    ($instance->last_say_time + $instance->say_interval) > $t ) {
                return;
            }

            unless ( $t % $instance->say_special_threshold ) {
                $reply = $instance->select_special_msg($user);
            }

            unless ( $reply && (my $words = $instance->get_words($symbols,'名詞')) ) {
                for my $w (@$words) {
                    $reply = $instance->select_msg($w);
                    last if $reply;
                }
            }

            $reply ||= $instance->select_random_msg();
            $instance->reply($con,$reply);
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

sub reply {
    my ($self,$con,$reply,$delay) = @_;
    $delay = defined $delay ? $delay : $self->say_delay;
    sleep $delay;
    $con->send_chan($self->channel, "NOTICE", $self->channel, $reply);
}

sub parse_msg {
    my ($self,$stmt) = @_;
    my $mecab = Text::MeCab->new;
    my @symbols;
    for (my $node = $mecab->parse($stmt); $node; $node = $node->next) {
        print $node->surface, "\n";
        push @symbols, {
            surface => $node->surface,
            feature => $node->feature,
        };
    }
    _debug(\@symbols);
    return @symbols ? \@symbols : [];
}

sub get_words {
    my ($self,$symbols,$feature) = @_;
    my @words;
    for my $s (@$symbols) {
        if ((split /,/, $s->{feature})[0] eq $feature) {
            push @words, $s->{surface};
        }
    }
    return @words ? \@words : [];
}

sub select_first_msg {
    my ($self,@bind) = @_;
    my $sth = $self->dbi->execute("select * from messages where weight = 2 and match(keyword) against(?) order by RAND() limit 1",@bind);
    my $records = $sth->fetchall_arrayref( +{} );
    $sth->finish;
    if ($records) {
        _debug($records->[0]);
        return $records->[0]->{msg};
    }
}

sub select_msg {
    my ($self,@bind) = @_;
    my $sth = $self->dbi->execute("select * from messages where match(keyword) against(?) order by RAND() limit 1",@bind);
    my $records = $sth->fetchall_arrayref( +{} );
    $sth->finish;
    if ($records) {
        _debug($records->[0]);
        return $records->[0]->{msg};
    }
}

sub select_special_msg {
    my ($self,@bind) = @_;
    my $sth = $self->dbi->execute("select * from special_messages where nick = ? order by RAND() limit 1",@bind);
    my $records = $sth->fetchall_arrayref( +{} );
    $sth->finish;
    if ($records) {
        _debug($records->[0]);
        return $records->[0]->{msg};
    }
}

sub select_random_msg {
    my ($self) = @_;
    my $sth = $self->dbi->execute("select * from messages where keyword is null order by RAND() limit 1");
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
