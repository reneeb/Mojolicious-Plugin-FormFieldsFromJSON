# This file is generated by Dist::Zilla::Plugin::SyncCPANfile v0.01
# Do not edit this file directly. To change prereqs, edit the `dist.ini` file.

requires "Mojo::File" => "0";
requires "Mojolicious" => "6.50";
requires "perl" => "5.010";

on 'configure' => sub {
    requires "ExtUtils::MakeMaker" => "0";
};

on 'configure' => sub {
    suggests "JSON::PP" => "2.27300";
};
