#!/usr/bin/env perl

use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use File::Basename;
use File::Spec;

{
    package
        FunctionTest;

    sub defaulttext {
        my ($class, $controller, $field_config) = @_;

        return "default";
    }
}

plugin 'FormFieldsFromJSON' => {
  dir                => File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf' ),
  datafunctionclass  => 'FunctionTest',
};

my $config_name = basename __FILE__;
$config_name    =~ s{\A \d+_ }{}xms;
$config_name    =~ s{\.t \z }{}xms;

get '/' => sub {
  my $c = shift;
  my ($textfield) = $c->form_fields( $config_name );
  $c->render(text => $textfield);
};

my $t = Test::Mojo->new;
$t->get_ok('/')
  ->status_is(200)
  ->content_is(
    '<input id="name" name="name" type="text" value="default" />' . "\n\n" . 
    '<input id="name2" name="name2" type="text" value="" />'
  );

done_testing();

