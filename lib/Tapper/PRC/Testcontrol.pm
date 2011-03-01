package Tapper::PRC::Testcontrol;

use IPC::Open3;
use File::Path;
use Moose;
use YAML 'LoadFile';

use common::sense;

use Tapper::Remote::Config;

extends 'Tapper::PRC';

our $MAXREAD = 1024;  # read that much in one read


=head1 NAME

Tapper::PRC::Testcontrol - Control running test programs

=head1 SYNOPSIS

 use Tapper::PRC::Testcontrol;

=head1 FUNCTIONS

=cut

=head2 testprogram_execute

Execute one testprogram. Handle all error conditions.

@param string - program name
@param int    - timeout
@param string - output directory
@param array of strings - parameters for test program

@return success - 0
@return error   - error string

=cut

sub testprogram_execute
{
        my ($self, $program, $timeout, $out_dir, @argv) = @_;

        my $progpath =  $self->cfg->{paths}{testprog_path};
        my $output   =  $program;
        $output      =~ s|[^A-Za-z0-9_-]|_|g;
        $output      =  $out_dir.$output;


        # make relative paths absolute
        $program=$progpath.$program if $program !~ m(^/);

        # try to catch non executables early
        return("tried to execute $program which does not exist") unless -e $program;
        return("tried to execute $program which is not an execuable") unless -x $program;
        return("tried to execute $program which is a directory") if -d $program;
        return("tried to execute $program which is a special file (FIFO, socket, device, ..)") unless -f $program or -l $program;

        $self->log->info("Try to execute test suite $program");

        pipe (my $read, my $write);
        return ("Can't open pipe:$!") if not (defined $read and defined $write);

        my $pid=fork();
        return( "fork failed: $!" ) if not defined($pid);

        if ($pid == 0) {        # hello child
                close $read;
                open (STDOUT, ">>", "$output.stdout") or syswrite($write, "Can't open output file $output.stdout: $!"),exit 1;
                open (STDERR, ">>", "$output.stderr") or syswrite($write, "Can't open output file $output.stderr: $!"),exit 1;
                exec ($program, @argv) or syswrite($write,"$!\n");
                close $write;
                exit -1;
        } else {
                # hello parent
                close $write;
                my $killed;
                # (XXX) better create a process group an kill this
                local $SIG{ALRM}=sub{$killed=1;kill (15,$pid); kill (9,$pid);};
                alarm ($timeout);
                waitpid($pid,0);
                my $retval = $?;
                alarm(0);
                return "Killed $program after $timeout seconds" if $killed;
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
        my $retval;
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
                        $self->log->info("Try load Xen guest described in ",$guest->{svm});
                        if (not (system("xm","create",$guest->{svm}) == 0)) {
                                $retval = "Can't start xen guest described in $guest->{svm}";
                                                $self->mcp_send({prc_number => ($i+1), state => 'error-guest',
                                                                 error => $retval});
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

                if (not -d $guestoutdir) {
                        mkpath($guestoutdir, {error => \$retval});
                        foreach my $diag (@$retval) {
                                my ($file, $message) = each %$diag;
                                return "general error: $message\n" if $file eq '';
                                return "Can't create $file: $message";
                        }
                }

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
        File::Path->mkpath($self->cfg->{paths}{prc_nfs_mountdir}, {error => \$error}) if not -d $self->cfg->{paths}{prc_nfs_mountdir};
        foreach my $diag (@$error) {
                my ($file, $message) = each %$diag;
                return "general error: $message\n" if $file eq '';
                return "Can't create $file: $message";
        }
        ($error, $retval) = $self->log_and_exec("mount",$self->cfg->{prc_nfs_server}.":".$self->cfg->{paths}{prc_nfs_mountdir},$self->cfg->{paths}{prc_nfs_mountdir});
        return "Can't mount ".$self->cfg->{paths}{prc_nfs_mountdir}.":$retval" if $error;
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



        my $retval;
        my $test_run         = $self->cfg->{test_run};
        my $out_dir          = $self->cfg->{paths}{output_dir}."/$test_run/test/";
        my @testprogram_list;
        @testprogram_list    = @{$self->cfg->{testprogram_list}} if $self->cfg->{testprogram_list};


        # prepend outdir with guest number if we are in virtualisation guest
        $out_dir.="guest-".$self->{cfg}->{guest_number}."/" if $self->{cfg}->{guest_number};


        mkpath($out_dir, {error => \$retval}) if not -d $out_dir;
        foreach my $diag (@$retval) {
                my ($file, $message) = each %$diag;
                return "general error: $message\n" if $file eq '';
                return "Can't create $file: $message";
        }

        $ENV{TAPPER_OUTPUT_PATH}=$out_dir;

        if ($self->cfg->{test_program}) {
                my @argv;
                @argv        = @{$self->cfg->{parameters}} if $self->cfg->{parameters};
                my $timeout  = $self->cfg->{timeout_testprogram} || 0;
                $timeout     = int $timeout;
                my $runtime  = $self->cfg->{runtime};
                push (@testprogram_list, {program => $self->cfg->{test_program}, parameters => \@argv, timeout => $timeout, runtime => $runtime});
        }


        for (my $i=0; $i<=$#testprogram_list; $i++) {
                my $testprogram =  $testprogram_list[$i];

                $ENV{TAPPER_TS_RUNTIME}      = $testprogram->{runtime} || 0;

                # unify differences in program vs. program_list vs. virt
                $testprogram->{program} ||= $testprogram->{test_program};
                $testprogram->{timeout} ||= $testprogram->{timeout_testprogram};

                my @argv;
                @argv      = @{$testprogram->{parameters}} if defined($testprogram->{parameters}) and ref($testprogram->{parameters}) eq "ARRAY";
                my $retval = $self->testprogram_execute($testprogram->{program}, int($testprogram->{timeout} || 0), $out_dir, @argv);

                if ($retval) {
                        $self->mcp_inform({testprogram => $i, state => 'error-testprogram', error => $retval});
                        $self->log->info("Error while executing $testprogram->{program}: $retval");
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
                        } else {
                                $self->log->warn(qq(Received sync request from host "$remotehost" which is not in our peerhost list. Request was sent from ),$msg_srv->peerhost);
                        }
                }
        }
        return 0;
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

                $config->{prc_count} = $config->{guest_count} + 1; # always have a PRC in host

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


        $retval = $self->mcp_inform({state => 'end-testing'});


}

1;

=head1 AUTHOR

OSRC SysInt Team, C<< <osrc-sysint at elbe.amd.com> >>

=head1 BUGS

None.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

 perldoc Tapper


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 AMD OSRC Tapper Team, all rights reserved.

This program is released under the following license: restrictive

