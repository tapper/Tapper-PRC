use strict;
use warnings;

use inc::Module::Install;

name     'Tapper-PRC';
all_from 'lib/Tapper/PRC.pm';
author   'AMD OSRC Tapper Team <tapper@amd64.org>';
license  'freebsd';

build_requires 'Test::Fixture::DBIC::Schema' => 0;
build_requires 'Test::Perl::Critic'          => 0;
build_requires 'Test::MockModule'            => 0;
build_requires 'Test::More'                  => 0;
build_requires 'Tapper::Test' => "3.000010";
build_requires 'Tapper::Config' => "3.000012";

author_requires 'Module::Install::WriteAll';

requires 'perl'               => '5.010';
requires 'Tapper::Base' => "3.000010";
requires 'Tapper::Remote' => "3.000011";
requires 'Moose'              => 0;
requires 'Log::Log4perl'      => 0;
requires 'List::Util'         => 0;
requires 'IPC::Open3'         => 0;
requires 'File::Path'         => 0;
requires 'App::Daemon'        => 0;
requires 'File::Temp'         => 0;
requires 'common::sense'      => 0;
requires 'YAML'               => "0.72";
requires 'Mojo::Util';

repository 'git://github.com/amd/Tapper-Reports-PRC.git';
bugtracker 'http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Tapper-PRC';

install_script glob('bin/*');

WriteAll;
