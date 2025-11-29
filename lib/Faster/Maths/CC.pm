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

my $xs_top = do { local $/; <DATA> };

sub make_xs {
  my ($module) = @_;

  our @collection;

  my $code = $xs_top;
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

=head1 AUTHOR

Tony Cook <tony@develop-help.com>

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;

__DATA__
/* generated code */
#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

typedef void (*fragment_handler)(pTHX_ const UNOP_AUX_item *aux);

/* API START */

/* alas, sv_2num() isn't API */
static SV *
my_sv_2num(pTHX_ SV *sv) {
    if (!SvROK(sv))
        return sv;
    if (SvAMAGIC(sv)) {
        SV * const tmpsv = AMG_CALLunary(sv, numer_amg);
        TAINT_IF(tmpsv && SvTAINTED(tmpsv));
        if (tmpsv && (!SvROK(tmpsv) || (SvRV(tmpsv) != SvRV(sv))))
            return my_sv_2num(aTHX_ tmpsv);
    }
    return sv_2mortal(newSVuv(PTR2UV(SvRV(sv))));
}

/* The API try_amagic() functions work with the stack, which
   we don't here.
*/
static SV *
do_try_amagic_bin(pTHX_ SV *out, SV **left, SV **right, int method,
                  int flags, bool mutator) {
    if (SvAMAGIC(*left) || SvAMAGIC(*right)) {
        OP *saved = PL_op; /* to get scalar context /cry */
        PL_op = NULL;
        SV *result = amagic_call(*left, *right, method, flags);
        PL_op = saved;
        if (result) {
            /* this should be controlled by flags */
            if (mutator) {
                sv_setsv(out, result);
                SvSETMAGIC(out);
                return out;
            }
            return result;
         }
        if (flags & AMGf_numeric) {
            *left = my_sv_2num(aTHX_ *left);
            *right = my_sv_2num(aTHX_ *right);
        }
    }
    return NULL;
}

PERL_STATIC_INLINE SV *
my_try_amagic_bin(pTHX_ SV *out, SV **left, SV **right, int method, int flags,
                  bool mutator) {
    /* eventually this will happen during code gen */
    if (UNLIKELY(PL_hints & HINT_NO_AMAGIC))
        return NULL;
    return (UNLIKELY((SvFLAGS(*left) | SvFLAGS(*right)) & SVf_ROK))
      ? do_try_amagic_bin(aTHX_ out, left, right, method, flags, mutator) : NULL;
}

static void
do_add_raw(pTHX_ SV *out, SV *left, SV *right) {
    /* addition without get magic, without overloads */
    /* will do IV preservation eventually */
    sv_setnv(out, SvNV_nomg(left) + SvNV_nomg(right));
}

static inline SV *
do_add(pTHX_ SV *out, SV *left, SV *right, int amagic_flags, bool mutator) {
    SvGETMAGIC(left);
    if (left != right)
        SvGETMAGIC(right);

    SV *result = my_try_amagic_bin(aTHX_ out, &left, &right, add_amg,
                                   amagic_flags | AMGf_numeric, mutator);
    if (result)
        return result;
    do_add_raw(aTHX_ out, left, right);
    return out;
}

static void
do_subtract_raw(pTHX_ SV *out, SV *left, SV *right) {
    /* subtraction without get magic, without overloads */
    /* will do IV preservation eventually */
    sv_setnv(out, SvNV_nomg(left) - SvNV_nomg(right));
}

static inline SV *
do_subtract(pTHX_ SV *out, SV *left, SV *right, int amagic_flags,
            bool mutator) {
    SvGETMAGIC(left);
    if (left != right)
        SvGETMAGIC(right);

    SV *result = my_try_amagic_bin(aTHX_ out, &left, &right, subtr_amg,
                                   amagic_flags | AMGf_numeric, mutator);
    if (result)
        return result;
    do_subtract_raw(aTHX_ out, left, right);
    return out;
}

static void
do_multiply_raw(pTHX_ SV *out, SV *left, SV *right) {
    sv_setnv(out, SvNV_nomg(left) * SvNV_nomg(right));
}

static inline SV *
do_multiply(pTHX_ SV *out, SV *left, SV *right, int amagic_flags,
            bool mutator) {
    SvGETMAGIC(left);
    if (left != right)
        SvGETMAGIC(right);

    SV *result = my_try_amagic_bin(aTHX_ out, &left, &right, mult_amg,
                                   amagic_flags | AMGf_numeric, mutator);
    if (result)
        return result;
    do_multiply_raw(aTHX_ out, left, right);
    return out;
}

static void
do_divide_raw(pTHX_ SV *out, SV *left, SV *right) {
    sv_setnv(out, SvNV_nomg(left) / SvNV_nomg(right));
}

static inline SV *
do_divide(pTHX_ SV *out, SV *left, SV *right, int amagic_flags,
          bool mutator) {
    SvGETMAGIC(left);
    if (left != right)
        SvGETMAGIC(right);

    SV *result = my_try_amagic_bin(aTHX_ out, &left, &right, div_amg,
                                   amagic_flags | AMGf_numeric, mutator);
    if (result)
        return result;
    do_divide_raw(aTHX_ out, left, right);
    return out;
}

/* API END */
