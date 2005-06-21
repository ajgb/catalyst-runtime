package Catalyst;

use strict;
use base qw[ Catalyst::Base Catalyst::Setup ];
use UNIVERSAL::require;
use Catalyst::Exception;
use Catalyst::Log;
use Catalyst::Utils;
use NEXT;
use Text::ASCIITable;
use Path::Class;
our $CATALYST_SCRIPT_GEN = 4;

__PACKAGE__->mk_classdata($_) for qw/arguments dispatcher engine log/;

our $VERSION = '5.24';
our @ISA;

=head1 NAME

Catalyst - The Elegant MVC Web Application Framework

=head1 SYNOPSIS

    # use the helper to start a new application
    catalyst.pl MyApp
    cd MyApp

    # add models, views, controllers
    script/myapp_create.pl model Something
    script/myapp_create.pl view Stuff
    script/myapp_create.pl controller Yada

    # built in testserver
    script/myapp_server.pl

    # command line interface
    script/myapp_test.pl /yada


    use Catalyst;

    use Catalyst qw/My::Module My::OtherModule/;

    use Catalyst '-Debug';

    use Catalyst qw/-Debug -Engine=CGI/;

    sub default : Private { $_[1]->res->output('Hello') } );

    sub index : Path('/index.html') {
        my ( $self, $c ) = @_;
        $c->res->output('Hello');
        $c->forward('foo');
    }

    sub product : Regex('^product[_]*(\d*).html$') {
        my ( $self, $c ) = @_;
        $c->stash->{template} = 'product.tt';
        $c->stash->{product} = $c->req->snippets->[0];
    }

See also L<Catalyst::Manual::Intro>

=head1 DESCRIPTION

