#!/usr/bin/env perl

use strict;
use warnings;

use Sys::Hostname;
use Artemis::PRC::Testcontrol;

if (@ARGV and $ARGV[0] eq "stop") {
        exit 0;
}

# bearable since it never really changes
my $logconf = 'log4perl.rootlogger = DEBUG, Screen
log4perl.appender.Screen = Log::Log4perl::Appender::Screen
log4perl.appender.Screen.layout = PatternLayout
# date package category - message in  last 2 components of filename (linenumber) newline
log4perl.appender.Screen.layout.ConversionPattern = %d %p %c - %m in %F{2} (%L)%n';
Log::Log4perl::init(\$logconf);


my $prc = new Artemis::PRC::Testcontrol;
$prc->run();

