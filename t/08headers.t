package TestApp;

use Catalyst qw[-Engine=Test];

sub foo : Global {
  my ( $self, $c ) = @_;
  $c->res->headers->header( 'X-Foo' => 'Bar' );
}

__PACKAGE__->setup;

package main;

use Test::More tests => 1;
use Catalyst::Test 'TestApp';

ok( request('/foo')->header('X-Foo') );