The key concept of Catalyst is DRY (Don't Repeat Yourself).

See L<Catalyst::Manual> for more documentation.

Catalyst plugins can be loaded by naming them as arguments to the "use Catalyst" statement.
Omit the C<Catalyst::Plugin::> prefix from the plugin name,
so C<Catalyst::Plugin::My::Module> becomes C<My::Module>.

    use Catalyst 'My::Module';

Special flags like -Debug and -Engine can also be specifed as arguments when
Catalyst is loaded:

    use Catalyst qw/-Debug My::Module/;

The position of plugins and flags in the chain is important, because they are
loaded in exactly the order that they appear.

The following flags are supported:

=over 4

=item -Debug

enables debug output, i.e.:

    use Catalyst '-Debug';

this is equivalent to:

    use Catalyst;
    sub debug { 1 }

=item -Engine

Force Catalyst to use a specific engine.
Omit the C<Catalyst::Engine::> prefix of the engine name, i.e.:

    use Catalyst '-Engine=CGI';

=back

=head1 METHODS

=over 4

=item debug

Overload to enable debug messages.

=cut

sub debug { 0 }

=item config

Returns a hashref containing your applications settings.

=cut

sub import {
    my ( $class, @arguments ) = @_;
    
    my $caller = caller(0);
    
    if ( $caller eq 'main' ) {
        return;
    }

    # Prepare inheritance
    unless ( $caller->isa($class) ) {
        no strict 'refs';
        push @{"$caller\::ISA"}, $class;
    }
    
    if ( $caller->engine ) {
        $caller->log->warn( qq/Attempt to re-initialize "$caller"/ );
        return;
    }

    # Process options
    my $flags = { };

    foreach (@arguments) {

        if ( /^-Debug$/ ) {
            $flags->{log} = ( $flags->{log} ) ? 'debug,' . $flags->{log} : 'debug';
        }
        elsif (/^-(\w+)=?(.*)$/) {
            $flags->{ lc $1 } = $2;
        }
        else {
            push @{ $flags->{plugins} }, $_;
        }
    }

    $caller->setup_log        ( delete $flags->{log}        );
    $caller->setup_plugins    ( delete $flags->{plugins}    );
    $caller->setup_dispatcher ( delete $flags->{dispatcher} );
    $caller->setup_engine     ( delete $flags->{engine}     );
    $caller->setup_home       ( delete $flags->{home}       );

    for my $flag ( sort keys %{ $flags } ) {

        if ( my $code = $caller->can( 'setup_' . $flag ) ) {
            &$code( $caller, delete $flags->{$flag} );
        }
        else {
            $caller->log->warn(qq/Unknown flag "$flag"/);
        }
    }

    $caller->log->warn( "You are running an old helper script! "
          . "Please update your scripts by regenerating the "
          . "application and copying over the new scripts." )
      if ( $ENV{CATALYST_SCRIPT_GEN}
        && ( $ENV{CATALYST_SCRIPT_GEN} < $CATALYST_SCRIPT_GEN ) );


    if ( $caller->debug ) {

        my @plugins = ();

        {
            no strict 'refs';
            @plugins = grep { /^Catalyst::Plugin/ } @{"$caller\::ISA"};
        }

        if ( @plugins ) {
            my $t = Text::ASCIITable->new;
            $t->setOptions( 'hide_HeadRow',  1 );
            $t->setOptions( 'hide_HeadLine', 1 );
            $t->setCols('Class');
            $t->setColWidth( 'Class', 75, 1 );
            $t->addRow($_) for @plugins;
            $caller->log->debug( "Loaded plugins:\n" . $t->draw );
        }

        my $dispatcher = $caller->dispatcher;
        my $engine     = $caller->engine;
        my $home       = $caller->config->{home};

        $caller->log->debug(qq/Loaded dispatcher "$dispatcher"/);
        $caller->log->debug(qq/Loaded engine "$engine"/);

        $home
          ? ( -d $home )
          ? $caller->log->debug(qq/Found home "$home"/)
          : $caller->log->debug(qq/Home "$home" doesn't exist/)
          : $caller->log->debug(q/Couldn't find home/);
    }
}

=item $c->engine

Contains the engine class.

=item $c->log

Contains the logging object.  Unless it is already set Catalyst sets this up with a
C<Catalyst::Log> object.  To use your own log class:

    $c->log( MyLogger->new );
    $c->log->info("now logging with my own logger!");

Your log class should implement the methods described in the C<Catalyst::Log>
man page.

=item $c->plugin( $name, $class, @args )

Instant plugins for Catalyst.
Classdata accessor/mutator will be created, class loaded and instantiated.

    MyApp->plugin( 'prototype', 'HTML::Prototype' );

    $c->prototype->define_javascript_functions;

=cut

sub plugin {
    my ( $class, $name, $plugin, @args ) = @_;
    $plugin->require;

    if ( my $error = $UNIVERSAL::require::ERROR ) {
        Catalyst::Exception->throw(
            message => qq/Couldn't load instant plugin "$plugin", "$error"/
        );
    }

    eval { $plugin->import };
    $class->mk_classdata($name);
    my $obj;
    eval { $obj = $plugin->new(@args) };

    if ( $@ ) {
        Catalyst::Exception->throw(
            message => qq/Couldn't instantiate instant plugin "$plugin", "$@"/
        );
    }

    $class->$name($obj);
    $class->log->debug(qq/Initialized instant plugin "$plugin" as "$name"/)
      if $class->debug;
}

=item $class->setup

Setup.

    MyApp->setup;

=cut

sub setup {
    my $class = shift;
    
    # Call plugins setup
    $class->NEXT::setup;

    # Initialize our data structure
    $class->components( {} );

    $class->setup_components;

    if ( $class->debug ) {
        my $t = Text::ASCIITable->new;
        $t->setOptions( 'hide_HeadRow',  1 );
        $t->setOptions( 'hide_HeadLine', 1 );
        $t->setCols('Class');
        $t->setColWidth( 'Class', 75, 1 );
        $t->addRow($_) for sort keys %{ $class->components };
        $class->log->debug( "Loaded components:\n" . $t->draw )
          if ( @{ $t->{tbl_rows} } );
    }

    # Add our self to components, since we are also a component
    $class->components->{$class} = $class;

    $class->setup_actions;

    if ( $class->debug ) {
        my $name = $class->config->{name} || 'Application';
        $class->log->info("$name powered by Catalyst $Catalyst::VERSION");
    }
}

=back

=head1 LIMITATIONS

mod_perl2 support is considered experimental and may contain bugs.

=head1 SUPPORT

IRC:

    Join #catalyst on irc.perl.org.

Mailing-Lists:

    http://lists.rawmode.org/mailman/listinfo/catalyst
    http://lists.rawmode.org/mailman/listinfo/catalyst-dev

Web:

    http://catalyst.perl.org

=head1 SEE ALSO

=over 4

=item L<Catalyst::Manual> - The Catalyst Manual

=item L<Catalyst::Engine> - Core Engine

=item L<Catalyst::Log> - The Log Class.

=item L<Catalyst::Request> - The Request Object

=item L<Catalyst::Response> - The Response Object

=item L<Catalyst::Test> - The test suite.

=back

=head1 AUTHOR

Sebastian Riedel, C<sri@oook.de>

=head1 THANK YOU

Andy Grundman, Andrew Ford, Andrew Ruthven, Autrijus Tang, Christian Hansen,
Christopher Hicks, Dan Sully, Danijel Milicevic, David Naughton,
Gary Ashton Jones, Geoff Richards, Jesse Sheidlower, Jody Belka,
Johan Lindstrom, Juan Camacho, Leon Brocard, Marcus Ramberg,
Tatsuhiko Miyagawa and all the others who've helped.

=head1 LICENSE

This library is free software . You can redistribute it and/or modify it under
the same terms as perl itself.

=cut

1;
