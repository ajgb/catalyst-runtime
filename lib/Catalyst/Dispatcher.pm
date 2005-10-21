package Catalyst::Dispatcher;

use strict;
use base 'Class::Accessor::Fast';
use Catalyst::Exception;
use Catalyst::Utils;
use Catalyst::Action;
use Catalyst::ActionContainer;
use Text::ASCIITable;
use Tree::Simple;
use Tree::Simple::Visitor::FindByPath;

# Stringify to class
use overload '""' => sub { return ref shift }, fallback => 1;

__PACKAGE__->mk_accessors(qw/actions tree/);

=head1 NAME

Catalyst::Dispatcher - The Catalyst Dispatcher

=head1 SYNOPSIS

See L<Catalyst>.

=head1 DESCRIPTION

=head1 METHODS

=over 4

=item $self->detach( $c, $command [, \@arguments ] )

=cut

sub detach {
    my ( $self, $c, $command, @args ) = @_;
    $c->forward( $command, @args ) if $command;
    die $Catalyst::DETACH;
}

=item $self->dispatch($c)

=cut

sub dispatch {
    my ( $self, $c ) = @_;
    my $action    = $c->req->action;
    my $namespace = '';
    $namespace = ( join( '/', @{ $c->req->args } ) || '/' )
      if $action eq 'default';

    unless ($namespace) {
        if ( my $result = $c->get_action($action) ) {
            $namespace =
              Catalyst::Utils::class2prefix( $result->[0]->[0]->namespace,
                $c->config->{case_sensitive} );
        }
    }

    my $default = $action eq 'default' ? $namespace : undef;
    my $results = $c->get_action( $action, $default, $default ? 1 : 0 );
    $namespace ||= '/';

    if ( @{$results} ) {

        # Errors break the normal flow and the end action is instantly run
        my $error = 0;

        # Execute last begin
        $c->state(1);
        if ( my $begin = @{ $c->get_action( 'begin', $namespace, 1 ) }[-1] ) {
            $begin->[0]->execute($c);
            $error++ if scalar @{ $c->error };
        }

        # Execute the auto chain
        my $autorun = 0;
        for my $auto ( @{ $c->get_action( 'auto', $namespace, 1 ) } ) {
            last if $error;
            $autorun++;
            $auto->[0]->execute($c);
            $error++ if scalar @{ $c->error };
            last unless $c->state;
        }

        # Execute the action or last default
        my $mkay = $autorun ? $c->state ? 1 : 0 : 1;
        if ( ( my $action = $c->req->action ) && $mkay ) {
            unless ($error) {
                if ( my $result =
                    @{ $c->get_action( $action, $default, 1 ) }[-1] )
                {
                    $result->[0]->execute($c);
                    $error++ if scalar @{ $c->error };
                }
            }
        }

        # Execute last end
        if ( my $end = @{ $c->get_action( 'end', $namespace, 1 ) }[-1] ) {
            $end->[0]->execute($c);
        }
    }

    else {
        my $path  = $c->req->path;
        my $error = $path
          ? qq/Unknown resource "$path"/
          : "No default action defined";
        $c->log->error($error) if $c->debug;
        $c->error($error);
    }
}

=item $self->forward( $c, $command [, \@arguments ] )

=cut

