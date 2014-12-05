package Mojolicious::Plugin::FormFieldsFromJSON;
use Mojo::Base 'Mojolicious::Plugin';

# ABSTRACT: create form fields based on a definition in a JSON file

our $VERSION = '0.06';

use Carp;
use File::Basename;
use File::Spec;
use IO::Dir;
use List::Util qw(first);

use Mojo::Asset::File;
use Mojo::Collection;
use Mojo::ByteStream;
use Mojo::JSON qw(decode_json);

our %request;

sub register {
    my ($self, $app, $config) = @_;

    $config //= {};
  
    my %configs;
    my $dir = $config->{dir} || '.';
  
    my %valid_types = (
        text     => 1,
        checkbox => 1,
        select   => 1,
        radio    => 1,
        hidden   => 1,
        textarea => 1,
        password => 1,
    );

    my %configfiles;
    $app->helper(
        forms => sub {
            if( %configfiles ) {
                return sort keys %configfiles;
            }

            my $dir = IO::Dir->new( $dir );

            FILE:
            while ( my $file = $dir->read ) {
                next FILE if $file !~ m{\.json\z};
                my $filename = basename $file;
                $filename    =~ s{\.json\z}{};
                $configfiles{$filename} = 1;
            }

            return sort keys %configfiles;
        }
    );

    $app->helper(
        fields => sub {
            my ($c, $file) = @_;

            if ( !$configs{$file} ) {
                $c->form_fields( $file, only_load => 1 );
            }

            my %fields;
            for my $field ( @{ $configs{$file} } ) {
                my $name = $field->{label} // $field->{name} // '';
                $fields{$name} = 1;
            }

            return sort keys %fields;
        }
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
  
            my $field_config = $configs{$file};

            my @fields;
  
            FIELD:
            for my $field ( @{ $field_config } ) {
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
  
                my $sub        = $self->can( '_' . $type );
                my $form_field = $self->$sub( $c, $field, %params );

                $form_field = Mojo::ByteStream->new( $form_field );

                my $template = $field->{template} // $config->{templates}->{$type} // $config->{template};
                if ( $template && $type ne 'hidden' ) {
                    $form_field = Mojo::ByteStream->new(
                        $c->render_to_string(
                            inline => $template,
                            id     => $field->{id} // $field->{name} // $field->{label} // '',
                            label  => $field->{label} // '',
                            field  => $form_field,
                        )
                    );
                }

                push @fields, $form_field;
            }

            return join "\n\n", @fields;
        }
    );
}

sub _hidden {
    my ($self, $c, $field) = @_;

    my $name  = $field->{name} // $field->{label} // '';
    my $value = $c->stash( $name ) // $request{$name} // $field->{data} // '';
    my $id    = $field->{id} // $name;
    my %attrs = %{ $field->{attributes} || {} };

    return $c->hidden_field( $name, $value, id => $id, %attrs );
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
    my ($self, $c, $field, %params) = @_;

    my $name   = $field->{name} // $field->{label} // '';

    my $field_params = $params{$name} || {},

    my %select_params = (
       disabled => $self->_get_highlighted_values( $field, 'disabled' ),
       selected => $self->_get_highlighted_values( $field, 'selected' ),
    );

    my $stash_values = $c->every_param( $name );
    my $reset;
    if ( @{ $stash_values || [] } ) {
        $select_params{selected} = $self->_get_highlighted_values(
            +{ selected => $stash_values },
            'selected',
        );
        $c->param( $name, '' );
        $reset = 1;
    }

    for my $key ( qw/disabled selected/ ) {
        my $hashref = $self->_get_highlighted_values( $field_params, $key );
        if ( keys %{ $hashref } ) {
            $select_params{$key} = $hashref;
        }
    }

    my @values = $self->_get_select_values( $c, $field, %select_params );
    my $id     = $field->{id} // $name;
    my %attrs  = %{ $field->{attributes} || {} };

    if ( $field->{multiple} ) {
        $attrs{multiple} = 'multiple';
        $attrs{size}     = $field->{size} || 5;
    }

    my $select_field = $c->select_field( $name, [ @values ], id => $id, %attrs );

    # reset parameters
    if ( $reset ) {
        my $single = scalar @{ $stash_values };
        my $param  = $single == 1 ? $stash_values->[0] : $stash_values;
        $c->param( $name, $param );
    }

    return $select_field;
}

sub _get_highlighted_values {
    my ($self, $field, $key) = @_;

    return +{} if !$field->{$key};

    my %highlighted;

    if ( !ref $field->{$key} ) {
        my $value = $field->{$key};
        $highlighted{$value} = 1;
    }
    elsif ( 'ARRAY' eq ref $field->{$key} ) {
        for my $value ( @{ $field->{$key} } ) {
            $highlighted{$value} = 1;
        }
    }

    return \%highlighted;
}

