#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;
use YAML::Syck;


use Artemis::Model 'model';
use Artemis::Config;
use Artemis::Schema::TestTools;

use File::Temp;
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
$testcontrol->cfg(Artemis::Config::subconfig);
my $retval;
my $time = time();

my $ft       = File::Temp->new(CLEANUP => 1);
my $syncfile = $ft->filename;
open my $fh, ">", $syncfile or die "Can not open syncfile $syncfile: $!";
print $fh "2";
close $fh;


my $pid=fork();
if ($pid==0) {
        sleep(5); # make this process the child

        $testcontrol->wait_for_sync($syncfile);
        exit 0;

} else {
        eval{
                local $SIG{ALRM}=sub{die("timeout of 5 seconds reached while waiting for reboot test.");};
                alarm(10);
                
                $retval = $testcontrol->wait_for_sync($syncfile);
                
                alarm(0);
        };
        is($@, '', 'Get state messages in time');
        waitpid($pid,0);
        
        is($retval, 0, 'Waiting for sync');
        ok( (time() - $time) >= 5, 'Waited as long as child, probably in sync');
        ok( (time() - $time) <= 6, 'Waited only one second longer than child, probably in sync');
}




done_testing();
