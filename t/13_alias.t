#!/usr/bin/env perl

use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use File::Basename;
use File::Spec;

plugin 'FormFieldsFromJSON' => {
  dir       => File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf' ),
  template  => '<label for="<%= $id %>"><%= $label %>:</label><div><%= $field %></div>',
  templates => {
    date => '<label for="<%= $id %>"><%= $label %> date:</label><div><%= $field %></div>',
  },
  alias => {
    date => 'text',
  },
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
     '<label for="name">Name:</label><div><input id="name" name="name" type="text" value="" /></div>'
     . "\n\n\n" .
     '<label for="expiration">expiration date:</label><div><input id="expiration" name="expiration" type="text" value="" /></div>' .
     "\n"
  );

done_testing();

