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
        'form_fields' => sub {
            my ($c, $file) = @_;
  
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
  
            return '' if !$configs{$file};
  
            my $config = $configs{$file};
  
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
  
                my $sub        = $self->can( '_' . $type );
                my $field_data = $self->$sub( $c, $field );
                return $field_data->{field};
            }
        }
    );
}

sub _text {
    my ($self, $c, $field) = @_;

    my $name  = $field->{name} // $field->{label} // '';
    my $value = $request{$name} // $field->{data} // '';
    my $id    = $field->{id} // $name;

    return +{
        label => $field->{label} // '',
        field => $c->text_field( $name, $value, id => $id ),
    };
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


=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
