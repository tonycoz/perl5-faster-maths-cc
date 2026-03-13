#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
# Mangled based on :
#  (C) Paul Evans, 2021 -- leonerd@leonerd.org.uk

package Faster::Maths::CC 0.001;

use v5.22;
use warnings;
use File::Temp;
use blib ();
use Devel::PPPort ();
use File::Spec ();
use File::ShareDir ();
use Carp ();

require XSLoader;
XSLoader::load();

sub import {
    $^H{"Faster::Maths::CC/faster"} = 1;
    shift;
    for my $arg (@_) {
        if ($arg =~ /^([+-])float$/) {
            $^H{"Faster::Maths::CC/float"} = $1 eq "+";
        }
        else {
            Carp::croak __PACKAGE__, ": Unknown import $arg";
        }
    }
}

sub unimport {
   $^H{"Faster::Maths::CC/faster"} = 0;
   $^H{"Faster::Maths::CC/float"} = 0;
}

my sub DebugFlags {
  my $key = shift;
  my $env = $ENV{PERL_FMC_DEBUG}
    or return;
  return index($env, $key) >= 0;
}

my sub save_file {
  my ($name, $content) = @_;

  open my $fh, ">", $name
    or die "Cannot create $name: $!\n";
  print $fh $content;
  close $fh
    or die "Cannot close $name: $!\n";
}

my sub run {
  my $cmd = shift;

  unless (DebugFlags("x")) {
    $cmd .= " >" . File::Spec->devnull . " 2>&1";
  }
  return system $cmd;
}

