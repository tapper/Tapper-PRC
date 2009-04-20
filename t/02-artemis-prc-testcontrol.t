#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;

use Artemis::Model 'model';
use Artemis::Schema::TestTools;



use Test::More tests => 1;

# (XXX) need to find a way to include log4perl into tests to make sure no
# errors reported through this framework are missed
my $string = "
log4perl.rootLogger           = INFO, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);


BEGIN { use_ok('Artemis::PRC::Testcontrol'); }


