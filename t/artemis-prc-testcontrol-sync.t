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

my $testcontrol = Artemis::PRC::Testcontrol->new();
isa_ok($testcontrol, 'Artemis::PRC::Testcontrol', 'New object');

$testcontrol->cfg({test_run => 1234,
                   mcp_server => 'localhost',
                   report_server => 'localhost',
                   hostname => 'localhost',
                   reboot_counter => 0,
                   max_reboot => 0,
                   guest_number => 0,
                   syncfile => '/dev/null', # just to check if set correctly in ENV
                  });
is($testcontrol->cfg->{test_run}, 1234, 'Setting attributes');
my $retval;

SKIP:
{
        skip 'Can not test syncing without peer',1 unless $ENV{ARTEMIS_SYNC_TESTING};
        $testcontrol->cfg(Artemis::Config::subconfig);
        $retval = $testcontrol->wait_for_sync(['wotan']);
        is($retval, 0, 'Synced');
}


done_testing();