sub forward {
    my $self    = shift;
    my $c       = shift;
    my $command = shift;

    unless ($command) {
        $c->log->debug('Nothing to forward to') if $c->debug;
        return 0;
    }

    # Relative forwards from detach
    my $caller = ( caller(1) )[0]->isa('Catalyst::Dispatcher')
      && ( ( caller(2) )[3] =~ /::detach$/ ) ? caller(3) : caller(1);

    my $arguments = ( ref( $_[-1] ) eq 'ARRAY' ) ? pop(@_) : $c->req->args;

    my $results = [];

    my $command_copy = $command;

    unless ( $command_copy =~ s/^\/// ) {
        my $namespace =
          Catalyst::Utils::class2prefix( $caller, $c->config->{case_sensitive} ) || '';
        $command_copy = "${namespace}/${command}";
    }

    unless ( $command_copy =~ /\// ) {
        $results = $c->get_action( $command_copy, '/' );
    }
    else {
        my @extra_args;
      DESCEND: while ( $command_copy =~ s/^(.*)\/(\w+)$/$1/ ) {
            my $tail = $2;
            $results = $c->get_action( $tail, $1 );
            if ( @{$results} ) {
                $command = $tail;
                push( @{$arguments}, @extra_args );
                last DESCEND;
            }
            unshift( @extra_args, $tail );
        }
    }

    unless ( @{$results} ) {

        unless ( $c->components->{$command} ) {
            my $error =
qq/Couldn't forward to command "$command". Invalid action or component./;
            $c->error($error);
            $c->log->debug($error) if $c->debug;
            return 0;
        }

        my $class  = $command;
        my $method = shift || 'process';

        if ( my $code = $c->components->{$class}->can($method) ) {
            my $action = Catalyst::Action->new(
                {
                    code      => $code,
                    reverse   => "$class->$method",
                    namespace => $class,
                }
            );
            $results = [ [$action] ];
        }

        else {
            my $error =
              qq/Couldn't forward to "$class". Does not implement "$method"/;
            $c->error($error);
            $c->log->debug($error)
              if $c->debug;
            return 0;
        }

    }

    local $c->request->{arguments} = [ @{$arguments} ];

    for my $result ( @{$results} ) {
        $result->[0]->execute($c);
        return if scalar @{ $c->error };
        last unless $c->state;
    }

    return $c->state;
}

=item $self->prepare_action($c)

=cut

sub prepare_action {
    my ( $self, $c ) = @_;
    my $path = $c->req->path;
    my @path = split /\//, $c->req->path;
    $c->req->args( \my @args );

    while (@path) {
        $path = join '/', @path;
        if ( my $result = ${ $c->get_action($path) }[0] ) {

            # It's a regex
            if ($#$result) {
                my $match    = $result->[1];
                my @snippets = @{ $result->[2] };
                $c->log->debug(
                    qq/Requested action is "$path" and matched "$match"/)
                  if $c->debug;
                $c->log->debug(
                    'Snippets are "' . join( ' ', @snippets ) . '"' )
                  if ( $c->debug && @snippets );
                $c->req->action($match);
                $c->req->snippets( \@snippets );
            }

            else {
                $c->req->action($path);
                $c->log->debug(qq/Requested action is "$path"/) if $c->debug;
            }

            $c->req->match($path);
            last;
        }
        unshift @args, pop @path;
    }

    unless ( $c->req->action ) {
        $c->req->action('default');
        $c->req->match('');
    }

    $c->log->debug( 'Arguments are "' . join( '/', @args ) . '"' )
      if ( $c->debug && @args );
}

=item $self->get_action( $c, $action, $namespace, $inherit )

=cut

sub get_action {
    my ( $self, $c, $action, $namespace, $inherit ) = @_;
    return [] unless $action;
    $namespace ||= '';
    $inherit   ||= 0;

    if ($namespace) {

        my $parent = $self->tree;
        my @match;

        if ($namespace ne '/') {

            my $visitor = Tree::Simple::Visitor::FindByPath->new;
            my @path = split('/', $namespace);
            $visitor->setSearchPath( @path );
            $parent->accept($visitor);

            if ($inherit) {

                @match = $visitor->getResults;
                @match = ($parent) unless @match;

                if (!defined $visitor->getResult) {
                    my $extra = $path[(scalar @match) - 1];
                    last unless $extra;
                    $visitor->setSearchPath($extra);
                    $match[-1]->accept($visitor);
                    push(@match, $visitor->getResult) if defined $visitor->getResult;
                }
            } else {
                @match = ($visitor->getResult) if $visitor->getResult;
            }

        }

        @match = ($parent) unless @match;

        my @results;

        foreach my $child (@match) {
            my $node = $child->getNodeValue->actions;
            push(@results, [ $node->{$action} ]) if defined $node->{$action};
        }
        return \@results;
    }

    elsif ( my $p = $self->actions->{plain}->{$action} ) { return [ [$p] ] }
    elsif ( my $r = $self->actions->{regex}->{$action} ) { return [ [$r] ] }

    else {

        for my $i ( 0 .. $#{ $self->actions->{compiled} } ) {
            my $name  = $self->actions->{compiled}->[$i]->[0];
            my $regex = $self->actions->{compiled}->[$i]->[1];

            if ( my @snippets = ( $action =~ $regex ) ) {
                return [
                    [ $self->actions->{regex}->{$name}, $name, \@snippets ] ];
            }

        }
    }
    return [];
}

