package Catalyst::Engine::Test;

use strict;
use base 'Catalyst::Engine';

use CGI::Cookie;
use Class::Struct ();
use HTTP::Headers::Util 'split_header_words';
use HTTP::Request;
use HTTP::Response;
use IO::File;
use URI;

__PACKAGE__->mk_accessors(qw/lwp/);

Class::Struct::struct 'Catalyst::Engine::Test::LWP' => {
    request  => 'HTTP::Request',
    response => 'HTTP::Response',
    hostname => '$',
    address  => '$'
};

=head1 NAME

Catalyst::Engine::Test - Catalyst Test Engine

=head1 SYNOPSIS

A script using the Catalyst::Engine::Test module might look like:

    #!/usr/bin/perl -w

    BEGIN { 
       $ENV{CATALYST_ENGINE} = 'Test';
    }

    use strict;
    use lib '/path/to/MyApp/lib';
    use MyApp;

    MyApp->run('/a/path');

=head1 DESCRIPTION

This is the Catalyst engine specialized for testing.

=head1 OVERLOADED METHODS

This class overloads some methods from C<Catalyst::Engine>.

=over 4

=item $c->finalize_headers

=cut

sub finalize_headers {
    my $c = shift;

    $c->lwp->response->code( $c->response->status || 200 );

    for my $name ( $c->response->headers->header_field_names ) {
        $c->lwp->response->header( $name => $c->response->header($name) );
    }

    while ( my ( $name, $cookie ) = each %{ $c->response->cookies } ) {
        my $cookie = CGI::Cookie->new(
            -name    => $name,
            -value   => $cookie->{value},
            -expires => $cookie->{expires},
            -domain  => $cookie->{domain},
            -path    => $cookie->{path},
            -secure  => $cookie->{secure} || 0
        );

        $c->lwp->response->header( 'Set-Cookie' => $cookie->as_string );
    }
}

=item $c->finalize_output

=cut

sub finalize_output {
    my $c = shift;
    $c->lwp->response->content_ref( \$c->response->{output} );
}

=item $c->prepare_connection

=cut

sub prepare_connection {
    my $c = shift;
    $c->req->hostname( $c->lwp->hostname );
    $c->req->address( $c->lwp->address );
}

=item $c->prepare_cookies

=cut

sub prepare_cookies {
    my $c = shift;

    if ( my $header = $c->request->header('Cookie') ) {
        $c->req->cookies( { CGI::Cookie->parse($header) } );
    }
}

=item $c->prepare_headers

=cut

sub prepare_headers {
    my $c = shift;
    $c->req->method( $c->lwp->request->method );
    $c->req->headers( $c->lwp->request->headers );
}

=item $c->prepare_parameters

=cut

sub prepare_parameters {
    my $c = shift;

    my @params  = ();
    my $request = $c->lwp->request;

    push( @params, $request->uri->query_form );

    if ( $request->content_type eq 'application/x-www-form-urlencoded' ) {
        my $uri = URI->new('http:');
        $uri->query( $request->content );
        push( @params, $uri->query_form );
    }

    if ( $request->content_type eq 'multipart/form-data' ) {

        for my $part ( $request->parts ) {

            my $disposition = $part->header('Content-Disposition');
            my %parameters  = @{ ( split_header_words($disposition) )[0] };

            if ( $parameters{filename} ) {

                my $fh = IO::File->new_tmpfile;
                $fh->write( $part->content ) or die $!;
                $fh->seek( SEEK_SET, 0 ) or die $!;

                $c->req->uploads->{ $parameters{filename} } = {
                    fh   => $fh,
                    size => ( stat $fh )[7],
                    type => $part->content_type
                };

                push( @params, $parameters{filename}, $fh );
            }
            else {
                push( @params, $parameters{name}, $part->content );
            }
        }
    }

    my $parameters = $c->req->parameters;

    while ( my ( $name, $value ) = splice( @params, 0, 2 ) ) {

        if ( exists $parameters->{$name} ) {
            for ( $parameters->{$name} ) {
                $_ = [$_] unless ref($_) eq "ARRAY";
                push( @$_, $value );
            }
        }
        else {
            $parameters->{$name} = $value;
        }
    }
}

=item $c->prepare_path

=cut

sub prepare_path {
    my $c = shift;

    my $base;
    {
        my $scheme = $c->lwp->request->uri->scheme;
        my $host   = $c->lwp->request->uri->host;
        my $port   = $c->lwp->request->uri->port;

        $base = URI->new;
        $base->scheme($scheme);
        $base->host($host);
        $base->port($port);

        $base = $base->canonical->as_string;
    }

    my $path = $c->lwp->request->uri->path || '/';
    $path =~ s/^\///;

    $c->req->base($base);
    $c->req->path($path);
}

=item $c->prepare_request($r)

=cut

sub prepare_request {
    my ( $c, $lwp ) = @_;
    $c->lwp($lwp);
}

=item $c->prepare_uploads

=cut

sub prepare_uploads {
    my $c = shift;
}

=item $c->run

=cut

sub run {
    my $class   = shift;
    my $request = shift || '/';

    unless ( ref $request ) {

        my $uri = ( $request =~ m/http/i )
          ? URI->new($request)
          : URI->new( 'http://localhost' . $request );

        $request = $uri->canonical;
    }

    unless ( ref $request eq 'HTTP::Request' ) {
        $request = HTTP::Request->new( 'GET', $request );
    }

    my $lwp = Catalyst::Engine::Test::LWP->new(
        address  => '127.0.0.1',
        hostname => 'localhost',
        request  => $request,
        response => HTTP::Response->new
    );

    $class->handler($lwp);

    return $lwp->response;
}

=back

=head1 SEE ALSO

L<Catalyst>.

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>
Christian Hansen, C<ch@ngmedia.com>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
