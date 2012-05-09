package Tapper::PRC;
# ABSTRACT: Tapper - Program run control for test program automation

use strict;
use warnings;

use IO::Socket::INET;
use YAML::Syck;
use Moose;
use Log::Log4perl;
use URI::Escape;

extends 'Tapper::Base';
with 'MooseX::Log::Log4perl';

has cfg => (is      => 'rw',
            isa     => 'HashRef',
            default => sub { {} },
           );
with 'Tapper::Remote::Net';

=head1 FUNCTIONS

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
