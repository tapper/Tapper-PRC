#!/home/artemis/perl510/bin/perl

use strict;
use warnings;

use Sys::Hostname;
use Artemis::PRC::Testcontrol;

if (@ARGV and $ARGV[0] eq "stop") {
        exit 0;
}

my $prc = new Artemis::PRC::Testcontrol;
$prc->run();

