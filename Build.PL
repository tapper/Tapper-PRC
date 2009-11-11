use strict;
use warnings;
use Module::Build;


my $build_class = 'Module::Build';
$build_class    = $build_class->subclass(code => <<'HERE'
 sub process_libauto_files {
        system("mkdir -p blib/lib/auto");
        system("cp -ra lib/auto/* blib/lib/auto/");
        system("chmod -R u+w blib/lib/auto/*"); # dirty hack around ./Build dist with wrong perms
 }
HERE
);

my $builder = $build_class->new
    (
     module_name         => 'Artemis::PRC',
     license             => 'restrictive',
     dist_author         => 'OSRC SysInt Team <osrc-sysint@elbe.amd.com>',
     dist_version_from   => 'lib/Artemis/PRC.pm',
     dist_abstract       => 'Automatic testing environment',
     build_requires => {
                        'Test::Fixture::DBIC::Schema' => 0,
                        'Test::MockModule'            => 0,
                        'Test::More'                  => 0,
                        'Artemis::Test'               => '2.010005',
                        'Artemis::Config'             => '2.010053',
                       },
     requires => {
                  'perl'               => '5.010',
                  'Artemis::Base'      => '0.010007',
                  'Method::Signatures' => 0,
                  'Moose'              => 0,
                  'Log::Log4perl'      => 0,
                  'List::Util'         => 0,
                  'IPC::Open3'         => 0,
                  'File::Path'         => 0,
                 },
     add_to_cleanup      => [ 'Artemis-*' ],
    );

$builder->create_build_script();

1;
