#! /usr/bin/env perl

use strict;
use warnings;

use Test::MockModule;
use YAML::Syck;

use Log::Log4perl;

use Test::More tests => 5;

# (XXX) need to find a way to include log4perl into tests to make sure no
# errors reported through this framework are missed
my $string = "
log4perl.rootLogger           = INFO, root
log4perl.appender.root        = Log::Log4perl::Appender::Screen
log4perl.appender.root.stderr = 1
log4perl.appender.root.layout = SimpleLayout";
Log::Log4perl->init(\$string);


BEGIN { use_ok('Artemis::PRC'); }


my $prc = new Artemis::PRC;

my ($error, $output) = $prc->log_and_exec('echo test');
is ($output,'test','log_and_exec, array mode');

$prc->{cfg} = {test_run => 1234, mcp_server => 'localhost', port => 1337};
my $pid=fork();
if ($pid==0) {
        sleep(2); #bad and ugly to prevent race condition
        $prc->mcp_inform({state => "test"});

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

        my $msg = Load($content);
        is_deeply($msg, {testrun_id => 1234, prc_number => 0, state => "test"}, 'sending message to server, no virtualisation');

        waitpid($pid,0);
}
