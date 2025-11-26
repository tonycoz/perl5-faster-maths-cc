#!perl
# Test we can compile the API code
# While this is checked when testing the generated code
# that produces a lot of irrelevant noise, so add a separate test.
#
# This can be run separately without building the FMC module itself.
use strict;
use warnings;
#use Test2::V0;
use File::Temp;
use v5.40;
require blib;
use Devel::PPPort;
use Cwd qw(getcwd);

sub note; # debugger breaks deep in Test2
sub ok;
sub diag;
sub done_testing;

open my $fh, "<", "lib/Faster/Maths/CC.pm"
  or die "Cannot open CC.pm: $!";

my $version;

while (<$fh>) {
  /^package Faster::Maths::CC\s+([\d.v]+);/ and $version = $1;
  last if /API START/;
}

$version or die "No our \$VERSION ... seen in CC.pm";

$_ or die "Couldn't find \"API START\" in CC.pm";

my $api_lines;
my @apis;
my $in_api;
my @api_args;
my $api_name;
while (<$fh>) {
  last if /API END/;
  $api_lines .=  $_;
  if (/^(?:static|PERL_STATIC_INLINE)\s+(.*)$/) {
    die "Unexpected ^static in API definition" if $in_api;
    push @apis, "$1\n";
    note $1;
    @api_args = ();
    undef $api_name;
    ++$in_api;
  }
  elsif ($in_api) {
    if (/^(\w+)\(/) {
      $api_name and die "Extra API name $1 found (already saw $api_name)";
      $api_name = $1;
    }
    s/pTHX_ //;
    my $at_end = s/\{//;
    my $args_only = $_ =~ s/\)\s*$//r;
    for my $arg (split /,/, $args_only) {
      $arg =~ /(\w+)$/
        or die "Failed to parse argument name from $arg";
      push @api_args, $1;
    }
    $apis[-1] .= $_;
    if ($at_end) {
      my $args = join ", ", @api_args;
      $in_api = 0;
      $apis[-1] .= <<"EOS";
CODE:
    $api_name(aTHX_ $args);
EOS
    }

    note $_;
  }
}

my $cleanup = !$ENV{PERL_FMC_KEEP};
my $build_dir = File::Temp->newdir(CLEANUP => $cleanup);
diag "build directory $build_dir" unless $cleanup;

my $xs = <<'EOS';
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

EOS

$xs .= $api_lines;

$xs .= <<'EOS';

MODULE = TestCCAPI

PROTOTYPES: DISABLE

EOS

for my $api (@apis) {
  $xs .= "$api\n\n";
}

save_file("$build_dir/TestCCAPI.xs", $xs);

save_file("$build_dir/Makefile.PL", <<'MKMF');
#!perl -w
use strict;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME 	=> 'TestCCAPI',
    VERSION_FROM => 'TestCCAPI.pm',
    OBJECT       => '$(BASEEXT)$(OBJ_EXT)',
);

MKMF

save_file("$build_dir/TestCCAPI.pm", <<EOS);
package TestCCAPI;
use v5.40;

require XSLoader;
our \$VERSION = "1.000";

XSLoader::load();

1;

EOS

Devel::PPPort::WriteFile("$build_dir/ppport.h");

my $build_outfile = "$build_dir/build.txt";
my $start_dir = getcwd();
my $good = eval {
  chdir $build_dir
    or die "Cannot chdir to $build_dir: $!";
  system "$^X Makefile.PL >$build_outfile 2>&1"
    and die "Cannot Makefile.PL: $?";
  system "make >>$build_outfile 2>&1"
    and die "Cannot make: $?";
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

sub note {
  my $out = join "", @_;
  $out =~ s/^/# /gm;
  $out .= "\n" unless $out =~ /\n\z/;
  print $out;
}

sub diag {
  my $out = join "", @_;
  $out =~ s/^/# /gm;
  $out .= "\n" unless $out =~ /\n\z/;
  print STDERR $out;
}

my $test_num;
sub ok ($ok, $name) {
  ++$test_num;
  print "not " unless $ok;
  print "ok $test_num $name\n";
  $ok;
}

sub done_testing {
  print "1..$test_num\n";
}
