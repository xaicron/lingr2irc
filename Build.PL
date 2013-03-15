use strict;
use warnings;
use Module::Build::Pluggable qw(CPANfile GithubMeta);

my $build = Module::Build::Pluggable->new(
    license        => 'perl',
    dynamic_config => 0,

    configure_requires => {},
    build_requires     => {},
    requires           => {
        perl => '5.001001',
    },

    no_index    => { 'directory' => [ 'inc' ] },
    name        => 'App-Lingr2IRC',
    module_name => 'App::Lingr2IRC',

    script_files => ['./bin/lingr2irc'],

    test_files           => (-d '.git' || $ENV{RELEASE_TESTING}) ? 't/ xt/' : 't/',
    recursive_test_files => 1,

    create_readme  => 1,
    create_license => 1,
);

$build->create_build_script();
