#!/usr/bin/perl

use v5.40;
use warnings;

use Test::More;

use Math::BigFloat;

{
  use Faster::Maths::CC;
  # test overloading handled correctly
  # Use some lexicals to avoid constfolding
  my $one  = Bodmas->new(1);
  my $__dummy1; # to defeat OP_PADRANGE
  my $two  = Bodmas->new(2);
  my $__dummy2;
  my $four = Bodmas->new(4);

  my $r = $one + $two + $four;
  is($r, "((1 + 2) + 4)", '1+2+4 is 7' );
  isa_ok($r, "Bodmas");

  $r = $four - $two - $one;
  is($r, "((4 - 2) - 1)", '4-2-1 is 1' );
  isa_ok($r, "Bodmas");

  is( $one * $four * $two, "((1 * 4) * 2)", '1*4*2 is 8' );

  is( $two * $four + $one, "((2 * 4) + 1)", '2*4+1 is 9' );
  is( $two * ( $four + $one ), "(2 * (4 + 1))", '2*(4+1) is 10' );
}
{
  use Faster::Maths::CC;
  # test overloading handled correctly
  # Use some lexicals to avoid constfolding
  my $one  = Math::BigFloat->new(1);
  my $__dummy1; # to defeat OP_PADRANGE
  my $two  = Math::BigFloat->new(2);
  my $__dummy2;
  my $four = Math::BigFloat->new(4);

  my $r = $one + $two + $four;
  is($r, 7, '1+2+4 is 7' );
  isa_ok($r, "Math::BigFloat");

  my $r2 = $four - $two - $one;
  is($r2, 1, '4-2-1 is 1' );
  isa_ok($r, "Math::BigFloat");

  is( $one * $four * $two, 8, '1*4*2 is 8' );

  is( $two * $four + $one, 9, '2*4+1 is 9' );
  is( $two * ( $four + $one ), 10, '2*(4+1) is 10' );
}

ok(@Faster::Maths::CC::collection, "we compiled something");

done_testing;

no Faster::Maths::CC;

package Bodmas {
  sub wrap($op, $left, $right, $swap) {
    ($left, $right) = ($right, $left) if $swap;
    return __PACKAGE__->new("($left->[0] $op $right->[0])");
  }
  use overload
    fallback => 1,
    '+' => sub { wrap("+", @_) },
    '-' => sub { wrap("-", @_) },
    '*' => sub { wrap("*", @_) },
    '/' => sub { wrap("/", @_) },
    '""' => sub { $_[0][0] };
  sub new {
    bless [ $_[1] ], $_[0];
  }
}
