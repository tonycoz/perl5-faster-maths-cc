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

# "constants" to prevent constant folding
my $max_iv = ~0 >> 1;
my $min_uv = (~0 >> 1) + 1;
my $min_uvp10 = $min_uv+10;
my $max_uv = ~0;
my $max_uvm1 = $max_uv - 1;
my $min_uvp1 = $min_uv + 1;
my $max_uvp1 = $max_uv + 1;
my $min_iv = -$max_iv - 1;
my $mmax_iv = - $max_iv;
my $three = 3;
my $mthree = -3;
my $five = 5;
my $mfive = -5;
my $fifteen = 15;
my $one = 1;
my $mtwo = -2;
my $xffff = 0xFFFF;
my $mxffff = -$xffff;
my $x10001 = 0x10001;
my $mx10001 = -$x10001;
{
  use Faster::Maths::CC;
  # FMC requires 3 "math" ops to optimize
  # and doesn't re-order (A+B)+C to A+(B+C) to fold
  # so in many cases I added a "+0" to get the third op
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

  # subtraction
  tryeq $T++, $three - 1 + 0, 2, 'subtraction of two positive integers';
  tryeq $T++, $three - 15, -12,
    'subtraction of two positive integers: minuend smaller';
  tryeq $T++, $three - -7 + 0, 10, 'subtraction of positive and negative integer';
  tryeq $T++, -156 - $five + 0, -161, 'subtraction of negative and positive integer';
  tryeq $T++, -156 - $mfive + 0, -151, 'subtraction of two negative integers';
  tryeq $T++, -156 - -$five + 0, -151, 'subtraction of two negative integers';
#  tryeq $T++, $mfive - -12 + 0, 7,
#    'subtraction of two negative integers: minuend smaller';
#  tryeq $T++, $mthree - -$three + 0, 0, 'subtraction of two negative integers with result of 0';
#tryeq $T++, $fifteen - 15 + 0, 0, 'subtraction of two positive integers with result of 0';
#tryeq $T++, $max_iv - 0 + 0, $max_iv, 'subtraction from large integer';
#tryeq $T++, $min_uv - 0 + 0, $min_uv, 'subtraction from large integer';
#tryeq $T++, $min_iv - 0 + 0, $min_iv,
#    'subtraction from large negative integer';
#tryeq $T++, 0 - $mmax_iv + 0, $max_iv,
#    'subtraction of large negative integer from 0';
# tryeq $T++, -1 - -2147483648, 2147483647,
#     'subtraction of large negative integer from negative integer';
# tryeq $T++, 2 - -2147483648, 2147483650,
#     'subtraction of large negative integer from positive integer';
# tryeq $T++, 4294967294 - 3, 4294967291, 'subtraction from large integer';
# tryeq $T++, -2147483648 - -1, -2147483647,
#     'subtraction from large negative integer';
# tryeq $T++, 2147483647 - -1, 2147483648, 'IV - IV promote to UV';
# tryeq $T++, 2147483647 - -2147483648, 4294967295, 'IV - IV promote to UV';
# tryeq $T++, 4294967294 - -3, 4294967297, 'UV - IV promote to NV';
# tryeq $T++, -2147483648 - +1, -2147483649, 'IV - IV promote to NV';
# tryeq $T++, 2147483648 - 2147483650, -2, 'UV - UV promote to IV';
# tryeq $T++, 2000000000 - 4000000000, -2000000000, 'IV - UV promote to IV';

  # multiplication
  tryeq $T++, $one * 3 + 0, 3, 'multiplication of two positive integers';
  tryeq $T++, $mtwo * 3 + 0, -6, 'multiplication of negative and positive integer';
  tryeq $T++, $three * -3, -9, 'multiplication of positive and negative integer';
  tryeq $T++, -4 * $mthree + 0, 12, 'multiplication of two negative integers';

  # check with 0xFFFF and 0xFFFF
  tryeq $T++, $xffff * $xffff + 0, 4294836225,
    'multiplication: 0xFFFF and 0xFFFF: pos pos';
tryeq $T++, $xffff * -65535 + 0, -4294836225,
    'multiplication: 0xFFFF and 0xFFFF: pos neg';
tryeq $T++, $mxffff * 65535 + 0, -4294836225,
    'multiplication: 0xFFFF and 0xFFFF: pos neg';
tryeq $T++, $mxffff  * $mxffff, 4294836225,
    'multiplication: 0xFFFF and 0xFFFF: neg neg';

# check with 0xFFFF and 0x10001
tryeq $T++, $xffff * $x10001 + 0, 4294967295,
    'multiplication: 0xFFFF and 0x10001: pos pos';
tryeq $T++, $xffff * $mx10001+0, -4294967295,
    'multiplication: 0xFFFF and 0x10001: pos neg';
tryeq $T++, $mxffff * $x10001+0, -4294967295,
    'multiplication: 0xFFFF and 0x10001: neg pos';
tryeq $T++, $mxffff * $mx10001+0, 4294967295,
    'multiplication: 0xFFFF and 0x10001: neg neg';

# check with 0x10001 and 0xFFFF
tryeq $T++, $x10001 * $xffff + 0, 4294967295,
    'multiplication: 0x10001 and 0xFFFF: pos pos';
tryeq $T++, $x10001 * $mxffff + 0, -4294967295,
    'multiplication: 0x10001 and 0xFFFF: pos neg';
tryeq $T++, $mx10001 * $xffff + 0, -4294967295,
    'multiplication: 0x10001 and 0xFFFF: neg pos';
tryeq $T++, $mx10001 * $mxffff + 0, 4294967295,
    'multiplication: 0x10001 and 0xFFFF: neg neg';

# # These should all be dones as NVs
# tryeq $T++, 65537 * 65537, 4295098369, 'multiplication: NV: pos pos';
# tryeq $T++, 65537 * -65537, -4295098369, 'multiplication: NV: pos neg';
# tryeq $T++, -65537 * 65537, -4295098369, 'multiplication: NV: neg pos';
# tryeq $T++, -65537 * -65537, 4295098369, 'multiplication: NV: neg neg';

# # will overflow an IV (in 32-bit)
# tryeq $T++, 46340 * 46342, 0x80001218,
#     'multiplication: overflow an IV in 32-bit: pos pos';
# tryeq $T++, 46340 * -46342, -0x80001218,
#     'multiplication: overflow an IV in 32-bit: pos neg';
# tryeq $T++, -46340 * 46342, -0x80001218,
#     'multiplication: overflow an IV in 32-bit: neg pos';
# tryeq $T++, -46340 * -46342, 0x80001218,
#     'multiplication: overflow an IV in 32-bit: neg neg';

# tryeq $T++, 46342 * 46340, 0x80001218,
#     'multiplication: overflow an IV in 32-bit: pos pos';
# tryeq $T++, 46342 * -46340, -0x80001218,
#     'multiplication: overflow an IV in 32-bit: pos neg';
# tryeq $T++, -46342 * 46340, -0x80001218,
#     'multiplication: overflow an IV in 32-bit: neg pos';
# tryeq $T++, -46342 * -46340, 0x80001218,
#     'multiplication: overflow an IV in 32-bit: neg neg';

# # will overflow a positive IV (in 32-bit)
# tryeq $T++, 65536 * 32768, 0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: pos pos';
# tryeq $T++, 65536 * -32768, -0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: pos neg';
# tryeq $T++, -65536 * 32768, -0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: neg pos';
# tryeq $T++, -65536 * -32768, 0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: neg neg';

# tryeq $T++, 32768 * 65536, 0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: pos pos';
# tryeq $T++, 32768 * -65536, -0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: pos neg';
# tryeq $T++, -32768 * 65536, -0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: neg pos';
# tryeq $T++, -32768 * -65536, 0x80000000,
#     'multiplication: overflow a positive IV in 32-bit: neg neg';

# # 2147483647 is prime. bah.

# tryeq $T++, 46339 * 46341, 0x7ffea80f,
#     'multiplication: hex product: pos pos';
# tryeq $T++, 46339 * -46341, -0x7ffea80f,
#     'multiplication: hex product: pos neg';
# tryeq $T++, -46339 * 46341, -0x7ffea80f,
#     'multiplication: hex product: neg pos';
# tryeq $T++, -46339 * -46341, 0x7ffea80f,
#     'multiplication: hex product: neg neg';

}

print "1..", $T-1, "\n";
