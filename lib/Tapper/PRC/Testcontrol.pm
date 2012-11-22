package Tapper::PRC::Testcontrol;

use 5.010;
use warnings;
use strict;

use IPC::Open3;
use File::Copy;
use File::Temp qw/tempdir/;
use Moose;
use YAML 'LoadFile';
use File::Basename 'dirname';
use English '-no_match_vars';
use IO::Handle;
use File::Basename 'basename';

use Tapper::Remote::Config;
# ABSTRACT: Control running test programs

extends 'Tapper::PRC';

our $MAXREAD = 1024;  # read that much in one read

=head1 FUNCTIONS

=cut

=head2 capture_handler_tap

This function is a handler for the capture function. It handles capture
requests of type 'tap'. This means the captured output is supposed to be
TAP already and therefore no transformation is needed.

@param file handle - opened file handle

@return string - output in TAP format
@return error  - die()

=cut

sub capture_handler_tap
{
        my ($self, $filename) = @_;
        my $content;
        open my $fh, '<', $filename or die "Can not open $filename to send captured report";
        { local $/; $content = <$fh> }
        close $fh;
        return $content;
}


=head2 send_output

Send the captured TAP output to the report receiver.

@param string - TAP text

@return success - 0
@return error   - error string

=cut

sub send_output
{
        my ($self, $captured_output, $testprogram) = @_;

        # add missing minimum Tapper meta information
        my $headerlines = "";
        $headerlines .= "# Tapper-suite-name: ".basename($testprogram->{program})."\n" unless $captured_output =~ /\# Tapper-suite-name:/;
        $headerlines .= "# Tapper-machine-name: ".$self->cfg->{hostname}."\n"          unless $captured_output =~ /\# Tapper-machine-name:/;
        $headerlines .= "# Tapper-reportgroup-testrun: ".$self->cfg->{test_run}."\n"   unless $captured_output =~ /\# Tapper-reportgroup-testrun:/;

        $captured_output =~ s/^(1\.\.\d+\n)/$1$headerlines/m;

        my ($error, $message) = $self->tap_report_away($captured_output);
        return $message if $error;
        return 0;

}


=head2 testprogram_execute

Execute one testprogram. Handle all error conditions.

@param hash ref - contains all config options for program to execute
* program     - program name
* timeout     - timeout in seconds
* outdir      - output directory
* parameters  - arrayref of strings - parameters for test program
* environment - hashref of strings - environment variables for test program
* chdir       - string - where to chdir before executing the testprogram

@return success - 0
@return error   - error string

=cut

