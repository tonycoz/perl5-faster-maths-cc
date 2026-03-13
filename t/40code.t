#!perl
use strict;
use warnings;
use Test2::V0;
use File::Temp;
use v5.40;
require constant;
use Scalar::Util qw(dualvar);

my $all = \@Faster::Maths::CC::collection; # suppress used once

BEGIN {
    my $x = 4;
    my $ignored = sin($x); # adds NV
    constant->import(IVandNV => $x);

    my $pv = "23";
    $ignored = $pv + 1;
    constant->import(IVandPV => $pv);
}

sub code_like;

my ($x, $y, $z);

sub f1 {
  use Faster::Maths::CC;
  my $f1;
  $f1 = $x * $y * $y;
}

{
  my $code = code(qr/\$f1/);
  # should only be one load of $y;
  my @matches = grep m(/\* \$y \*/), split /\n/, $code;
  is @matches, 1, "only one \$y lookup"
    or diag $code;
}

sub f_nv {
  use Faster::Maths::CC;
  my $f_nv;
  $f_nv = $x * $y * $y + 1.0;
}

code_like(qr/\$f_nv/, qr(/\* NV 1 \*/), "sv_summary NV");

sub f3 {
  use Faster::Maths::CC;
  my $f3;
  $f3 = $x * $y * $y + 3;
}

code_like(qr/\$f3/, qr(/\* IV 3 \*/), "sv_summary IV");

sub f4 {
  use Faster::Maths::CC;
  my $f4;
  $f4 = $x * $y * $y + IVandNV;
}

code_like(qr/\$f4/, qr(/\* IV 4 NV 4 \*/), "sv_summary IV/NV");

use constant und => undef;
sub f_undef {
  use Faster::Maths::CC;
  my $f_und;
  $f_und = $x * $y * $y + und;
}

code_like(qr/\$f_und/, qr(/\* undef \*/), "sv_summary undef");

sub f_pv {
  use Faster::Maths::CC;
  my $f_pv;
  $f_pv = $x * $y * $y + "23.1";
}

code_like(qr/\$f_pv/, qr(/\* PV "23.1" \*/), "sv_summary PV");

use constant ref_const => \22.1;
sub f_ref {
  use Faster::Maths::CC;
  my $f_ref;
  $f_ref = $x * $y * $y + ref_const;
}

code_like(qr/\$f_ref/, qr(/\* REF NV 22.1 \*/), "sv_summary ref");

use constant dual_const => dualvar(23.1, "abc");
sub f_dual {
  use Faster::Maths::CC;
  my $f_dual;
  $f_dual = $x * $y * $y + dual_const;
}

code_like(qr/\$f_dual/, qr(/\* NV 23.1 PV "abc" \*/), "sv_summary dual");

done_testing();

sub code ($re) {
  my @found = grep $_->[0] =~ /$re/, @$all;

  if (@found > 1) {
    dump_code();
    die "More than one code found for $re\n",
      join "\n", map "$_->[3]: $_->[2]", @found;
  }
  elsif (!@found) {
    dump_code();
    die "No code found for $re";
  }
  return $found[0][0];
}

sub code_like ($code_match, $expect, $name) {
    my $code = code($code_match);
    return like($code, $expect, $name);
}

sub dump_code {
  for my $code (@$all) {
    print STDERR "\n\n** $code->[3]: $code->[2] **\n";
    print STDERR "  $_\n" for split /\n/, $code->[0];
  }
}
