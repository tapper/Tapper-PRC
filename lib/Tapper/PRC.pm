package Tapper::PRC;

use strict;
use warnings;

use IO::Socket::INET;
use YAML::Syck;
use Moose;
use Log::Log4perl;
use URI::Escape;


extends 'Tapper::Base';

with 'MooseX::Log::Log4perl';

our $VERSION = '3.000010';

=head1 NAME

Tapper::PRC - Tapper - Program run control for test program automation

=head1 SYNOPSIS

 use Tapper::PRC;

=head1 FUNCTIONS

=cut

has cfg => (is      => 'rw',
            isa     => 'HashRef',
            default => sub { {} },
           );

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
        my $port   = $self->cfg->{mcp_port} || $self->cfg->{port} || 1337;
        $message->{testrun_id} ||= $self->cfg->{test_run};
        my %headers;

        my $url = "GET /state/";

        # state always needs to be first URL part because server uses it as filter
        $url   .= $message->{state} || 'unknown';
        delete $message->{state};

        foreach my $key (keys %$message) {
                if ($message->{$key} =~ m|/| ) {
                        $headers{$key} = $message->{$key};
                } else {
                        $url .= "/$key/";
                        $url .= uri_escape($message->{$key});
                }
        }
        $url .= " HTTP/1.0\r\n";
        foreach my $header (keys %headers) {
                $url .= "X-Tapper-$header: ";
                $url .= $headers{$header};
                $url .= "\r\n";
        }

	if (my $sock = IO::Socket::INET->new(PeerAddr => $server,
					     PeerPort => $port,
					     Proto    => 'tcp')){
		$sock->print("$url\r\n");
		close $sock;
	} else {
                return("Can't connect to MCP: $!\r\n\r\n");
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
        if ($self->cfg->{guest_number}) {
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

AMD OSRC Tapper Team, C<< <tapper at amd64.org> >>

=head1 BUGS

None.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

 perldoc Tapper


=head1 ACKNOWLEDGEMENTS


=head1 COPYRIGHT & LICENSE

Copyright 2008-2011 AMD OSRC Tapper Team, all rights reserved.

This program is released under the following license: freebsd

