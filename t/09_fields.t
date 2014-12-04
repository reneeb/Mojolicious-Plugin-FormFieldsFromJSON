#!/usr/bin/perl

use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use File::Basename;
use File::Spec;

plugin 'FormFieldsFromJSON' => {
  dir => File::Spec->catdir( dirname( __FILE__ ) || '.', 'formsconf' ),
};

get '/' => sub {
  my $c = shift;
  my @fields = $c->fields('template_twofields');

  $c->render(text => join ' .. ', @fields );
};

my $t = Test::Mojo->new;
$t->get_ok('/')
  ->status_is(200)
  ->content_is('Name .. Password');

done_testing();
