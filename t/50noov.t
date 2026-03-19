#!/usr/bin/perl

use v5.42;
use warnings;

use Test2::V0;

# Use some lexicals to avoid constfolding
my $one  = 1;
my $two  = 2;
my $four = 4;

no overloading;
use Faster::Maths::CC;


is( -$one + 0 + 0, -1, '-1+0+0 is -1' );

ok(@Faster::Maths::CC::collection, "we compiled something");

done_testing;
