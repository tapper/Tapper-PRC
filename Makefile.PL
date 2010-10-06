use strict;
use warnings;

use inc::Module::Install;

name     'Artemis-PRC';
all_from 'lib/Artemis/PRC.pm';
author   'OSRC SysInt Team <osrc-sysint@elbe.amd.com>';

build_requires 'Test::Fixture::DBIC::Schema' => 0;
build_requires 'Test::MockModule'            => 0;
build_requires 'Test::More'                  => 0;
build_requires 'Artemis::Test'               => '2.010005';

requires 'perl'               => '5.010';
requires 'Artemis::Base'      => '0.010008';
requires 'Artemis::Remote'    => '1.000001';
requires 'Moose'              => 0;
requires 'Log::Log4perl'      => 0;
requires 'List::Util'         => 0;
requires 'IPC::Open3'         => 0;
requires 'File::Path'         => 0;
requires 'common::sense'      => 0;


WriteAll;
