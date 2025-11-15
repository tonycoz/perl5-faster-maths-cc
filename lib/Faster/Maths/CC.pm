#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
# Mangled based on :
#  (C) Paul Evans, 2021 -- leonerd@leonerd.org.uk

package Faster::Maths::CC 0.001;

use v5.22;
use warnings;

require XSLoader;
XSLoader::load( __PACKAGE__);

{
  our %code;
  my $accum;
  while (<DATA>) {
    if (/^END (\S+)/) {
      $code{$1} = $accum;
      $accum = "";
    }
    else {
      $accum .= $_;
    }
  }
  $accum =~ /\S/
    and die "Unterminated code:\n$accum\n ";
}

sub import
{
   $^H{"Faster::Maths::CC/faster"} = 1;
}

sub unimport
{
   $^H{"Faster::Maths::CC/faster"} = 0;
}

=head1 NAME

Faster::Maths::CC - make mathematically-intense programs faster

=head1 SYNOPSIS

   use Faster::Maths::CC;

   # and that's it :)

=head1 DESCRIPTION

This module attempts to compile some perl code into C code, ideally to
make it faster.

=head2 BUGS

=over 2

=item *

Currently writes generated code to STDOUT mixed with debug data

=back

=head1 TODO

=over

=item *

Implementation

=back

=cut

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

__DATA__
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h" /* may not need this */
END preamble