sub testprogram_execute
{
        my ($self, $test_program) = @_;

        my $program  = $test_program->{program};
        my $chdir    = $test_program->{chdir};
        my $progpath =  $self->cfg->{paths}{testprog_path};
        my $output   =  $program;
        $output      =~ s|[^A-Za-z0-9_-]|_|g;
        $output      =  $test_program->{out_dir}.$output;


        # make relative paths absolute
        $program=$progpath.$program if $program !~ m(^/);

        # try to catch non executables early
        return("tried to execute $program which does not exist") unless -e $program;


        if (not -x $program) {
                system ("chmod", "ugo+x", $program);
                return("tried to execute $program which is not an execuable and can not set exec flag") if not -x $program;
        }

        return("tried to execute $program which is a directory") if -d $program;
        return("tried to execute $program which is a special file (FIFO, socket, device, ..)") unless -f $program or -l $program;

        foreach my $file (@{$test_program->{upload_before} || [] }) {
                my $target_name =~ s|[^A-Za-z0-9_-]|_|g;
                $target_name = $test_program->{out_dir}.'/before/'.$target_name;
                File::Copy::copy($file, $target_name);
        }

        $self->log->info("Try to execute test suite $program");

        pipe (my $read, my $write);
        return ("Can't open pipe:$!") if not (defined $read and defined $write);

        my $pid=fork();
        return( "fork failed: $!" ) if not defined($pid);

        if ($pid == 0) {        # hello child
                close $read;
                %ENV = (%ENV, %{$test_program->{environment} || {} });
                open (STDOUT, ">", "$output.stdout") or syswrite($write, "Can't open output file $output.stdout: $!"),exit 1;
                open (STDERR, ">", "$output.stderr") or syswrite($write, "Can't open output file $output.stderr: $!"),exit 1;
                if ($chdir) {
                        if (-d $chdir) {
                                chdir $chdir;
                        } elsif ($chdir == "AUTO" and $program =~ m,^/, ) {
                                chdir dirname($program);
                        }
                }
                exec ($program, @{$test_program->{argv} || []}) or syswrite($write,"$!\n");
                close $write;
                exit -1;
        } else {
                # hello parent
                close $write;
                my $killed;
                # (XXX) better create a process group an kill this
                local $SIG{ALRM}=sub {
                                      $killed = 1;
                                      kill (15, $pid);
                                      
                                      # allow testprogram to react on SIGTERM
                                      my $grace_period = $ENV{HARNESS_ACTIVE} ? 1 : 60; # wait less during test
                                      while ($grace_period and (kill 0, $pid)) {
                                              sleep 1;
                                              $grace_period--;
                                      }
                                      kill (9, $pid);
                                     };
                alarm ($test_program->{timeout});
                waitpid($pid,0);
                my $retval = $?;
                alarm(0);

                foreach my $file (@{$test_program->{upload_after} || [] }) {
                        my $target_name =~ s|[^A-Za-z0-9_-]|_|g;
                        $target_name = $test_program->{out_dir}.'/after/'.$target_name;
                        File::Copy::copy($file, $target_name);
                }
                if ($test_program->{capture}) {
                        my $captured_output;
                        given($test_program->{capture}) {
                                when ('tap') { eval { $captured_output = $self->capture_handler_tap("$output.stdout")}; return $@ if $@;};
                                default      { return "Can not handle captured output, unknown capture type '$test_program->{capture}'. Valid types are (tap)"};
                        }
                        my $error_msg =  $self->send_output($captured_output, $test_program);
                        return $error_msg if $error_msg;
                }

                return "Killed $program after $test_program->{timeout} seconds" if $killed;
                if ( $retval ) {
                        my $error;
                        sysread($read,$error, $MAXREAD);
                        return("Executing $program failed:$error");
                }
        }
        return 0;
}


=head2 guest_start

Start guest images for virtualisation. Only Xen guests can be started at the
moment.

@return success - 0
@return error   - error string

=cut

sub guest_start
{
        my ($self) = @_;
        my ($error, $retval);
 GUEST:
        for (my $i=0; $i<=$#{$self->cfg->{guests}}; $i++) {
                my $guest = $self->cfg->{guests}->[$i];
                if ($guest->{exec}){
                        my $startscript = $guest->{exec};
                        $self->log->info("Try to start virtualisation guest with $startscript");
                        if (not -s $startscript) {
                                $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                 error => qq(Startscript "$startscript" is empty or does not exist at all)});
                                next GUEST;
                        } else {
                                # just try to set it executable always
                                if (not -x $startscript) {
                                        unless (system ("chmod", "ugo+x", $startscript) == 0) {
                                                $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                                 error =>
                                                                 return qq(Unable to set executable bit on "$startscript": $!)
                                                                });
                                                next GUEST;
                                        }
                                }
                        }
                        if (not system($startscript) == 0 ) {
                                $retval = qq(Can't start virtualisation guest using startscript "$startscript");
                                $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                 error => $retval});
                                next GUEST;
                        }
                } elsif ($guest->{svm}){
                        my $xm = `which xm`; chomp $xm;
                        $self->log->info("Try load Xen guest described in ",$guest->{svm});
                        ($error, $retval) =  $self->log_and_exec($xm, 'create', $guest->{svm});
                        if ($error) {
                                $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                 error      => $retval});
                                next GUEST;
                        }
                } elsif ($guest->{xen}) {
                        $self->log->info("Try load Xen guest described in ",$guest->{xen});

                        my $guest_file = $guest->{xen};
                        if ($guest_file =~ m/^(.+)\.(?:xl|svm)$/) {
                            $guest_file = $1;
                        }

                        my $xm = `which xm`; chomp $xm;
                        my $xl = `which xl`; chomp $xl;

                        if ( -e $xl ) {
                                ($error, $retval) =  $self->log_and_exec($xl, 'create', $guest_file.".xl");
                                if ($error) {
                                        $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                         error      => $retval});
                                        next GUEST;
                                }
                        } elsif ( -e $xm ) {
                                ($error, $retval) =  $self->log_and_exec($xm, 'create', $guest_file.".svm");
                                if ($error) {
                                        $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                         error      => $retval});
                                        next GUEST;
                                }
                        } else {
                                $retval =  "Can not find both xm and xl.";
                                $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                 error      => $retval});
                                next GUEST;
                        }
                }
                $self->mcp_send({prc_number => ($i+1), state => 'start-guest'});
        }
        return 0;
}

