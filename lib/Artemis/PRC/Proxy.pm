package Artemis::PRC::Proxy;

use strict;
use warnings;

use File::Basename;
use File::Path;
use IO::Select;
use List::Util qw(min max);
use Method::Signatures;
use Moose;


extends 'Artemis::PRC';


=head1 NAME

Artemis::PRC::Proxy - Collect status messages from all PRCs running on this
                      host and send them to MCP together with some additional
                      information

=head1 SYNOPSIS

 use Artemis::PRC::Proxy;

=head1 FUNCTIONS

=cut



=head2 BUILD

BUILD methods are called immediatelly after an object instance is
created. This one fills $self->{cfg}. The parameter has to be handed over to
new().

@param hash ref - configuration hash

=cut

method BUILD($config)
{
        $self->{cfg}=$config;
};


=head2 msg_send

Append prc_count to message and send it to MCP

@param string - message to be send

@retval success - 0 
@retval error   - error string

=cut

method msg_send($msg)
{
        $msg   .= ",prc_count:";
        $msg   .= $self->{cfg}->{prc_count};
        my $retval = $self->mcp_send($msg );
        return $retval;
};


=head2 report_timeout

A timeout occured. Check guests status array and report an error for each
guest that is affected.

@param int   - number of guests that haven't booted yet
@param int   - number of guests that haven't finished their test programs yet
@param array - status of each guest

