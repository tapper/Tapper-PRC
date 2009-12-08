#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;
use YAML::Syck;


use Artemis::Model 'model';
use Artemis::Config;
use Artemis::Schema::TestTools;


use Test::More;

# (XXX) need to find a way to include log4perl into tests to make sure no
# errors reported through this framework are missed
my $string = "
log4perl.rootLogger           = FATAL, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);


BEGIN { use_ok('Artemis::PRC::Testcontrol'); }

SKIP:
{
        skip 'Can not test syncing without peer',1 unless $ENV{ARTEMIS_SYNC_TESTING};
        my $testcontrol = Artemis::PRC::Testcontrol->new();
        $testcontrol->cfg(Artemis::Config::subconfig);
        my $retval = $testcontrol->wait_for_sync(['wotan']);
        is($retval, 0, 'Synced');
}
done_testing();
