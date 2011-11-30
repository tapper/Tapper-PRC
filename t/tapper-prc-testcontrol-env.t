#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;
use YAML::Syck;

use Log::Log4perl;

use Test::More;
use Test::Deep;
use Test::MockModule;

use File::Temp;

# (XXX) need to find a way to include log4perl into tests to make sure no
# errors reported through this framework are missed
my $string = "
log4perl.rootLogger           = FATAL, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);


BEGIN { use_ok('Tapper::PRC::Testcontrol'); }

my $testcontrol = Tapper::PRC::Testcontrol->new();
my $output_dir = File::Temp::tempdir( CLEANUP => 1 );
$testcontrol->cfg({test_run => 1234,
                   mcp_server => 'localhost',
                   report_server => 'localhost',
                   hostname => 'localhost',
                   reboot_counter => 0,
                   max_reboot => 0,
                   guest_number => 0,
                   syncfile => '/dev/null', # just to check if set correctly in ENV
                   paths => {output_dir => $output_dir},
                   testprogram_list => [{ program             => '/bin/true',
                                          chdir               => "/my/chdir/affe/zomtec",
                                          environment         => { AFFE => "ZOMTEC"},
                                          runtime             => 72000,
                                          timeout_testprogram => 129600,
                                          parameters          => ['--tests', '-v'],
                                        }],
                  });
is($testcontrol->cfg->{test_run}, 1234, 'Setting attributes');
my $retval;

# Mock actual execution of testprogram
my @execute_options;
my $mock_testcontrol = Test::MockModule->new('Tapper::PRC::Testcontrol');
$mock_testcontrol->mock('testprogram_execute',sub{(undef, @execute_options) = @_;return 0});
$mock_testcontrol->mock('mcp_inform',sub{return 0;});
$retval = $testcontrol->testprogram_execute();
is($retval, 0, 'Mocking testprogram_execute');

$retval = $testcontrol->control_testprogram();
is($retval, 0, 'Running control_testprogram');

is($execute_options[0]{chdir}, "/my/chdir/affe/zomtec", "providing chdir");
is($execute_options[0]{environment}{AFFE}, "ZOMTEC", "providing environment");

done_testing();
