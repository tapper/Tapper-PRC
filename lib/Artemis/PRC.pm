package Artemis::PRC;

use strict;
use warnings;

use IO::Socket::INET;
use Method::Signatures;
use Artemis::Config;
use Moose;
use Log::Log4perl;

with 'MooseX::Log::Log4perl';

our $VERSION = '2.000005';

=head1 NAME

Artemis::PRC - Base class for running test programs

=head1 SYNOPSIS

 use Artemis::PRC;

=head1 FUNCTIONS

=cut

has cfg => (is      => 'rw',
            default => sub { {} },
           );

BEGIN {
	Log::Log4perl::init(Artemis::Config->subconfig->{files}{log4perl_cfg}); # ss5 2009-09-23
}



=head2 mcp_send

Tell the MCP server our current status. This is done using a TCP connection.

@param string - message to send to MCP

@return success - 0
@return error   - error string

=cut

method mcp_send($message)
{
        my $server = $self->cfg->{server} or return "MCP host unknown";
        my $port   = $self->cfg->{port} || 7357;

        $self->log->info(qq(Sending status message "$message" to MCP host "$server"));

	if (my $sock = IO::Socket::INET->new(PeerAddr => $server,
					     PeerPort => $port,
					     Proto    => 'tcp')){
		$sock->print("$message\n");
		close $sock;
	} else {
                return("Can't connect to MCP: $!");
	}
        return(0);
};


=head2 mcp_inform

Generate the message to be send to MCP and hand it over to mcp_send.

@param array of strings - messages to send to MCP

@return success - 0
@return error   - error string

=cut

method mcp_inform(@msg)
{

        # prepend PRC number
        if ($self->{cfg}->{guest_number}) {
                unshift @msg, "prc_number:".$self->{cfg}->{guest_number};
        } else {
                # guest numbers start with 1, 0 is host or no virtualisation
                unshift @msg, "prc_number:0"; 
        }

        my $msg=join ',', @msg;

        return $self->mcp_send($msg);
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

