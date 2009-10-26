package Artemis::PRC;

use strict;
use warnings;

use IO::Socket::INET;
use YAML::Syck;
use Moose;
use Log::Log4perl;

use Artemis::Base;

with 'MooseX::Log::Log4perl';

our $VERSION = '2.000036';

=head1 NAME

Artemis::PRC - Base class for running test programs

=head1 SYNOPSIS

 use Artemis::PRC;

=head1 FUNCTIONS

=cut

has cfg => (is      => 'rw',
            isa     => 'HashRef',
            default => sub { {} },
           );

BEGIN {
	Log::Log4perl::init(Artemis::Config->subconfig->{files}{log4perl_cfg}); # ss5 2009-09-23
}

=head2 log_and_exec

Execute a given command. Make sure the command is logged if requested and none
of its output pollutes the console. In scalar context the function returns 0
for success and the output of the command on error. In array context the
function always return a list containing the return value of the command and
the output of the command. (XXX: this function is also used in installer,
think about refactoring it into a common module used by all Artemis projects)

@param string - command

@return success - 0
@return error   - error string
@returnlist success - (0, output)
@returnlist error   - (return value of command, output)

=cut

sub log_and_exec
{
        my ($self, @cmd) = @_;
        my $cmd = join " ",@cmd;
        $self->log->debug( $cmd );
        my $output=`$cmd 2>&1`;
        my $retval=$?;
        if (not defined($output)) {
                $output = "Executing $cmd failed";
                $retval = 1;
        }
        chomp $output if $output;
        if ($retval) {
                return ($retval >> 8, $output) if wantarray;
                return $output;
        }
        return (0, $output) if wantarray;
        return 0;
}
;




=head2 mcp_send

Tell the MCP server our current status. This is done using a TCP connection.

@param string - message to send to MCP

@return success - 0
@return error   - error string

=cut

sub mcp_send
{
        my ($self, $message) = @_;
        my $server = $self->cfg->{mcp_server} or return "MCP host unknown";
        my $port   = $self->cfg->{port} || 7357;

        my $yaml = Dump($message);
        
	if (my $sock = IO::Socket::INET->new(PeerAddr => $server,
					     PeerPort => $port,
					     Proto    => 'tcp')){
		print $sock ("$yaml");
		close $sock;
	} else {
                return("Can't connect to MCP: $!");
	}
        return(0);
}


=head2 mcp_inform

Generate the message to be send to MCP and hand it over to mcp_send.

@param hash reference - message to send to MCP

@return success - 0
@return error   - error string

=cut

sub mcp_inform
{
        
        my ($self, $msg) = @_;
        return "$msg is not a hash" if not ref($msg) eq 'HASH';

        # set PRC number
        if ($self->{cfg}->{guest_number}) {
                $msg->{prc_number} = $self->{cfg}->{guest_number};
        } else {
                # guest numbers start with 1, 0 is host or no virtualisation
                $msg->{prc_number} = 0;
        }
        return $self->mcp_send($msg);
};



=head2 mcp_error

Log an error and exit.

@param string - messages to send to MCP

@return never returns

=cut

sub mcp_error
{

        my ($self, $error) = @_;
        $self->log->error($error);
        my $retval = $self->mcp_inform({status => 'error-testprogram', error => $error});
        $self->log->error($retval) if $retval;
        exit 1;
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

