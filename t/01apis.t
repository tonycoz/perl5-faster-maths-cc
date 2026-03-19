#!perl
# Test we can compile the API code
# While this is checked when testing the generated code
# that produces a lot of irrelevant noise, so add a separate test.
#
# This can be run separately without building the FMC module itself.
use strict;
use warnings;
use Test2::V0;
use v5.40;
require blib;
use Devel::PPPort;
use Cwd qw(getcwd);

# part one: build the module
my $start_dir = getcwd();
my $build_dir = "$start_dir/t/apitest";

unless (-d "$build_dir/ppport.h") {
  Devel::PPPort::WriteFile("t/apitest/ppport.h");
}

my $build_outfile = "$build_dir/build.txt";
my $makefile = "$build_dir/Makefile";
my $makefile_pl = "$build_dir/Makefile.PL";
my $good = eval {
  chdir $build_dir
    or die "Cannot chdir to $build_dir: $!";
  if (!-e $makefile || -M $makefile > -M $makefile_pl) {
    system "$^X Makefile.PL >$build_outfile 2>&1"
      and die "Cannot Makefile.PL: $?";
  }
  system "make >>$build_outfile 2>&1"
    and die "Cannot make: $?";
  system "make test >>$build_outfile 2>&1"
    and die "Cannot make test: $?";
  1;
};
my $err = $@;
chdir $start_dir
  or die "Cannot chdir back to $start_dir: $!";

ok($good, "successfully built")
  or diag $err;
unless ($good) {
  open my $fh, "<", $build_outfile
    or die "Cannot open $build_outfile: $!";
  while (<$fh>) {
    chomp;
    diag $_;
  }
}

done_testing;

sub save_file($name, $content) {
  open my $fh, ">", $name
    or die "Cannot create $name: $!";
  print $fh $content;
  close $fh
    or die "Cannot close $name; $!";
}

# sub note {
#   my $out = join "", @_;
#   $out =~ s/^/# /gm;
#   $out .= "\n" unless $out =~ /\n\z/;
#   print $out;
# }

# sub diag {
#   my $out = join "", @_;
#   $out =~ s/^/# /gm;
#   $out .= "\n" unless $out =~ /\n\z/;
#   print STDERR $out;
# }

# my $test_num;
# sub ok ($ok, $name) {
#   ++$test_num;
#   print "not " unless $ok;
#   print "ok $test_num $name\n";
#   $ok;
# }

# sub done_testing() {
#   print "1..$test_num\n";
# }

# sub BAIL_OUT ($msg) {
#   ok(0, $msg);
#   done_testing();
#   exit(255);
# }