sub make_xs {
  my ($module) = @_;

  our @collection;

  my $header_name =
    File::ShareDir::dist_file("Faster-Maths-CC", "header.c");
  open my $fh, "<", $header_name or die "Cannot open $header_name: $!";
  my $code = do { local $/; <$fh> };
  close $fh;
  for my $entry (@collection) {
    $code .= "// $entry->[3]:$entry->[2]\n";
    $code .= $entry->[0];
  }
  $code .= << 'EOS' . "  ";

static fragment_handler
handlers[] = {
EOS
  $code .= join(",\n  ", map $_->[1], @collection);
  $code .= "\n};\n\n";
  my $count = @collection;
  $code .= <<"EOS";

static const size_t handler_count = $count;

typedef void
(*register_fragments_p)(pTHX_ const fragment_handler *frags,
                   size_t frag_count);

MODULE = $module

# for all our XSUBs
PROTOTYPES: DISABLE

BOOT:
  SV **svp = hv_fetchs(PL_modglobal, "Faster::Maths::CC::register", 0);
  if (!svp)
    Perl_croak(aTHX_ "Could not find FMC registration function");
  register_fragments_p reg = (register_fragments_p)SvIV(*svp);
  reg(aTHX_ handlers, handler_count);
EOS

  return $code;
}

my sub make_mfpl {
  my ($module, $base) = @_;

  return <<"EOS";
use strict;
use ExtUtils::MakeMaker 6.46;

WriteMakefile(
  NAME => "$module",
  VERSION_FROM => "$base.pm",
  OBJECT => '$base\$(OBJ_EXT)',
);
EOS
}

my sub make_pm {
  my ($module) = @_;

  return <<"EOS";
package $module;
use strict;
require XSLoader;
our \$VERSION = "1.000";

XSLoader::load();
EOS
  
}

my $build_dir;

CHECK {
  my $module = "Faster::Maths::CC::Compiled";
  (my $base = $module) =~ s/.*:://;

  my $code = make_xs($module);
  my $cleanup = !$ENV{PERL_FMC_KEEP};
  $build_dir = File::Temp->newdir(CLEANUP => $cleanup);
  print STDERR "Build $build_dir\n" unless $cleanup;
  my $mfpl = "$build_dir/Makefile.PL";
  my $pm = "$build_dir/$base.pm";
  my $xs = "$build_dir/$base.xs";
  my $ppport = "$build_dir/ppport.h";

  # generate the dist files
  save_file($xs, make_xs($module));
  save_file($mfpl, make_mfpl($module, $base));
  save_file($pm, make_pm($module));
  Devel::PPPort::WriteFile($ppport);

  # build it
  my $olddir = Cwd::getcwd();
  chdir $build_dir
    or die "Cannot chdir $build_dir: $!\n";
  my $debug_b = DebugFlags("b");
  my $ok = eval {
    print STDERR "Makefile.PL:\n"
      if $debug_b;
    my $mkpl_opts = $ENV{PERL_FMC_MAKEFILEPL} // "";
    run("$^X Makefile.PL $mkpl_opts")
      and die "Cannot run Makefile.PL\n";
    print STDERR "make:\n"
      if $debug_b;
    run("make")
      and die "Cannot run make\n";
    1;
    };
  chdir $olddir
    or die "Cannot return to $olddir: $!\n";
  $@ and die "Failed build in $build_dir: $@\n";

  print STDERR "Loading:\n"
    if $debug_b;
  blib->import($build_dir);
  require Faster::Maths::CC::Compiled;
}

=head1 NAME

Faster::Maths::CC - make mathematically-intense programs faster

=head1 SYNOPSIS

   use Faster::Maths::CC;

   # and that's it :)

   # optionally:
   use Faster::Maths::CC "+float";

   # and maybe
   no overloading;

=head1 DESCRIPTION

This module attempts to compile some perl code into C code, ideally to
make it faster.

This works similar in concept to L<Faster::Maths> except instead of
generating a byte code and interpreting that, C code is generated.

When enabled for a scope with:

  use Faster::Maths::CC;

I<some> ops in range (see below) are translated to C code (this may
change to C++ for reasons) that tries to behave like the original Perl
ops, including supporting overloading and preserving the lower bits of
large integer values.

If you also disable overloading with

  no overloading;

checks for overloading are disabled, only slightly improving
performance.

You can also request working in floating point:

  use Faster::Maths::CC "+float";

which, when overloading is also disabled, will work in pure floating
point, similar to L<Faster::Maths>.

For the julia set test case from Faster::Maths this produces
performance improvements like:

  Improvement   Configuration
  -----------   -------------
  20%           Faster::Maths::CC
  21%           Faster::Maths::CC, no overloading
  35%           Faster::Maths::CC +float, no overloading
  27%           original Faster::Maths

All relative to native perl performance.

=head2 HOW IT WORKS

During compilation the peep hook is used to trace the C<op_next> chain
looking for chains of three or more OPs that are supported by the code
generation.  Logical OP C<op_other> ops start a new sequence of OPs.

Once a sequence of compatible OPs are found C code is generated for
them, except that instead of pushing and popping values from the perl
value stack, local variables are used instead.  The code generated
currently always works with PADTMPs for results, so there's no new SVs
created beyond those that already exist, avoiding the possibility of
leaks.

When code is generated a C<callcompiled> OP is inserted before the
original OPs, this will call the generated code fragment once the XS
module is generated, compiled and loaded, but falls back to the
original OPs if it hasn't been.

We don't want to compile each generated C code fragment separately, so
they're accumulated until C<CHECK> time when an XS module with the
generated code is created, compiled and loaded.

=head2 BUGS

=over 2

=item *

OPs supported are very limited

=item *

doesn't handle C<+float> with overloading enabled

=item *

warnings are reported against the C<callcompiled> OP rather than the
original (eg. "addition") operator, which can be confusing.

=item *

doesn't handle C<PERL_RC_STACK> builds

=item *

only Perl code compiled before C<CHECK> time is scanned and compiled
to C (this won't be fixed for a while, if at all)

=back

=head1 TODO

=over

=item *

cache generated code - currently the code is generated and the XS
module is created and compiled for each run.  It should be possible to
skip the last steps when restarting the same program.

=item *

Support more OPs

=item *

support more math related ops, builtin functions, POSIX functions

=item *

support more structural code, like loops, conditionals (requires a
major re-work)

=item *

compile leaf functions to directly callable code, and call that from
calling functions.  It may be necessary to delay all code gen to
C<CHECK> time so that functions defined after their call can be called
directly.

=back

=cut

=head1 ENVIRONMENT VARIABLES

=over

=item C<PERL_FMC_DEBUG>

Contains a number of flags controlling debug output from the code
generation and build process:

=over

=item C<s> - dump the emulated stack as OPs are processed.

=item C<c> - write generated code to STDERR.  This does not include
the file preamble (from C<share/header.c>) nor the function headers.

=item C<o> - display each op while processing ops.

=item C<f> - report any failures in processing (currently unused).

=item C<r> - report when the generated code registers itself with
Faster::Maths::CC.

=item C<b> - print a line for each step of the build process.

=item C<x> - prevents build output being redirected to F</dev/null>.

=item C<d> - miscellaneous debug output.

=item C<F> - report calls to the generated code fragments.

=item C<n> - generate the C code and build it, but don't insert the
OPs.

=item C<u> - dUmp the op tree before processing

=item C<S> - include the op sequence number (as with -Dx) when
reporting OP addresses.  This is not thread safe.

=back

=item C<PERL_FMC_KEEP>

If set to non-zero the build directory for the generated XS module
isn't cleaned up on exit and the path to the build directory will be
written to STDERR.

=item C<PERL_FMC_MAKEFILEPL>

Extra options passed to F<Makefile.PL>.  For example you might set:

  PERL_FMC_MAKEFILEPL="OPTIMIZE='-O0 -ggdb3'"

If you want to use a debugger on the generated XS code.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

