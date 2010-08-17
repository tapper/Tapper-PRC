#! /usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

BEGIN {
        use_ok( 'Artemis::PRC' );
        use_ok( 'Artemis::PRC::Testcontrol' );
}

diag( "Testing Artemis::PRC $Artemis::PRC::VERSION, Perl $], $^X" );
