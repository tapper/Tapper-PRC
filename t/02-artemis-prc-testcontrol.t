#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;

use Artemis::Model 'model';
use Artemis::Schema::TestTools;



use Test::More tests => 2;

# (XXX) need to find a way to include log4perl into tests to make sure no
# errors reported through this framework are missed
my $string = "
log4perl.rootLogger           = INFO, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);


BEGIN { use_ok('Artemis::PRC::Testcontrol'); }



my $mock_control = new Test::MockModule('Artemis::PRC::Testcontrol');
$mock_control->mock('nfs_mount', sub { return(0);});

my $mock_prc = new Test::MockModule('Artemis::PRC');
$mock_prc->mock('log_and_exec', sub { return(0);});

$ENV{ARTEMIS_CONFIG} = 't/files/artemis.config';

my $pid=fork();
if ($pid==0) {
        sleep(2); #bad and ugly to prevent race condition

        my $testcontrol = new Artemis::PRC::Testcontrol;
        $testcontrol->run();
        exit 0;

} else {
        my $server = IO::Socket::INET->new(Listen    => 5,
                                           LocalPort => 1337);
        ok($server, 'create socket');
        my $content;
        eval{
                $SIG{ALRM}=sub{die("timeout of 5 seconds reached while waiting for file upload test.");};
                alarm(5);
                my $msg_sock = $server->accept();
                while (my $line=<$msg_sock>) {
                        $content.=$line;
                }
                alarm(0);
        };
        is($@, '', 'Getting data from file upload');

        my $msg = "prc_number:0,start-testprogram\n";
        is($content, $msg, 'sending message to server, no virtualisation');

        waitpid($pid,0);
}


