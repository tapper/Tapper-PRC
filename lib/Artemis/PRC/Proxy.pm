package Artemis::PRC::Proxy;

use strict;
use warnings;

use File::Basename;
use File::Path;
use IO::Select;
use IO::Socket::INET;
use List::Util qw(min max);
use Moose;


extends 'Artemis::PRC';

has select => (is  => 'rw');


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

sub BUILD
{
        my ($self, $config) = @_;
        $self->{cfg}=$config;
        $self->{select} = new IO::Select();
}


=head2 msg_send

Append prc_count to message and send it to MCP

@param string - message to be send

@retval success - 0 
@retval error   - error string

=cut

sub msg_send
{
        my ($self, $msg) = @_;
        $msg   .= ",prc_count:";
        $msg   .= $self->{cfg}->{prc_count};
        my $retval = $self->mcp_send($msg );
        return $retval;
}

=head2 open_console

Open a console file handle for each guest. 

@param arrary ref - containing all file handles

@retval success - (array_ref, IO::Select)
@retval error   - (string)

=cut

sub open_console
{
        my ($self, $handles) = @_;
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


                my $fifo = "/tmp/guest$guest_number.fifo";
                my $output_file=$self->cfg->{paths}{output_dir}."/$testrun/test/guest-$guest_number/console";
                open($handles->[$i]->{console}, "<",$fifo)
                  or return qq(Can't open console "$fifo" for guest $guest_number:$!);
                open($handles->[$i]->{output},">",$output_file)
                  or return qq(Can't open output file "$output_file" for guest $guest_number:$!);
                $self->{select}->add($handles->[$i]->{console});

                
        }
        return($handles);
}




=head2 read_console

Read from guest console and write to associated log file.

@param array ref - reference to array with file handles
@param file handle - readable filehandle (returned by select)

@retval success - 0
@retval error   - error string

=cut

sub read_console
{
        my ($self, $handles, $fh) = @_;
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
}



=head2 wait_for_messages

Main method of this module. Wait for message from guests and check whether
they arrive within the timeout.

@retval success - 0
@retval error   - error string

=cut 

sub wait_for_messages
{
        my ($self) = @_;
        my $server =  IO::Socket::INET->new(Listen    => 5,
                                            LocalPort => $self->cfg->{port} || 7357,
                                            Proto     => 'tcp'
                                           )
          or return "Can't open proxy server: $!";
        $self->{select}->add($server);


        my $handles;
        ($handles) = $self->open_console($handles);
        return $handles if not ref($handles) eq "ARRAY";
        

 MESSAGE:
        while (1) {
                my @ready = $self->{select}->can_read();

                foreach my $fh (@ready) {
                        if ($fh == $server) {
                                # Create a new socket
                                my $new = $fh->accept;
                                $self->{select}->add($new);
                        } elsif ($fh->isa('IO::Socket::INET')){
                                my $msg=<$fh>;
                                $self->{select}->remove($fh);
                                $fh->close; # don't need message socket any more.
                                my $retval = $self->msg_send($msg);
                        }
                        else {
                                $self->read_console($handles, $fh);
                        }
                }
        }                
        return 0;
}



=head2 run

Run the PRC proxy used to forward status messages to MCP.

=cut

sub run
{
        my ($self) = @_;
        syswrite $self->{cfg}->{syncwrite}, "start\n";   # inform parent that proxy is ready
        $self->log->info("Proxy started");
        $self->wait_for_messages();
}

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