sub _get_select_values {
    my ($self, $c, $field, %params) = @_;

    my $data = $params{data} || $field->{data} || [];

    my @values;
    if ( 'ARRAY' eq ref $data ) {
        @values = $self->_transform_array_values( $data, %params );
    }
    elsif( 'HASH' eq ref $data ) {
        @values = $self->_transform_hash_values( $c, $data, %params );
    }

    return @values;
}

sub _transform_hash_values {
    my ($self, $c, $data, %params) = @_;

    my @values;
    my $numeric = 1;
    my $counter = 0;
    my %mapping;

    KEY:
    for my $key ( keys %{ $data } ) {
        if ( ref $data->{$key} ) {
            my @group_values = $self->_get_select_values( $c, +{ data => $data->{$key} }, %params );
            $values[$counter] = Mojo::Collection->new( $key => \@group_values );
            $mapping{$key} = $counter;
        }
        else {
            my %opts;

            $opts{disabled} = 'disabled' if $params{disabled}->{$key};
            $opts{selected} = 'selected' if $params{selected}->{$key};

            $values[$counter] = [ $data->{$key} => $key, %opts ];
            $mapping{$key}    = $counter;
        }

        $counter++;
    }

    if ( first{ $_ =~ m{[^0-9]} }keys %mapping ) {
        $numeric = 0;
    }

    my @sorted_keys = $numeric ? 
        sort { $a <=> $b }keys %mapping :
        sort { $a cmp $b }keys %mapping;

    my @indexes = @mapping{ @sorted_keys };

    my @sorted_values = @values[ @indexes ];

    return @sorted_values;
}

sub _transform_array_values {
    my ($self, $data, %params) = @_;

    my @values;
    my $numeric = 1;

    for my $value ( @{ $data } ) {
        if ( $numeric && $value =~ m{[^0-9]} ) {
            $numeric = 0;
        }

        my %opts;

        $opts{disabled} = 'disabled' if $params{disabled}->{$value};
        $opts{selected} = 'selected' if $params{selected}->{$value};

        push @values, [ $value => $value, %opts ];
    }

    @values = $numeric ?
        sort{ $a->[0] <=> $b->[0] }@values :
        sort{ $a->[0] cmp $b->[0] }@values;

    return @values;
}

sub _radio {
    my ($self, $c, $field, %params) = @_;

    my $name  = $field->{name} // $field->{label} // '';
    my $id    = $field->{id} // $name;
    my %attrs = %{ $field->{attributes} || {} };

    my $data   = $params{data} // $field->{data} // [];
    my @values = ref $data ? @{ $data } : ($data);

    my $field_params = $params{$name} || {},

    my %select_params = (
       disabled => $self->_get_highlighted_values( $field, 'disabled' ),
       selected => $self->_get_highlighted_values( $field, 'selected' ),
    );

    my $stash_values = $c->every_param( $name );
    my $reset;
    if ( @{ $stash_values || [] } ) {
        $select_params{selected} = $self->_get_highlighted_values(
            +{ selected => $stash_values },
            'selected',
        );
        $c->param( $name, '' );
        $reset = 1;
    }

    for my $key ( qw/disabled selected/ ) {
        my $hashref = $self->_get_highlighted_values( $field_params, $key );
        if ( keys %{ $hashref } ) {
            $select_params{$key} = $hashref;
        }
    }

    my $radiobuttons = '';
    for my $radio_value ( @values ) {
        my %value_attributes;

        if ( $select_params{disabled}->{$radio_value} ) {
            $value_attributes{disabled} = 'disabled';
        }

        if ( $select_params{selected}->{$radio_value} ) {
            $value_attributes{checked} = 'checked';
        }

        $radiobuttons .= $c->radio_button(
            $name => $radio_value,
            id => $id,
            %attrs,
            %value_attributes,
        ) . "\n";
    }

    if ( $reset ) {
        my $single = scalar @{ $stash_values };
        my $param  = $single == 1 ? $stash_values->[0] : $stash_values;
        $c->param( $name, $param );
    }

    return $radiobuttons;
}

sub _checkbox {
}

sub _textarea {
    my ($self, $c, $field) = @_;

    my $name  = $field->{name} // $field->{label} // '';
    my $value = $c->stash( $name ) // $request{$name} // $field->{data} // '';
    my $id    = $field->{id} // $name;
    my %attrs = %{ $field->{attributes} || {} };

    return $c->text_area( $name, $value, id => $id, %attrs );
}

