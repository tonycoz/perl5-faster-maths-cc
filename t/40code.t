#!perl
use strict;
use warnings;
use Test2::V0;
use File::Temp;
use v5.40;

my ($x, $y, $z);

sub f1 {
  use Faster::Maths::CC;
  my $f1;
  $f1 = $x * $y * $y;
}

{
  my $code = code(qr/\$f1/);
  # should only be one load of $y;
  my @matches = grep /\$y/, split /\n/, $code;
  is @matches, 1, "only one \$y lookup"
    or diag $code;
}


done_testing();

sub code ($re) {
  my $x = \@Faster::Maths::CC::collection; # suppress used once
  my @found = grep $_-[0] =~ /$re/, @Faster::Maths::CC::collection;

  if (@found > 1) {
    die "More than one code found for $re\n",
      join "\n", map "$_->[3]: $_->[2]", @found;
  }
  elsif (!@found) {
    die "No code foud for $re";
  }
  return $found[0][0];
}
