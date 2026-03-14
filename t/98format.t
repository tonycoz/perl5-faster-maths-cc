#!perl
use Test2::V0;
use List::Util "min";
use Config;

skip_all("Author test")
  unless $ENV{AUTHOR_TESTING} && $ENV{AUTHOR_TESTING} eq "tonyc";

my @formatters =
  (
  ( map "clang-format-$_", qw(23 22 21 20 19) ),
  "clang-format"
  );

if ($ENV{CLANG_FORMAT}) {
    @formatters = split /\Q$Config{path_sep}/, $ENV{CLANG_FORMAT};
}

# look for the formatter
my $formatter;

my $out;
for my $candidate (@formatters) {
  if (open my $ffh, "-|", $candidate, "docc.cpp") {
    
    $out = do { local $/; <$ffh> };
    if (close($ffh) && $? == 0) {
      $formatter = $candidate;
      last;
    }
  }
}
skip_all "No formatter"
  unless $out;

open my $srcfh, "<", "docc.cpp"
  or skip_all "Cannot open docc.cpp: $!";
my $src = do { local $/; <$srcfh> };
$src =~ tr/\r//d;

# is() too verbose
unless (ok($src eq $out, "docc.cpp properly formatted")) {
    my @src_lines = split /\n/, $src, -1;
    my @exp_lines = split /\n/, $out, -1;
    my $check_limit = min(scalar @src_lines, scalar @exp_lines);
    my $lineno = 1;
    while ($lineno <= $check_limit) {
        my $src_line = shift @src_lines;
        my $exp_line = shift @exp_lines;
        if ($src_line ne $exp_line) {
            diag <<EOS;
First mismatch:
  Line: $lineno
  Source: $src_line
  Expect: $exp_line
EOS
            last;
        }
        ++$lineno;
    }
    if ($lineno > $check_limit) {
        if (@src_lines > @exp_lines) {
            diag "Source longer than expected";
        }
        else {
            diag "Expected longer than source";
        }
    }
}

done_testing();
