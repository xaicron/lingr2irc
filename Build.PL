use strict;
use warnings;
use Module::Build::Pluggable qw(CPANfile);

my $build = Module::Build::Pluggable->new(
    license        => 'perl',
    dynamic_config => 0,

    configure_requires => {},
    build_requires     => {},
    requires           => {
        perl => '5.008001',
    },

    no_index    => { 'directory' => [ 'inc' ] },
    name        => 'App-Lingr2IRC',
    module_name => 'App::Lingr2IRC',

    # script_files => [''],

    test_files           => (-d '.git' || $ENV{RELEASE_TESTING}) ? 't/ xt/' : 't/',
    recursive_test_files => 1,

    meta_merge => {
        resources => {
            repository => 'https://github.com/xaicron/p5-App-Lingr2IRC',
            bugtracker => 'https://github.com/xaicron/p5-App-Lingr2IRC/issues',
        },
    },

    create_readme  => 1,
    create_license => 1,
);

$build->create_build_script();