@retval (int, int) - (number of guests that haven't booted yet, number of

=cut

method report_timeout($to_start, $to_stop, @guest_status)
{
        # at least one guest wasn't started so we have to assume we hit the
        # boot timeout of this guest.
        if ($to_start) {
                for (my $i=0;$i<=$#guest_status;$i++) {
                        if ($guest_status[$i]->{start}) {
                                $guest_status[$i]->{start} = 0;
                                $guest_status[$i]->{stop}  = 0;
                                $self->msg_send("prc_number:$i,error-testprogram:boot timeout reached");
                                $to_start--;
                                $to_stop--;
                        }
                }
        } 
        # all guests finished booting, so the timeout occured because a guest
        # took to much time for its tests
        elsif ($to_stop) {
                for (my $i=0;$i<=$#guest_status;$i++) {
                        if ($guest_status[$i]->{stop}) {
                                $guest_status[$i]->{stop}  = 0;
                                $self->msg_send("prc_number:$i,error-testprogram:test program timeout reached");
                                $to_stop--;
                        }
                }
        }
        return ($to_start, $to_stop);
}
;



=head2 time_reduce

Reduce remaining timeout time for all guests by the time we slept in
select. Returns the time to be used in the next sleep, i.e. the minimum of all
guest timeouts greater zero.

@param int   - time slept in select
@param array - status of all guests

@retval new value for timeout

=cut

method time_reduce($elapsed, @guest_status)
{
        my $boot_timeout;
        my $test_timeout;
        for (my $i=0; $i<=$#guest_status; $i++) {
                if ($guest_status[$i]->{start}) {
                        $guest_status[$i]->{start}= max (0, $guest_status[$i]->{start} - $elapsed);
                        if ($boot_timeout) {
                                $boot_timeout = min($boot_timeout, $guest_status[$i]->{start});
                        } else {
                                $boot_timeout = $guest_status[$i]->{start};
                        }
                } elsif ($guest_status[$i]->{stop}) {
                        $guest_status[$i]->{stop}= max (0, $guest_status[$i]->{stop} - $elapsed);
                        if ($boot_timeout) {
                                $test_timeout = min($boot_timeout, $guest_status[$i]->{stop});
                        } else {
                                $test_timeout = $guest_status[$i]->{stop} if not $test_timeout;
                                $test_timeout = min($test_timeout, $guest_status[$i]->{stop})
                        }
                }
        }
        
        return $boot_timeout if $boot_timeout;
        return max(1,$test_timeout);
}
;

=head2 open_console

Open a console file handle for each guest. 

@param arrary ref - containing all file handles
@param IO::Select object - add consoles to select

@retval success - (array_ref, IO::Select)
@retval error   - (string)

=cut

method open_console($handles, $select)
{
        my $testrun = $self->cfg->{test_run};
        my $outdir  = $self->cfg->{paths}{output_dir}."/$testrun/test/";



        for (my $i = 0; $i <= $#{$self->cfg->{guests}}; $i++) {
                # guest count starts with 1, arrays start with 0
                my $guest_number=$i+1;

                # every guest gets its own subdirectory
                my $guestoutdir="$outdir/guest-$guest_number/";
        
                mkpath($guestoutdir, {error => \my $retval}) if not -d $guestoutdir;
                foreach my $diag (@$retval) {
                        my ($file, $message) = each %$diag;
                        return "general error: $message\n" if $file eq '';
                        return "Can't create $file: $message";
                }


                my $fifo = "/xen/images/guest$guest_number.fifo";
                my $output_file=$self->cfg->{paths}{output_dir}."/$testrun/test/guest-$guest_number/console";
                open($handles->[$i]->{console}, "<",$fifo)
                  or return qq(Can't open console "$fifo" for guest $guest_number:$!);
                open($handles->[$i]->{output},">",$output_file)
                  or return qq(Can't open output file "$output_file" for guest $guest_number:$!);
                $select->add($handles->[$i]->{console});

                
        }
        return($handles, $select);
}
;


=head2 read_console

Read from guest console and write to associated log file.

@param array ref - reference to array with file handles
@param file handle - readable filehandle (returned by select)

@retval success - 0
@retval error   - error string

=cut

method read_console($handles, $fh)
{
        my $file;
        my $maxread = 1024; # number of bytes to read from console
        my $i;
 HANDLE:
        for ($i  = 0; $i <= $#{$handles}; $i++) {
                if ($fh == $handles->[$i]->{console}) {
                        $file = $handles->[$i]->{output};
                        last HANDLE;
                }
        }
        
        my $buffer;

        # This has to be sysread. The diamond operator tries to read up to the
        # next newline but select also reports file handles without this
        # newline as readable. Don't put a loop around sysread, since we can't
        # detect when to stop reading.
        my $retval = sysread($fh, $buffer, $maxread);
        return "Can't read from console of guest $i:$!" if not defined($retval);
        
        $retval = syswrite($file, $buffer);
        return "Can't write console of guest $i:$!" if not defined($retval);
        return 0;
};



=head2 wait_for_messages

Main method of this module. Wait for message from guests and check whether
they arrive within the timeout.

@retval success - 0
@retval error   - error string

=cut 

method wait_for_messages
{
        my $server =  IO::Socket::INET->new(Listen    => 5,
                                            LocalPort => $self->cfg->{port} || 7357,
                                            Proto     => 'tcp'
                                           )
          or return "Can't open proxy server: $!";
        my $select = new IO::Select( $server );
        

        my $handles;
        ($handles, $select) = $self->open_console($handles, $select);
        return $handles if not ref($handles) eq "ARRAY";
        

        # initialise guest_status array
        # guests get boot timeout for start and their associated test timeouts
        # for stop
        my $to_start;
        my $to_stop  = $to_start = $self->{cfg}->{prc_count};
        my $retval;
        my @guest_status;
        # prc_count is always at least one, since we got a PRC running in host
        for (my $i=0; $i<$self->{cfg}->{prc_count}; $i++) {
                $guest_status[$i]={start => $self->{cfg}->{times}{boot_timeout},
                                   stop => $self->{cfg}->{timeouts}[$i] || 0};  # timeouts array starts with 0 for 1st guest
        }
        my $timeout = $self->{cfg}->{times}{boot_timeout};
        my $elapsed = 0;

 MESSAGE:
        while ($to_stop) {

                # time_reduce on the beginning of the loop so when the loop is
                # restarted after a message is received, the timeout is recalculated
                $timeout = $self->time_reduce($elapsed, @guest_status);

                my $start_timeout = time();
                my @ready = $select->can_read($timeout);
                $elapsed = time() - $start_timeout;

                ($to_start, $to_stop) = $self->report_timeout($to_start, $to_stop, @guest_status) if not @ready;


                foreach my $fh (@ready) {
                        if ($fh == $server) {
                                # Create a new socket
                                my $new = $fh->accept;
                                $select->add($new);
                        } elsif ($fh->isa('IO::Socket::INET')){
                                my $msg=<$fh>;
                                $select->remove($fh);
                                $fh->close; # don't need message socket any more.
                                chomp $msg;
                                #        prc_number:0,end-testprogram
                                my ($number, $status, undef, $error) = $msg =~/prc_number:(\d+),(start|end|error)-testprogram(:(.+))?/ 
                                  or $self->log->error(qq(Can't parse message "$msg" received from child machine. I'll ignore the message.))
                                    and next MESSAGE;
                                $self->log->debug("status $status in PRC $number, last PRC is ",$self->{cfg}->{prc_count});
                
                                
                                if ($status eq "start") {
                                        $retval = $self->msg_send($msg);
                                        $guest_status[$number]->{start}=0;
                                        $to_start--;
                                        next MESSAGE;
                                } elsif ($status eq "end") {
                                        if ($guest_status[$number]->{start}) {
                                                $self->log->warn("Received end for guest $number without having received start before.",
                                                              " I probably missed it and thus send the start message to the server too.");
                                                $retval = $self->msg_send("prc_number:$number,start-testprogram");
                                                $self->log->warn($retval) if $retval;
                                        }
                        
                                } elsif ($status eq "error") {
                                        if ($guest_status[$number]->{start})
                                        {
                                                $self->log->warn("got an error but still have a start timeout. BUG!");
                                                $to_stop--;
                                                $guest_status[$number]->{start}=0;
                                        }
                                }

                                # common for end and error
                                $retval = $self->msg_send($msg);
                                $guest_status[$number]->{stop}=0;
                                $to_stop--;
                        }
                        else {
                                $self->read_console($handles, $fh);
                        }
                }
        }                
        return 0;
}
;


=head2 run

Run the PRC proxy used to forward status messages to MCP.

=cut

method run()
{
        syswrite $self->{cfg}->{syncwrite}, "start\n";   # inform parent that proxy is ready
        $self->log->info("Proxy started");

        $self->wait_for_messages();
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

