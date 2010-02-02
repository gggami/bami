#!/usr/bin/perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Bami;

my $conf = shift @ARGV;
die unless $conf;

my $bami = Bami->new(conf => $conf);
$bami->process;

__END__