sub _password {
    my ($self, $c, $field) = @_;

    my $name  = $field->{name} // $field->{label} // '';
    my $value = $c->stash( $name ) // $request{$name} // $field->{data} // '';
    my $id    = $field->{id} // $name;
    my %attrs = %{ $field->{attributes} || {} };

    return $c->password_field( $name, value => $value, id => $id, %attrs );
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

=head1 CONFIGURATION

You can configure some settings for the plugin:

=over 4

=item * dir

The directory where the json files for form field configuration are located

  $self->plugin( 'FormFieldsFromJSON' => {
    dir => '/home/mojo/fields',
  });

=item * template

With template you can define a template for the form fields.

  $self->plugin( 'FormFieldsFromJSON' => {
    template => '<label for="<%= $id %>"><%= $label %>:</label><div><%= $field %></div>',
  });

See L<Templates|Mojolicious::Plugin::FormFieldsFromJSON/Templates>.

=item * templates

With template you can define type specific templates for the form fields.

  plugin 'FormFieldsFromJSON' => {
    templates => {
      text => '<%= $label %>: <%= $field %>',
    },
  };

See L<Templates|Mojolicious::Plugin::FormFieldsFromJSON/Templates>.

=back

=head1 HELPER

=head2 form_fields

  $controller->form_fields( 'formname' );

=head2 validate_form_fields

=head2 forms

=head2 fields

=head1 FIELD DEFINITIONS

This plugin supports several form fields:

=over 4

=item * text

=item * checkbox

=item * radio

=item * select

=item * textarea

=item * password

=item * hidden

=back

Those fields have the following definition items in common:

=over 4

=item * label

=item * type

=item * data

=item * attributes

Attributes of the field like "class"

=back

=head1 EXAMPLES

The following sections should give you an idea what's possible with this plugin

=head2 text

With type I<text> you get a simple text input field.

=head3 A simple text field

This is the configuration for a simple text field:

 [
    {
        "label" : "Name",
        "type" : "text",
        "name" : "name"
    }
 ]

And the generated form field looks like

 <input id="name" name="name" type="text" value="" />

=head3 Set CSS classes

If you want to set a CSS class, you can use the C<attributes> field:

 [
    {
        "label" : "Name",
        "type" : "text",
        "name" : "name",
        "attributes" : {
            "class" : "W75px"
        }
    }
 ]

And the generated form field looks like

 <input class="W75px" id="name" name="name" type="text" value="" />

=head3 Text field with predefined value

Sometimes, you want to predefine a value shown in the text field. Then you can
use the C<data> field:

 [
    {
        "label" : "Name",
        "type" : "text",
        "name" : "name",
        "data" : "default value"
    }
 ]

This will generate this input field:

  <input id="name" name="name" type="text" value="default value" />

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

=head3 Multiselect

  [
    {
      "type" : "select",
      "name" : "languages",
      "data" : [
        "de",
        "en",
        "cn",
        "jp"
      ],
      "multiple" : 1,
      "size" : 3
    }
  ]

This creates the following select field:

  <select id="languages" name="languages" multiple="multiple" size="3">
      <option value="cn">cn</option>
      <option value="de">de</option>
      <option value="en">en</option>
      <option value="jp">jp</option>
  </select>

=head3 Preselect multiple values

  [
    {
      "type" : "select",
      "name" : "languages",
      "data" : [
        "de",
        "en",
        "cn",
        "jp"
      ],
      "multiple" : 1,
      "selected" : [ "en", "de" ]
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="cn">cn</option>
      <option value="de" selected="selected">de</option>
      <option value="en" selected="selected">en</option>
      <option value="jp">jp</option>
  </select>

=head3 Values != Label

  [
    {
      "type" : "select",
      "name" : "language",
      "data" : {
        "de" : "German",
        "en" : "English"
      }
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="en">English</option>
      <option value="de">German</option>
  </select>

=head3 Option groups

  [
    {
      "type" : "select",
      "name" : "language",
      "data" : {
        "EU" : {
          "de" : "German",
          "en" : "English"
        },
        "Asia" : {
          "cn" : "Chinese",
          "jp" : "Japanese"
        }
      }
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="en">English</option>
      <option value="de">German</option>
  </select>

=head3 Disable values

  [
    {
      "type" : "select",
      "name" : "languages",
      "data" : [
        "de",
        "en",
        "cn",
        "jp"
      ],
      "multiple" : 1,
      "disabled" : [ "en", "de" ]
    }
  ]

This creates the following select field:

  <select id="language" name="language">
      <option value="cn">cn</option>
      <option value="de" disabled="disabled">de</option>
      <option value="en" disabled="disabled">en</option>
      <option value="jp">jp</option>
  </select>

=head2 radio

For radiobuttons, you can use two ways: You can either configure
form fields for each value or you can define a list of values in
the C<data> field. With the first way, you can create radiobuttons
where the template (if any defined) is applied to each radiobutton.
With the second way, the radiobuttons are handled as one single 
field in the template.

=head3 A single radiobutton

Given the configuration

 [
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : "internal"
    }
 ]

You get



=head3 Two radiobuttons configured seperately

With the configuration

 [
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : "internal"
    },
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : "external"
    }
 ]

You get

=head3 Two radiobuttons as a group

And with

 [
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : ["internal", "external" ]
    }
 ]

You get

=head3 Two radiobuttons configured seperately - with template

Define template:

  plugin 'FormFieldsFromJSON' => {
    dir      => './conf',
    template => '<%= $label %>: <%= $form %>';
  };

Config:

 [
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : "internal"
    },
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : "external"
    }
 ]

Fields:

  Name: <input id="type" name="type" type="radio" value="internal" />
  
  
  
  Name: <input id="type" name="type" type="radio" value="external" />
  
  

=head3 Two radiobuttons as a group - with template

Same template definition as above, but given this field config:

 [
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : ["internal", "external" ]
    }
 ]