=head2 create_log

Checks whether fifos for guest logging exists and creates them if
not. Existing files of wrong type are deleted.

@retval success - 0
@retval error   - error string

=cut

sub create_log
{
        my ($self) = @_;
        my $testrun = $self->cfg->{test_run};
        my $outdir  = $self->cfg->{paths}{output_dir}."/$testrun/test/";
        my ($error, $retval);

        for (my $i = 0; $i <= $#{$self->cfg->{guests}}; $i++) {
                # guest count starts with 1, arrays start with 0
                my $guest_number=$i+1;

                # every guest gets its own subdirectory
                my $guestoutdir="$outdir/guest-$guest_number/";

                $error = $self->makedir($guestoutdir);
                return $error if $error;

                $self->log_and_exec("touch $guestoutdir/console");
                $self->log_and_exec("chmod 666 $guestoutdir/console");
                ($error, $retval) = $self->log_and_exec("ln -sf $guestoutdir/console /tmp/guest$guest_number.fifo");
                return "Can't create guest console file $guestoutdir/console: $retval" if $error;
        }
        return 0;
}



=head2 nfs_mount

Mount the output directory from an NFS server. This method is used since we
only want to mount this NFS share in live mode.

@return success - 0
@return error   - error string

=cut

sub nfs_mount
{
        my ($self) = @_;
        my ($error, $retval);

        $error = $self->makedir($self->cfg->{paths}{prc_nfs_mountdir});
        return $error if $error;

        ($error, $retval) = $self->log_and_exec("mount",$self->cfg->{paths}{prc_nfs_mountdir});
        return 0 if not $error;
        ($error, $retval) = $self->log_and_exec("mount",$self->cfg->{prc_nfs_server}.":".$self->cfg->{paths}{prc_nfs_mountdir},$self->cfg->{paths}{prc_nfs_mountdir});
        # report error, but only if not already mounted
        return "Can't mount ".$self->cfg->{paths}{prc_nfs_mountdir}.":$retval" if ($error and ! -d $self->cfg->{paths}{prc_nfs_mountdir}."/live");
        return 0;
}

=head2 control_testprogram

Control running of one program including caring for its input, output and
the environment variables some testers asked for.

@return success - 0
@return error   - error string

=cut

