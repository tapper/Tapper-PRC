package Artemis::PRC;

use strict;
use warnings;

use IO::Socket::INET;
use YAML::Syck;
use Moose;
use Log::Log4perl;

extends 'Artemis::Base';

with 'MooseX::Log::Log4perl';

our $VERSION = '2.000040';

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
        # hardcoding these values reduces dependancy on Artemis::Config and is
        # bearable since it never really changes
        my $logconf = 'log4perl.cfg';
        if ($ENV{HARNESS_ACTIVE}) {
           $logconf = 'log4perl_test.cfg';
        }
	Log::Log4perl::init($logconf);
}

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


=head2 set_comfile

Set the file that holds the current state of this PRC for MCP to access in
case of a restart. 

@return 0

=cut

sub set_comfile
{
        if ($self->{cfg}->{guest_number}) {
                $msg->{prc_number} = $self->{cfg}->{guest_number};
        } else {
                # guest numbers start with 1, 0 is host or no virtualisation
                $msg->{prc_number} = 0;
        }
        
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

