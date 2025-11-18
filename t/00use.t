#!/usr/bin/perl

use v5.14;
use warnings;

use Test::More;

# needs to load early to be useful
BEGIN { use_ok( 'Faster::Maths::CC' ); }

done_testing;
