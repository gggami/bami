package Bami::DBI;
use strict;
use warnings;
use DBI;
use UNIVERSAL::require;

sub new {
    my ($class,%args) = @_;
    bless {%args}, $class;
}

sub execute {
    my ( $self, $query, @args ) = @_;
    my $dbh = $self->_get_master_dbh();

    _debug($query);
    _debug(\@args);

    my $sth = $dbh->prepare($query);
    unless ( $sth->execute( @args ) ) {
        warn $sth->errstr;
    }
    return $sth;
}

sub _get_master_dbh {
    my $self = shift;
    #DBI->trace(2);
    my $dbh = DBI->connect(
        $self->{dsn}, $self->{user}, $self->{password},
        { RaiseError => 1, PrintError => 0, AutoCommit => 1, }
    ) or die $DBI::errstr;
    #$dbh->do('SET NAMES UTF8');
    return $dbh;
};

our $Debug = 1;
sub _debug {
    my $msg = shift;
    if ($Debug) {
        $msg = '' unless defined $msg;
        if (ref $msg) {
            Data::Dumper->require;
            warn Data::Dumper::Dumper($msg);
        } else {
            warn $msg;
        }
    }
}

1;
