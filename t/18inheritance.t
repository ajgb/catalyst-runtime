package TestApp;

use Catalyst qw[-Engine=Test];

__PACKAGE__->action(

    '!begin' => sub {
        my ( $self, $c ) = @_;
        $c->res->headers->content_type('text/plain');
    }
);

package TestApp::C::Foo;

TestApp->action(

    '!begin' => sub {
        my ( $self, $c ) = @_;
        $c->res->output('foo');
    },

    '!default' => sub {
        my ( $self, $c ) = @_;
        $c->res->output( $c->res->output . 'foo' );
    },

    '!end' => sub {
        my ( $self, $c ) = @_;
        $c->res->output( $c->res->output . 'foo' );
    },
);

package TestApp::C::Foo::Bar;

TestApp->action(

    '!begin' => sub {
        my ( $self, $c ) = @_;
        $c->res->output( $c->res->output . 'bar' );
    },

    '!default' => sub {
        my ( $self, $c ) = @_;
        $c->res->output( $c->res->output . 'bar' );
    },

    '!end' => sub {
        my ( $self, $c ) = @_;
        $c->res->output( $c->res->output . 'bar' );
    },
);

package main;

use Test::More tests => 5;
use Catalyst::Test 'TestApp';

{
    my $response = request('/foo');
    is( $response->content, 'foofoofoo' );
}

{
    my $response = request('/foo/rab');
    is( $response->content, 'foofoofoo' );
}

{
    my $response = request('/foo/bar');
    is( $response->content, 'foobarfoobarfoobar' );
}

{
    my $response = request('/foobar');
    isnt( $response->content, 'foofoofoo' );
}

{
    my $response = request('/foo_bar/yada');
    isnt( $response->content, 'foobarfoobarfoobar' );
}
