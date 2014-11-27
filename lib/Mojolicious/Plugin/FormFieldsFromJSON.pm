package Mojolicious::Plugin::FormFieldsFromJSON;
use Mojo::Base 'Mojolicious::Plugin';

# ABSTRACT: create form fields based on a definition in a JSON file

our $VERSION = '0.01';

use Carp;
use File::Spec;

use Mojo::Asset::File;
use Mojo::JSON qw(decode_json);

our %request;

sub register {
    my ($self, $app, $config) = @_;
  
    my %configs;
    my $dir = $config->{dir} || '.';
  
    my %valid_types = (
        text     => 1,
        checkbox => 1,
        select   => 1,
        radio    => 1,
    );

    $app->helper(
        'validate_form_fields' => sub {
            my ($c, $file) = @_;
  
            return '' if !$file;
  
            if ( !$configs{$file} ) {
                $c->form_fields( $file, only_load => 1 );
            }
  
            return '' if !$configs{$file};
  
            my $config = $configs{$file};

            my $validation = $c->validation;
            $validation->input( $c->tx->req->params->to_hash );

            my %errors;
  
            FIELD:
            for my $field ( @{ $config } ) {
                if ( 'HASH' ne ref $field ) {
                    $app->log->error( 'Field definition must be a HASH - skipping field' );
                    next FIELD;
                }

                if ( !$field->{validation} ) {
                    next FIELD;
                }

                if ( 'HASH' ne ref $field->{validation} ) {
                    $app->log->warn( 'Validation settings must be a HASH - skipping field' );
                    next FIELD;
                }

                my $name = $field->{name} // $field->{label} // '';

                if ( $field->{validation}->{required} ) {
                    $validation->required( $name );
                }
                else {
                    $validation->optional( $name );
                }

                RULE:
                for my $rule ( keys %{ $field->{validation} } ) {
                    my @params = ( $field->{validation}->{$rule} );
                    my $method = $rule;

                    if ( ref $field->{validation}->{$rule} ) {
                        @params = @{ $field->{validation}->{$rule} };
                    }

                    if ( $method eq 'required' ) {
                        $validation->required( $name );
                        next RULE;
                    }

                    eval{
                        $validation->check( $method, @params );
                    } or do {
                        $app->log->error( "Validating $name with rule $method failed: $@" );
                    };

                    if ( !$validation->is_valid( $name ) ) {
                        $errors{$name} = 1;
                        last RULE;
                    }
                }

                if ( !$validation->is_valid( $name ) ) {
                    $errors{$name} = 1;
                }
            }

            return %errors;
        }
    );
  
    $app->helper(
        'form_fields' => sub {
            my ($c, $file, %params) = @_;
  
            return '' if !$file;
  
            if ( !$configs{$file} ) {
                my $path = File::Spec->catfile( $dir, $file . '.json' );
                return '' if !-r $path;
  
                eval {
                    my $content = Mojo::Asset::File->new( path => $path )->slurp;
                    $configs{$file} = decode_json $content;
                } or do {
                    $app->log->error( "FORMFIELDS $file: $@" );
                    return '';
                };
  
                if ( 'ARRAY' ne ref $configs{$file} ) {
                    $app->log->error( 'Definition JSON must be an ARRAY' );
                    return '';
                }
            }
 
            return if $params{only_load}; 
            return '' if !$configs{$file};
  
            my $config = $configs{$file};

            my @fields;
  
            FIELD:
            for my $field ( @{ $config } ) {
                if ( 'HASH' ne ref $field ) {
                    $app->log->error( 'Field definition must be an HASH - skipping field' );
                    next FIELD;
                }
  
                my $type = $field->{type};
  
                if ( !$valid_types{$type} ) {
                    $app->log->warn( "Invalid field type $type - falling back to 'text'" );
                    $type = 'text';
                }

                local %request = %{ $c->tx->req->params->to_hash };
  
                my $sub   = $self->can( '_' . $type );
                my $field = $self->$sub( $c, $field );
                push @fields, $field;
            }

            return @fields;
        }
    );
}

sub _text {
    my ($self, $c, $field) = @_;

    my $name  = $field->{name} // $field->{label} // '';
    my $value = $c->stash( $name ) // $request{$name} // $field->{data} // '';
    my $id    = $field->{id} // $name;
    my %attrs = %{ $field->{attributes} || {} };

    return $c->text_field( $name, $value, id => $id, %attrs );
}

sub _select {
    my ($self, $c, $field) = @_;

    my $name   = $field->{name} // $field->{label} // '';
    my @values = $self->_get_select_values( $c, $field );
    my $id     = $field->{id} // $name;
    my %attrs  = %{ $field->{attributes} || {} };

    return $c->select_field( $name, [ @values ], id => $id, %attrs );
}

sub _get_select_values {
    my ($self, $c, $field) = @_;

    
}

sub _radio {
}

sub _checkbox {
}

1;

__END__

=encoding utf8

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('FormFieldsFromJSON');

  # Mojolicious::Lite
  plugin 'FormFieldsFromJSON';

=head1 DESCRIPTION

L<Mojolicious::Plugin::FormFieldsFromJSON> is a L<Mojolicious> plugin.

=head1 HELPER

=head2 form_fields

  $controller->form_fields( 'formname' );

=head1 FIELD DEFINITIONS

This plugin supports several form fields:

=over 4

=item * text

=item * checkbox

=item * radio

=item * select

=back

Those fields have the following definition items in common:

=over 4

=item * label

=item * type

=item * data

=item * data_function

=item * attributes

Attributes of the field like "class"

=back

=head1 EXAMPLES

The following sections should give you an idea what's possible with this plugin

=head2 text

=head3 A simple text field

=head3 Set CSS classes

=head2 select

=head3 Simple: Value = Label

When you have a list of values for a select field, you can define
an array reference:

  [
    {
      "type" : "select",
      "name" : "language",
      "data" : [
        "de",
        "en"
      ]
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="de">de</option>
      <option value="en">en</option>
  </select>

=head3 Preselect a value

You can define

  [
    {
      "type" : "select",
      "name" : "language",
      "data" : [
        "de",
        "en"
      ],
      "selected" : "en"
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="de">de</option>
      <option value="en" selected="selected">en</option>
  </select>

If a key named as the select exists in the stash, those values are preselected
(this overrides the value defined in the .json):

  $c->stash( language => 'en' );

and

  [
    {
      "type" : "select",
      "name" : "language",
      "data" : [
        "de",
        "en"
      ]
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="de">de</option>
      <option value="en" selected="selected">en</option>
  </select>

=head3 Values != Label

You can define


=head2 radio

=head2 checkbox

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