You get this:

  Name: <input id="type" name="type" type="radio" value="internal" />
  <input id="type" name="type" type="radio" value="external" />

=head3 Two radiobuttons - one checked

Config:

 [
    {
        "label" : "Name",
        "type" : "radio",
        "name" : "type",
        "data" : ["internal", "external" ],
        "selected" : ["internal"]
    }
 ]

Field:

  <input checked="checked" id="type" name="type" type="radio" value="internal" />
  <input id="type" name="type" type="radio" value="external" />

=head2 checkbox

=head2 textarea

This type is very similar to L<text|Mojolicious::Plugin::FormFieldsFromJSON/text>.

=head3 A simple textarea

This is the configuration for a simple text field:

 [
    {
        "type" : "textarea",
        "name" : "message",
        "data" : "Current message"
    }
 ]

And the generated form field looks like

  <textarea id="message" name="message">Current message</textarea>

=head3 A textarea with defined number of columns and rows

This is the configuration for a simple text field:

 [
    {
        "type" : "textarea",
        "name" : "message",
        "data" : "Current message",
        "attributes" : {
            "cols" : 80,
            "rows" : 10
        }
    }
 ]

And the generated textarea looks like

  <textarea cols="80" id="message" name="message" rows="10">Current message</textarea>

=head2 password

This type is very similar to L<text|Mojolicious::Plugin::FormFieldsFromJSON/text>.
You can use the very same settings as for text fields, so we show only a simple
example here:

=head3 A simple password field

This is the configuration for a simple text field:

 [
    {
        "type" : "password",
        "name" : "user_password"
    }
 ]

And the generated form field looks like

 <input id="user_password" name="password" type="password" value="" />

=head1 Templates

Especially when you work with frameworks like Bootstrap, you want to 
your form fields to look nice. For that the form fields are within
C<div>s or other HTML elements.

To make your life easier, you can define templates. Either a "global"
one, a type specific template or a template for one field.

For hidden fields, no template is applied!

=head2 A global template

When you load the plugin this way

  $self->plugin( 'FormFieldsFromJSON' => {
    template => '<label for="<%= $id %>"><%= $label %>:</label><div><%= $field %></div>',
  });

and have a configuration that looks like

You get

  <label for="name">Name:</label><div><input id="name" name="name" type="text" value="" /></div>
  
   
  <label for="password">Password:</label><div><input id="password" name="password" type="text" value="" /></div>

=head2 A type specific template

When you want to use a different template for select fields, you can use a
different template for that kind of fields:

  plugin 'FormFieldsFromJSON' => {
    dir       => File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf' ),
    template  => '<label for="<%= $id %>"><%= $label %>:</label><div><%= $field %></div>',
    templates => {
      select => '<%= $label %>: <%= $field %>',
    },
  };

With a configuration file like 

 [
    {
        "label" : "Name",
        "type" : "text",
        "name" : "name"
    }
    {
        "label" : "Country",
        "type" : "select",
        "name" : "country",
        "data" : [ "au" ]
    }
 ]

You get 

  <label for="name">Name:</label><div><input id="name" name="name" type="text" value="" /></div>
  
   
  Country: <select id="country" name="country"><option value="au">au</option></select>

=head2 A field specific template

When you want to use a different template for a specific field, you can use the
C<template> field in the configuration file.

  plugin 'FormFieldsFromJSON' => {
    dir       => File::Spec->catdir( dirname( __FILE__ ) || '.', 'conf' ),
    template  => '<label for="<%= $id %>"><%= $label %>:</label><div><%= $field %></div>',
  };

With a configuration file like 

 [
    {
        "label" : "Name",
        "type" : "text",
        "name" : "name"
    }
    {
        "label" : "Country",
        "type" : "select",
        "name" : "country",
        "data" : [ "au" ],
        "template" : "<%= $label %>: <%= $field %>"
    }
 ]

You get 

  <label for="name">Name:</label><div><input id="name" name="name" type="text" value="" /></div>
  
   
  Country: <select id="country" name="country"><option value="au">au</option></select>

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