sub control_testprogram
{
        my ($self) = @_;
        $ENV{TAPPER_TESTRUN}         = $self->cfg->{test_run};
        $ENV{TAPPER_SERVER}          = $self->cfg->{mcp_server};
        $ENV{TAPPER_REPORT_SERVER}   = $self->cfg->{report_server};
        $ENV{TAPPER_REPORT_API_PORT} = $self->cfg->{report_api_port};
        $ENV{TAPPER_REPORT_PORT}     = $self->cfg->{report_port};
        $ENV{TAPPER_HOSTNAME}        = $self->cfg->{hostname};
        $ENV{TAPPER_REBOOT_COUNTER}  = $self->cfg->{reboot_counter} if $self->cfg->{reboot_counter};
        $ENV{TAPPER_MAX_REBOOT}      = $self->cfg->{max_reboot} if $self->cfg->{max_reboot};
        $ENV{TAPPER_GUEST_NUMBER}    = $self->cfg->{guest_number} || 0;
        $ENV{TAPPER_SYNC_FILE}       = $self->cfg->{syncfile} if $self->cfg->{syncfile};
        $ENV{CRITICALITY}            = $self->cfg->{criticality} //  4;  # provide criticality for autoreport test scripts (4 == max)
        if ($self->{cfg}->{testplan}) {
                $ENV{TAPPER_TESTPLAN_ID}   = $self->cfg->{testplan}{id};
                $ENV{TAPPER_TESTPLAN_PATH} = $self->cfg->{testplan}{path};
        }



        my $test_run         = $self->cfg->{test_run};
        my $out_dir          = $self->cfg->{paths}{output_dir}."/$test_run/test/";
        my @testprogram_list;
        @testprogram_list    = @{$self->cfg->{testprogram_list}} if $self->cfg->{testprogram_list};


        # prepend outdir with guest number if we are in virtualisation guest
        $out_dir.="guest-".$self->{cfg}->{guest_number}."/" if $self->{cfg}->{guest_number};


        my $error = $self->makedir($out_dir);

        # can't create output directory. Make
        if ($error) {
                $self->log->warn($error);
                $out_dir = tempdir( CLEANUP => 1 );
        }

        $ENV{TAPPER_OUTPUT_PATH}=$out_dir;

        if ($self->cfg->{test_program}) {
                my $argv;
                my $environment;
                my $chdir;
                $argv        = $self->cfg->{parameters} if $self->cfg->{parameters};
                $environment = $self->cfg->{environment} if $self->cfg->{environment};
                $chdir       = $self->cfg->{chdir} if $self->cfg->{chdir};
                my $timeout  = $self->cfg->{timeout_testprogram} || 0;
                $timeout     = int $timeout;
                my $runtime  = $self->cfg->{runtime};
                push (@testprogram_list, {program => $self->cfg->{test_program},
                                          chdir => $chdir,
                                          parameters => $argv,
                                          environment => $environment,
                                          timeout => $timeout,
                                          runtime => $runtime,
                                          upload_before => $self->cfg->{upload_before},
                                          upload_after => $self->cfg->{upload_after},
                                         });
        }


        for (my $i=0; $i<=$#testprogram_list; $i++) {
                my $testprogram =  $testprogram_list[$i];

                $ENV{TAPPER_TS_RUNTIME}      = $testprogram->{runtime} || 0;

                # unify differences in program vs. program_list vs. virt
                $testprogram->{program}   ||= $testprogram->{test_program};
                $testprogram->{timeout}   ||= $testprogram->{timeout_testprogram};
                $testprogram->{argv}        = $testprogram->{parameters} if @{$testprogram->{parameters} || []};

                # create hash for testprogram_execute
                $testprogram->{timeout}   ||= 0;
                $testprogram->{out_dir}     = $out_dir;

                my $retval = $self->testprogram_execute($testprogram);

                if ($retval) {
                        my $error_msg = "Error while executing $testprogram->{program}: $retval";
                        $self->mcp_inform({testprogram => $i, state => 'error-testprogram', error => $error_msg});
                        $self->log->info($error_msg);
                } else {
                        $self->mcp_inform({testprogram => $i , state => 'end-testprogram'});
                        $self->log->info("Successfully finished test suite $testprogram->{program}");
                }

        }

        return(0);
}


=head2 get_peers_from_file

Read syncfile and extract list of peer hosts (not including this host).

@param string - file name

@return success - hash ref

@throws plain error message

=cut

sub get_peers_from_file
{
        my ($self, $file) = @_;
        my $peers;

        $peers = LoadFile($file);
        return "Syncfile does not contain a list of host names" if not ref($peers) eq 'ARRAY';

        my $hostname = $self->cfg->{hostname};
        my %peerhosts;
        foreach my $host (@$peers) {
                $peerhosts{$host} = 1;
        }
        delete $peerhosts{$hostname};

        return \%peerhosts;
}

=head2 wait_for_sync

Synchronise with other hosts belonging to the same interdependent testrun.

@param array ref - list of hostnames of peer machines

@return success - 0
@return error   - error string

=cut


