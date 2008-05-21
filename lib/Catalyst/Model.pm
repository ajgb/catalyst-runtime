package Catalyst::Model;

use MRO::Compat;
use mro 'c3';
use Moose;
extends qw/Catalyst::Component/;

no Moose;

#We can't immutablize anything that ISA Component just yet
#__PACKAGE__->meta->make_immutable();

=head1 NAME

Catalyst::Model - Catalyst Model base class

=head1 SYNOPSIS

See L<Catalyst>.

=head1 DESCRIPTION

Catalyst Model base class.

=head1 METHODS

Implements the same methods as other Catalyst components, see
L<Catalyst::Component>

=head1 AUTHOR

Sebastian Riedel, C<sri@oook.de>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
