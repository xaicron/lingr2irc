# requires 'Foo::Bar' => '0.01';

on configure => sub {
    requires 'Module::Build'                      => '0.40';
    requires 'Module::Build::Pluggable::CPANfile' => '0.02';
};

on test => sub {
    requires 'Test::More'     => '0.98';
    requires 'Test::Requires' => '0.06';
};

on develop => sub {
    requires 'Test::Pretty'         => '0.22';
    requires 'Test::Name::FromLine' => '0.09';
};
