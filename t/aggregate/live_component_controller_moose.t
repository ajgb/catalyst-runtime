use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";

use Test::More tests => 4;
use Catalyst::Test 'TestApp';

{
    my $response = request('http://localhost/moose/get_attribute');
    ok($response->is_success);
    is($response->content, '42', 'attribute default values get set correctly');
}

{
    my $response = request('http://localhost/moose/methodmodifiers/get_attribute');
    ok($response->is_success);
    is($response->header('X-Catalyst-Test-After'), 'after called', 'after works as expected');
}