sub wait_for_sync
{
        my ($self, $syncfile) = @_;

        my %peerhosts;   # easier to delete than from array

        eval {
                %peerhosts = %{$self->get_peers_from_file($syncfile)};
        };
        return $@ if $@;


        my $hostname = $self->cfg->{hostname};
        my $port = $self->cfg->{sync_port};
        my $sync_srv = IO::Socket::INET->new( LocalPort => $port, Listen => 5, );
        my $select = IO::Select->new($sync_srv);

        $self->log->info("Trying to sync with: ". join(", ",sort keys %peerhosts));

        foreach my $host (keys %peerhosts) {
                my $remote = IO::Socket::INET->new(PeerPort => $port, PeerAddr => $host,);
                if ($remote) {
                        $remote->print($hostname);
                        $remote->close();
                        delete($peerhosts{$host});
                }
                if ($select->can_read(0)) {
                        my $msg_srv = $sync_srv->accept();
                        my $remotehost;
                        $msg_srv->read($remotehost, 2048); # no hostnames are that long, anything longer is wrong and can be ignored
                        chomp $remotehost;
                        $msg_srv->close();
                        if ($peerhosts{$remotehost}) {
                                delete($peerhosts{$remotehost});
                        } else {
                                $self->log->warn(qq(Received sync request from host "$remotehost" which is not in our peerhost list. Request was sent from ),$msg_srv->peerhost);
                        }
                }
                $self->log->debug("In sync with $host.");

        }

        while (%peerhosts) {
                if ($select->can_read()) {   # TODO: timeout handling
                        my $msg_srv = $sync_srv->accept();
                        my $remotehost;
                        $msg_srv->read($remotehost, 2048); # no hostnames are that long, anything longer is wrong and can be ignored
                        chomp $remotehost;
                        $msg_srv->close();
                        if ($peerhosts{$remotehost}) {
                                delete($peerhosts{$remotehost});
                                $self->log->debug("In sync with $remotehost.");
                        } else {
                                $self->log->warn(qq(Received sync request from host "$remotehost" which is not in our peerhost list. Request was sent from ),$msg_srv->peerhost);
                        }
                } else {
                        # handle timeout here when can_read() has a timeout eventually
                }
        }
        return 0;
}

=head2 send_keep_alive_loop

Send keepalive messages to MCP in an endless loop.

@param int - sleep time between two keepalives

=cut

sub send_keep_alive_loop
{
        my ($self, $sleeptime) = @_;
        return unless $sleeptime;
        while (1) {
                $self->mcp_inform("keep-alive");
                sleep($sleeptime);
        }
        return;
}


=head2 run

Main function of Program Run Control.

=cut

sub run
{
        my ($self) = @_;
        my $retval;
        my $producer = Tapper::Remote::Config->new();
        my $config = $producer->get_local_data("test-prc0");
        $self->cfg($config);
        $self->cfg->{reboot_counter} = 0 if not defined($self->cfg->{reboot_counter});

        if ($self->cfg->{log_to_file}) {
                $self->log_to_file('testing');
        }

        if ($config->{times}{keep_alive_timeout}) {
                $SIG{CHLD} = 'IGNORE';
                my $pid = fork();
                if ($pid == 0) {
                        $self->send_keep_alive_loop($config->{times}{keep_alive_timeout});
                        exit;
                } else {
                        $config->{keep_alive_child} = $pid;
                }
        }

        # ignore error
        $self->log_and_exec('ntpdate -s gwo');

        if ($config->{prc_nfs_server}) {
                $retval = $self->nfs_mount();
                $self->log->warn($retval) if $retval;
        }

        $self->log->logdie($retval) if $retval = $self->create_log();

        if ($config->{scenario_id}) {
                my $syncfile = $config->{paths}{sync_path}."/".$config->{scenario_id}."/syncfile";
                $self->cfg->{syncfile} = $syncfile;

                $retval = $self->wait_for_sync($syncfile);
                $self->log->logdie("Can not sync - $retval") if $retval;
        }

        if ($self->{cfg}->{guest_count}) {

                $retval = $self->guest_start();
                $self->log->error($retval) if $retval;
        }

        $retval = $self->mcp_inform({state => 'start-testing'}) if not $self->cfg->{reboot_counter};

        $retval = $self->control_testprogram() if $self->cfg->{test_program} or $self->cfg->{testprogram_list};

        if ($self->cfg->{max_reboot}) {
                $self->mcp_inform({state => 'reboot', count => $self->cfg->{reboot_counter}, max_reboot => $self->cfg->{max_reboot}});
                if ($self->cfg->{reboot_counter} < $self->cfg->{max_reboot}) {
                        $self->cfg->{reboot_counter}++;
                        YAML::Syck::DumpFile($config->{filename}, $self->{cfg}) or $self->mcp_error("Can't write config to file: $!");
                        $self->log_and_exec("reboot");
                        return 0;
                }

        }


        # no longer send keepalive
        if ($config->{keep_alive_child}) {
                kill 15, $config->{keep_alive_child};
                sleep 2;
                kill 9, $config->{keep_alive_child};
        }

        $retval = $self->mcp_inform({state => 'end-testing'});


}

1;
