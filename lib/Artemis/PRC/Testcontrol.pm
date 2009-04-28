package Artemis::PRC::Testcontrol;

use strict;
use warnings;

use IPC::Open3;
use File::Path;
use Method::Signatures;
use Moose;

use Artemis::PRC::Proxy;

extends 'Artemis::PRC';

=head1 NAME

Artemis::PRC::Testcontrol - Control running test programs

=head1 SYNOPSIS

 use Artemis::PRC::Testcontrol;

=head1 FUNCTIONS

=cut


=head2 guest_start

Start guest images for virtualisation. Only Xen guests can be started at the
moment.

@return success - 0
@return error   - error string

=cut

method guest_start
{
        my $retval;
        for (my $i=0; $i<=$#{$self->cfg->{guests}}; $i++) {
                my $guest = $self->cfg->{guests}->[$i];
                if ($guest->{exec}){
                        my $startscript = $guest->{exec};
                        $self->log->info("Try to start virtualisation guest with $startscript");
                        return qq(Startscript "$startscript" is not an executable or does not exist at all) if not -x $startscript;
                        if (not system($startscript) == 0 ) {
                                $retval = qq(Can't start virtualisation guest using startscript "$startscript");
                                $self->mcp_send("prc_number:".($i+1).",error-testprogram:$retval");
                                return $retval;
                        }
                } elsif ($guest->{svm}){
                        $self->log->info("Try load Xen guest described in ",$guest->{svm});
                        print STDERR "Artemis::PRC::Testcontrol: xm create ",$guest->{svm},"\n";
                        if (not (system("xm","create",$guest->{svm}) == 0)) {
                                $retval = "Can't start xen guest described in $guest->{svm}";
                                $self->mcp_send("prc_number:".($i+1).",error-testprogram:$retval");
                                return $retval;
                        }  
                }
        }
        return 0;
};

=head2 create_log

Checks whether fifos for guest logging exists and creates them if
not. Existing files of wrong type are deleted.

@retval success - 0
@retval error   - error string

=cut

method create_log()
{
        for(my $i=0; $i <= $#{$self->cfg->{guests}}; $i++) {
                my $guest_number=$i+1;
                my $fifo = "/tmp/guest$guest_number.fifo";
                if (not -p "$fifo") {
                        my ($error, $retval);
                        rmtree($fifo,{verbose => 0, error => \$error});
                ERROR:
                        for my $diag (@$error) {
                                my ($file, $message) = each %$diag;
                                next ERROR if not $file; # remove inexisting file
                                return "Can't remove $file:$message\n";
                        }
                        ($error, $retval) = $self->log_and_exec("mkfifo",$fifo);
                        return "Can't create guest console file $fifo: $retval" if $error;
                }
        }
        return 0;
};



=head2 nfs_mount

Mount the output directory from an NFS server. This method is used since we
only want to mount this NFS share in live mode.

@return success - 0
@return error   - error string

=cut

method nfs_mount
{
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
};


=head2 control_testprogram

Control running of one program including caring for its input, output and
the environment variables some testers asked for. 

@return success - 0
@return error   - error string

=cut

method control_testprogram()
{ 
        $ENV{ARTEMIS_TESTRUN}         = $self->cfg->{test_run};
        $ENV{ARTEMIS_SERVER}          = $self->cfg->{mcp_server};
        $ENV{ARTEMIS_REPORT_SERVER}   = $self->cfg->{report_server};
        $ENV{ARTEMIS_REPORT_API_PORT} = $self->cfg->{report_api_port};
        $ENV{ARTEMIS_REPORT_PORT}     = $self->cfg->{report_port};
        $ENV{ARTEMIS_TS_RUNTIME}      = $self->cfg->{runtime};
        $ENV{ARTEMIS_GUEST_NUMBER}    = $self->{cfg}->{guest_number} || 0;

        my $MAXREAD = 1024;  # read that much in one read

        my $retval;
        my $test_run = $self->cfg->{test_run};
        my $out_dir  = $self->cfg->{paths}{output_dir}."/$test_run/test/";
        my $progpath = $self->cfg->{paths}{testprog_path};
        my $program  = $self->cfg->{test_program};
        my $timeout  = $self->cfg->{timeout_testprogram} || 0;
        my @argv     = @{$self->cfg->{parameters}} if $self->cfg->{parameters}; 
        $timeout     = int $timeout;

        # prepend outdir with guest number if we are in virtualisation guest
        $out_dir.="guest-".$self->{cfg}->{guest_number}."/" if $self->{cfg}->{guest_number};
        

        mkpath($out_dir, {error => \$retval}) if not -d $out_dir;
        foreach my $diag (@$retval) {
                my ($file, $message) = each %$diag;
                return "general error: $message\n" if $file eq '';
                return "Can't create $file: $message";
        }


        # make relative paths absolute
        $program=$progpath.$program if $program !~ m(^/);
		
        # if exec fails  the error message will go into the output file, thus its best to catch 
        # many error early to have them reported back 
        return("tried to execute $program which is not an execuable or does not exist at all") if not -x $program;

        my $output = $out_dir.'Output';
        $ENV{ARTEMIS_OUTPUT_PATH}=$out_dir;
		

        $self->log->info("Try to execute test suite $program");

	pipe (my $read, my $write);
	return ("Can't open pipe:$!") if not (defined $read and defined $write);

        my $pid=fork();
        return( "fork failed: $!" ) if not defined($pid);
        
        if ($pid == 0) {        # hello child
                close $read;
                open (STDOUT, ">>$output.stdout") or syswrite($write, "Can't open output file $output-STDOUT: $!"),exit 1;
                open (STDERR, ">>$output.stderr") or syswrite($write, "Can't open output file $output-STDERR: $!"),exit 1;
                exec ($program, @argv) or syswrite($write,"$!\n");
                close $write;
                exit -1;
        } else {
                # hello parent
                close $write;
                our $killed;
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
        return(0);
}
;

=head2 run

Main function of Program Run Control. When used in virtualisation environment,
a proxy is created in a child process. The parent process waits until the
proxy sends a "ready" message through the pipe provided as
$self->cfg->{syncwrite} in the proxy. When this status is received or the
function is called in a test without virtualisation, it continues with
starting the guests (if any) and to call test control functions.

=cut

method run()
{

        my $retval;
        my $config_file_name = '/etc/artemis';
        $config_file_name = $ENV{ARTEMIS_CONFIG} if $ENV{ARTEMIS_CONFIG};

        my $config = YAML::Syck::LoadFile($config_file_name) or $self->log->logdie("Can't read config file $config_file_name: $!");
        $self->{cfg} = $config;
        $self->cfg->{reboot_counter} = 0 if not defined($self->cfg->{reboot_counter});

        if ($config->{prc_nfs_server}) {
                $retval = $self->nfs_mount();
                $self->log->logdie($retval) if $retval;
        }
        $self->log->logdie($retval) if $retval = $self->create_log();


        if ($self->{cfg}->{guest_count}) {
                
                $config->{prc_count} = $config->{guest_count} + 1; # always have a PRC in host

                my ($read, $write);
                pipe($read, $write) or $self->log->error("Can't open pipe to talk to child: $!") && return;

                my $pid = fork();
                $self->log->error("fork failed: $!") and return -1 if (not defined $pid);

                if ($pid == 0) {
                        # send pipe to proxy
                        $config->{syncwrite} = $write;
                        close $read;

                        $config->{server} = $config->{mcp_server};
                        # proxy collects status messages from guests and sends reports with more
                        # information to MCP
                        my $proxy = Artemis::PRC::Proxy->new($config);
                        $retval = $proxy->run;
                        if ($retval) {
                                #syswrite($write,$retval."\n");
                                $self->log->error($retval);
                                exit -1;
                        }
                        exit 0;
                        
                } else {
                        close $write;
                        # wait for proxy, ignore the message 
                        <$read>;
                        # report testprogram status to Proxy
                        $retval = $self->guest_start();
                        $self->log->error($retval) if $retval;
                }

        }

        $retval = $self->mcp_inform('start-testprogram') if not $self->cfg->{reboot_counter};

        if ($self->cfg->{test_program}) {
                $retval = $self->control_testprogram();
                if ($retval) {
                        $self->mcp_error($retval);
                } else {
                        $self->log->info("Successfully finished test suite ".$self->cfg->{test_program});
                }
        }

        if ($self->cfg->{max_reboot}) {
                $self->mcp_inform("reboot:".$self->cfg->{reboot_counter},$self->cfg->{max_reboot}); # mcp_inform joins messages with comma
                if ($self->cfg->{reboot_counter} < $self->cfg->{max_reboot}) {
                        $self->cfg->{reboot_counter}++;
                        YAML::Syck::DumpFile($config_file_name, $self->{cfg}) or $self->mcp_error("Can't write config to file: $!");
                        $self->log_and_exec("reboot");
                        return 0;
                }

        }


        $retval = $self->mcp_inform('end-testprogram');
        

};

1;

=head1 AUTHOR

OSRC SysInt Team, C<< <osrc-sysint at elbe.amd.com> >>

=head1 BUGS

None.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

 perldoc Artemis


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008 OSRC SysInt Team, all rights reserved.

This program is released under the following license: restrictive

