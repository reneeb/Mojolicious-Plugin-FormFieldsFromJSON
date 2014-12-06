#!/usr/bin/env perl

use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use File::Basename;
use File::Spec;

plugin 'FormFieldsFromJSON' => {
  dir => File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf' ),
};

my $config_name = basename __FILE__;
$config_name    =~ s{\A \d+_ }{}xms;
$config_name    =~ s{\.t \z }{}xms;

get '/' => sub {
  my $c = shift;
  my ($field) = $c->form_fields( $config_name );
  $c->render(text => $field);
};

get '/test' => sub {
  my $c = shift;

  $c->param( type => 'internal' );

  my ($field) = $c->form_fields( $config_name );
  $c->render(text => $field);
};

get '/set' => sub {
  my $c = shift;
  my ($field) = $c->form_fields( $config_name, type => { selected => 'internal' } );
  $c->render(text => $field);
};

get '/reset' => sub {
  my $c = shift;
  my ($field) = $c->form_fields( $config_name, type => { selected => 'internal' } );
  $c->render(text => $c->param('type') . $field );
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_is(
  '<input checked="checked" id="type" name="type" type="checkbox" value="internal" />' . "\n" .
  '<input id="type" name="type" type="checkbox" value="external" />' . "\n"
);

$t->get_ok('/?type=internal')->status_is(200)->content_is(
  '<input checked="checked" id="type" name="type" type="checkbox" value="internal" />' . "\n" .
  '<input id="type" name="type" type="checkbox" value="external" />' . "\n"
);

$t->get_ok('/test')->status_is(200)->content_is(
  '<input checked="checked" id="type" name="type" type="checkbox" value="internal" />' . "\n" .
  '<input id="type" name="type" type="checkbox" value="external" />' . "\n"
);

$t->get_ok('/set')->status_is(200)->content_is(
  '<input checked="checked" id="type" name="type" type="checkbox" value="internal" />' . "\n" .
  '<input id="type" name="type" type="checkbox" value="external" />' . "\n"
);

$t->get_ok('/reset?type=external')->status_is(200)->content_is(
  'external' .
  '<input checked="checked" id="type" name="type" type="checkbox" value="internal" />' . "\n" .
  '<input id="type" name="type" type="checkbox" value="external" />' . "\n"
);

done_testing();

