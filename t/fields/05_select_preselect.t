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

get '/t' => sub {
  my $c = shift;

  $c->stash( language => 'de' );

  my ($field) = $c->form_fields( $config_name );
  $c->render(text => $field);
};

my $t = Test::Mojo->new;
$t->get_ok('/')->status_is(200)->content_is(qq~<select id="language" name="language">
  <option value="cn">cn</option>
  <option value="de">de</option>
  <option value="en" selected="selected">en</option>
</select>~);

$t->get_ok('/?language=de')->status_is(200)->content_is(qq~<select id="language" name="language">
  <option value="cn">cn</option>
  <option value="de" selected="selected">de</option>
  <option value="en">en</option>
</select>~);

$t->get_ok('/test')->status_is(200)->content_is(qq~<select id="language" name="language">
  <option value="cn">cn</option>
  <option value="de" selected="selected">de</option>
  <option value="en">en</option>
</select>~);

done_testing();

