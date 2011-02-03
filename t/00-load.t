#! /usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 2;

BEGIN {
        use_ok( 'Tapper::PRC' );
        use_ok( 'Tapper::PRC::Testcontrol' );
}

diag( "Testing Tapper::PRC $Tapper::PRC::VERSION, Perl $], $^X" );
