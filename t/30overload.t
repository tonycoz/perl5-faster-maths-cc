#!/usr/bin/perl

use v5.40;

use Test::More;

use Math::BigFloat;

{
  my $one  = Bodmas->new(1);
  my $two  = Bodmas->new(2);
  my $four = Bodmas->new(4);

  use Faster::Maths::CC;
  # test overloading handled correctly

  my $r = $one + $two + $four;
  is($r, "((1 + 2) + 4)", '1+2+4 is 7' );
  isa_ok($r, "Bodmas");

  $r = $four - $two - $one;
  is($r, "((4 - 2) - 1)", '4-2-1 is 1' );
  isa_ok($r, "Bodmas");

  is( $one * $four * $two, "((1 * 4) * 2)", '1*4*2 is 8' );

  is( $two * $four + $one, "((2 * 4) + 1)", '2*4+1 is 9' );
  is( $two * ( $four + $one ), "(2 * (4 + 1))", '2*(4+1) is 10' );
  is( - ($one + $two + $four), '(- ((1 + 2) + 4))', '-(1+2+4) is -7' );
}
{
  my $one  = Math::BigFloat->new(1);
  my $two  = Math::BigFloat->new(2);
  my $four = Math::BigFloat->new(4);

  use Faster::Maths::CC;
  # test overloading handled correctly
  # Use some lexicals to avoid constfolding
  my $r = $one + $two + $four;
  is($r, 7, '1+2+4 is 7' );
  isa_ok($r, "Math::BigFloat");

  my $r2 = $four - $two - $one;
  is($r2, 1, '4-2-1 is 1' );
  isa_ok($r, "Math::BigFloat");

  is( $one * $four * $two, 8, '1*4*2 is 8' );

  is( $two * $four + $one, 9, '2*4+1 is 9' );
  is( $two * ( $four + $one ), 10, '2*(4+1) is 10' );
  is( - ($one + $two + $four), -7, '-(1+2+4) is -7' );
}

ok(@Faster::Maths::CC::collection, "we compiled something");

done_testing;

no Faster::Maths::CC;

package Bodmas {
  sub wrap($op, $left, $right, $swap) {
    $right = __PACKAGE__->new($right) unless ref $right;
    ($left, $right) = ($right, $left) if $swap;
    return __PACKAGE__->new("($left->[0] $op $right->[0])");
  }
  use overload
    fallback => 1,
    '+' => sub { wrap("+", @_) },
    '-' => sub { wrap("-", @_) },
    '*' => sub { wrap("*", @_) },
    '/' => sub { wrap("/", @_) },
    'neg' => sub($arg, @) {
      __PACKAGE__->new("(- $arg->[0])")
    },
    '""' => sub { $_[0][0] };
  sub new ($class, $value) {
    bless [ $value ], $class;
  }
}
