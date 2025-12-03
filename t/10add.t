#!/usr/bin/perl

use v5.14;
use warnings;

# adapted from t/opbasic/arith.t

my $T = 1;

sub tryeq ($$$$) {
  my $status;
  if ($_[1] == $_[2]) {
    $status = "ok $_[0]";
  } else {
    $status = "not ok $_[0] # $_[1] != $_[2]";
  }
  print "$status - $_[3]\n";
}

my $max_iv = ~0 >> 1;
my $min_uv = (~0 >> 1) + 1;
my $min_uvp10 = $min_uv+10;
my $max_uv = ~0;
my $max_uvm1 = $max_uv - 1;
my $min_uvp1 = $min_uv + 1;
my $max_uvp1 = $max_uv + 1;
{
  use Faster::Maths::CC;
  # FMC requires 3 "math" ops to optimize
  # and doesn't re-order (A+B)+C to A+(B+C) to fold
  tryeq $T++, $max_iv + 0 + 0, $max_iv,
    'trigger wrapping on IVs and UVs';

  tryeq $T++, $max_iv + 1 + 0, $min_uv, 'IV + IV promotes to UV';
  tryeq $T++, $min_uv + 10 + 0, $min_uvp10, 'IV + IV promotes to UV';
  tryeq $T++, $max_iv + $max_iv + 0, $max_uv - 1, 'IV + IV promotes to UV';
  tryeq $T++, $max_iv + $min_uvp1 + 0, $max_uvp1, 'IV + UV promotes to NV';
  tryeq $T++, $max_uvm1 + 2 + 0, $max_uvp1, 'UV + IV promotes to NV';
  # tryeq $T++, 4294967295 + 4294967295, 8589934590, 'UV + UV promotes to NV';

  # tryeq $T++, 2147483648 + -1, 2147483647, 'UV + IV promotes to IV';
  # tryeq $T++, 2147483650 + -10, 2147483640, 'UV + IV promotes to IV';
  # tryeq $T++, -1 + 2147483648, 2147483647, 'IV + UV promotes to IV';
  # tryeq $T++, -10 + 4294967294, 4294967284, 'IV + UV promotes to IV';
  # tryeq $T++, -2147483648 + -2147483648, -4294967296, 'IV + IV promotes to NV';
  # tryeq $T++, -2147483640 + -10, -2147483650, 'IV + IV promotes to NV';
  
  # # Hmm. Do not forget the simple stuff
  # # addition
  # tryeq $T++, 1 + 1, 2, 'addition of 2 positive integers';
  # tryeq $T++, 4 + -2, 2, 'addition of positive and negative integer';
  # tryeq $T++, -10 + 100, 90, 'addition of negative and positive integer';
  # tryeq $T++, -7 + -9, -16, 'addition of 2 negative integers';
  # tryeq $T++, -63 + +2, -61, 'addition of signed negative and positive integers';
  # tryeq $T++, 4 + -1, 3, 'addition of positive and negative integer';
  # tryeq $T++, -1 + 1, 0, 'addition which sums to 0';
  # tryeq $T++, +29 + -29, 0, 'addition which sums to 0';
  # tryeq $T++, -1 + 4, 3, 'addition of signed negative and positive integers';
  # tryeq $T++, +4 + -17, -13, 'addition of signed positive and negative integers';
}

print "1..", $T-1, "\n";
