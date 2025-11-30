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

require XSLoader;
XSLoader::load();

sub import
{
   $^H{"Faster::Maths::CC/faster"} = 1;
}

sub unimport
{
   $^H{"Faster::Maths::CC/faster"} = 0;
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

=head1 DESCRIPTION

This module attempts to compile some perl code into C code, ideally to
make it faster.

=head2 BUGS

=over 2

=item *

Currently writes generated code to STDOUT mixed with debug data

=back

=head1 TODO

=over

=item *

Implementation

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

=back

=item C<PERL_FMC_KEEP>

If set to non-zero the build directory for the generated XS module
isn't cleaned up on exit and the path to the build directory will be
written to STDERR.

=back

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

