#!/usr/bin/env perl

use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;
use File::Basename;
use File::Spec;

plugin 'FormFieldsFromJSON' => {
  dir => File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf' ),
  global_attributes => {
    class => 'test',
  },
};

my $config_name = basename __FILE__;
$config_name    =~ s{\A \d+_ }{}xms;
$config_name    =~ s{\.t \z }{}xms;

get '/' => sub {
  my $c = shift;
  my $fields = $c->form_fields( $config_name );
  $c->render(text => $fields);
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_is(
  '<select class=" test" id="language" name="language">' .
  '<option value="de">de</option>' .
  '<option value="en">en</option>' .
  '</select>' .
  "\n\n" .
  '<input class=" test" id="name" name="name" type="text" value="" />' .
  "\n\n" .
  '<input id="id" name="id" type="hidden" value="hello" />' .
  "\n\n" .
  '<input class=" test" id="pwd" name="pwd" type="password" value="" />' .
  "\n\n" .
  '<input class=" test" id="filter" name="filter" type="checkbox" value="age" />' .
  "\n\n\n" .
  '<input class=" test" id="type" name="type" type="radio" value="internal" />' .
  "\n" .
  '<input class=" test" id="type" name="type" type="radio" value="external" />' .
  "\n\n\n" .
  '<textarea class=" test" id="comment" name="comment"></textarea>'
);

done_testing();

