#!/usr/bin/env perl

use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use File::Basename;
use File::Spec;

plugin 'FormFieldsFromJSON' => {
  dir      => [File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf/a' ), File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf/b' )],
  template => '<label for="<%= $id %>"><%= $label %>:</label><div><%= $field %></div>',
};

my $config_name = basename __FILE__;
$config_name    =~ s{\A \d+_ }{}xms;
$config_name    =~ s{\.t \z }{}xms;
my $a_config_name = "a_".$config_name;
my $b_config_name = "b_".$config_name;

get '/conf_a' => sub {
  my $c = shift;
  my ($textfield) = $c->form_fields( $a_config_name );
  $c->render(text => $textfield);
};

get '/conf_b' => sub {
  my $c = shift;
  my ($textfield) = $c->form_fields( $b_config_name );
  $c->render(text => $textfield);
};

my $close = Mojolicious->VERSION >= 5.73 ? '' : " /";

my $t = Test::Mojo->new;
$t->get_ok('/conf_a')
  ->status_is(200)
  ->content_is(qq~<label for="name_a">Name:</label><div><input id="name_a" name="name_a" type="text" value=""$close></div>\n~);

$t->get_ok('/conf_b')
  ->status_is(200)
  ->content_is(qq~<label for="name_b">Name:</label><div><input id="name_b" name="name_b" type="text" value=""$close></div>\n~);

done_testing();