=item $self->set_action( $c, $action, $code, $namespace, $attrs )

=cut

sub set_action {
    my ( $self, $c, $method, $code, $namespace, $attrs ) = @_;

    my $prefix =
      Catalyst::Utils::class2prefix( $namespace, $c->config->{case_sensitive} )
      || '';
    my %flags;

    for my $attr ( @{$attrs} ) {
        if    ( $attr =~ /^(Local|Relative)$/ )    { $flags{local}++ }
        elsif ( $attr =~ /^(Global|Absolute)$/ )   { $flags{global}++ }
        elsif ( $attr =~ /^Path\(\s*(.+)\s*\)$/i ) {
            push @{ $flags{path} }, $1;
        }
        elsif ( $attr =~ /^Private$/i ) { $flags{private}++ }
        elsif ( $attr =~ /^(Regex|Regexp)\(\s*(.+)\s*\)$/i ) {
            push @{ $flags{regex} }, $2;
        }
    }

    if ( $flags{private} && ( keys %flags > 1 ) ) {
        $c->log->debug( 'Bad action definition "'
              . join( ' ', @{$attrs} )
              . qq/" for "$namespace->$method"/ )
          if $c->debug;
        return;
    }
    return unless keys %flags;

    my $parent  = $self->tree;
    my $visitor = Tree::Simple::Visitor::FindByPath->new;

    if ($prefix) {
        for my $part ( split '/', $prefix ) {
            $visitor->setSearchPath($part);
            $parent->accept($visitor);
            my $child = $visitor->getResult;
    
            unless ($child) {
                my $container = Catalyst::ActionContainer->new(
                                    { part => $part, actions => {} });
                $child = $parent->addChild( Tree::Simple->new($container) );
                $visitor->setSearchPath($part);
                $parent->accept($visitor);
                $child = $visitor->getResult;
            }
    
            $parent = $child;
        }
    }

    my $reverse = $prefix ? "$prefix/$method" : $method;

    my $action = Catalyst::Action->new(
        {
            code      => $code,
            reverse   => $reverse,
            namespace => $namespace,
        }
    );

    $parent->getNodeValue->actions->{$method} = $action;

    my @path;
    for my $path ( @{ $flags{path} } ) {
        $path =~ s/^\w+//;
        $path =~ s/\w+$//;
        if ( $path =~ /^\s*'(.*)'\s*$/ ) { $path = $1 }
        if ( $path =~ /^\s*"(.*)"\s*$/ ) { $path = $1 }
        push @path, $path;
    }
    $flags{path} = \@path;

    my @regex;
    for my $regex ( @{ $flags{regex} } ) {
        $regex =~ s/^\w+//;
        $regex =~ s/\w+$//;
        if ( $regex =~ /^\s*'(.*)'\s*$/ ) { $regex = $1 }
        if ( $regex =~ /^\s*"(.*)"\s*$/ ) { $regex = $1 }
        push @regex, $regex;
    }
    $flags{regex} = \@regex;

    if ( $flags{local} || $flags{global} ) {
        push( @{ $flags{path} }, $prefix ? "/$prefix/$method" : "/$method" )
          if $flags{local};

        push( @{ $flags{path} }, "/$method" ) if $flags{global};
    }

    for my $path ( @{ $flags{path} } ) {
        if ( $path =~ /^\// ) { $path =~ s/^\/// }
        else { $path = $prefix ? "$prefix/$path" : $path }
        $self->actions->{plain}->{$path} = $action;
    }

    for my $regex ( @{ $flags{regex} } ) {
        push @{ $self->actions->{compiled} }, [ $regex, qr#$regex# ];
        $self->actions->{regex}->{$regex} = $action;
    }
}

=item $self->setup_actions( $class, $component )

=cut

sub setup_actions {
    my ( $self, $class ) = @_;

    # These are the core structures
    $self->actions(
        {
            plain    => {},
            private  => {},
            regex    => {},
            compiled => []
        }
    );

    # We use a tree
    my $container = Catalyst::ActionContainer->new(
                        { part => '/', actions => {} } );
    $self->tree( Tree::Simple->new( $container, Tree::Simple->ROOT ) );

    for my $comp ( keys %{ $class->components } ) {

        # We only setup components that inherit from Catalyst::Base
        next unless $comp->isa('Catalyst::Base');

        for my $action ( @{ Catalyst::Utils::reflect_actions($comp) } ) {
            my ( $code, $attrs ) = @{$action};
            my $name = '';
            no strict 'refs';
            my @cache = ( $comp, @{"$comp\::ISA"} );
            my %namespaces;

            while ( my $namespace = shift @cache ) {
                $namespaces{$namespace}++;
                for my $isa ( @{"$comp\::ISA"} ) {
                    next if $namespaces{$isa};
                    push @cache, $isa;
                    $namespaces{$isa}++;
                }
            }

            for my $namespace ( keys %namespaces ) {

                for my $sym ( values %{ $namespace . '::' } ) {

                    if ( *{$sym}{CODE} && *{$sym}{CODE} == $code ) {

                        $name = *{$sym}{NAME};
                        $class->set_action( $name, $code, $comp, $attrs );
                        last;
                    }

                }

            }

        }

    }

    return unless $class->debug;

    my $actions  = $self->actions;
    my $privates = Text::ASCIITable->new;
    $privates->setCols( 'Private', 'Class' );
    $privates->setColWidth( 'Private', 36, 1 );
    $privates->setColWidth( 'Class',   37, 1 );

    my $walker = sub {
        my ( $walker, $parent, $prefix ) = @_;
        $prefix .= $parent->getNodeValue || '';
        $prefix .= '/' unless $prefix =~ /\/$/;
        my $node = $parent->getNodeValue->actions;

        for my $action ( keys %{ $node } ) {
            my $action_obj = $node->{$action};
            $privates->addRow( "$prefix$action", $action_obj->namespace );
        }

        $walker->( $walker, $_, $prefix ) for $parent->getAllChildren;
    };

    $walker->( $walker, $self->tree, '' );
    $class->log->debug( "Loaded private actions:\n" . $privates->draw )
      if ( @{ $privates->{tbl_rows} } );

    my $publics = Text::ASCIITable->new;
    $publics->setCols( 'Public', 'Private' );
    $publics->setColWidth( 'Public',  36, 1 );
    $publics->setColWidth( 'Private', 37, 1 );

    for my $plain ( sort keys %{ $actions->{plain} } ) {
        my $action = $actions->{plain}->{$plain};
        $publics->addRow( "/$plain", "/$action" );
    }

    $class->log->debug( "Loaded public actions:\n" . $publics->draw )
      if ( @{ $publics->{tbl_rows} } );

    my $regexes = Text::ASCIITable->new;
    $regexes->setCols( 'Regex', 'Private' );
    $regexes->setColWidth( 'Regex',   36, 1 );
    $regexes->setColWidth( 'Private', 37, 1 );

    for my $regex ( sort keys %{ $actions->{regex} } ) {
        my $action = $actions->{regex}->{$regex};
        $regexes->addRow( $regex, "/$action" );
    }

    $class->log->debug( "Loaded regex actions:\n" . $regexes->draw )
      if ( @{ $regexes->{tbl_rows} } );
}

=back

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
