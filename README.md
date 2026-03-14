# Faster::Maths::CC

Generate C code from perl ops at runtime, compile them into XS code
and call that instead of the OPs.

Or that's the idea.

It can produce significantly faster code for what it does, for
example, comparing:

```
sub julia
{
   my ($zr, $zi) = @_;
   my ($cr, $ci) = @$C;

   my $count = $MAXCOUNT;
   while ( $count and $zr*$zr + $zi*$zi < 2*2 ) {
      ($zr, $zi) = ( ($zr*$zr - $zi*$zi + $cr), 2*($zr*$zi) + $ci );
      --$count or return undef;
   }

   return $count;
}
```

benchmarked with various options:

```
  Improvement   Configuration
  -----------   -------------
  17%           Faster::Maths::CC
  35%           Faster::Maths::CC +float
  20%           Faster::Maths::CC, no overloading
  43%           Faster::Maths::CC +float, no overloading
  27%           original Faster::Maths
```

Your milage will definitely vary.

This seems to be basically working for the OPs supported.  It supports
overloads, though the support there is ugly enough that I have limited
trust in it.

Requires a modern C++ compiler to build and uses fairly modern C++
features, though probably badly, and I don't plan to change this,
except hopefully the badly bit.

There's a few things I want to do here, of which none might happen:

- compile ops to C code and run that code instead of the OPs (works mostly)
- produce output the same as the OPs, in particular, try to preserve
  integers the way the core OPs do (done)
- handle overloads too, and optionally disable overloads (done)
- optimize OPs in sensible ways, if the code adds/multiplies by a
  float, then just do a floating point multiply
- optimize away overloads if we can
- replace various standard functions by direct calls, so POSIX::ceil()
  just calls ceil().
- do more than just maths
- allow leaf functions to be called directly from other FMC code
- use attributes or `my $x : integer` syntax to mark variables as a
  given type and produce code based on that.
- optimize to avoid multiple PAD_SV() calls for the same index, if
  nothing else the compiler can optimize away the memory access (done)
- handle intermediate results as their types, eg, i_add always makes
  an IV, so don't bother storing it in a padsv unless it's the final
  result
- handle LVINTRO padsvs (need to handle padsv_store, padsv with and
  without those flags)

Some thoughts:

- we may need to convert `OP_CONST`s to `OP_PADSV` early, since
  storing raw pointer in the generated code would prevent caching
  (they get converted later on threaded builds of perl but it may
  complicate other code transformations)
- caching, yay

Code from `t/95benchmark.t`, generated from the perl code;

with `use Faster::Maths::CC;`, `use Faster::Maths::CC "+float";`
combined with `no overloading;` or not.

The op tree fragments compiled correspond to the `$zr*$zr + $zi*$zi <
2*2` code (though without the actual comparison) and to the list `(
($zr*$zr - $zi*$zi + $cr), 2*($zr*$zi) + $ci )` on the next line.

The non-perl-API functions are defined in `share/header.c`, and are
generally derived from the implementations in perl itself, eg `do_add`
was derived from `pp_add` and so on.

Plain `use Faster::Maths::CC;`:

```
// t/95benchmark.t:55
static void
f0(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:55
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(17) /* t17 */ ;
SV *loc2 = do_multiply(aTHX_ loc1, loc0, loc0,
    0, 0);
SV *loc3 = PAD_SV(2) /* $zi */;
SV *loc4 = PAD_SV(18) /* t18 */ ;
SV *loc5 = do_multiply(aTHX_ loc4, loc3, loc3,
    0, 0);
SV *loc6 = PAD_SV(19) /* t19 */ ;
SV *loc7 = do_subtract(aTHX_ loc6, loc2, loc5,
    0, 0);
SV *loc8 = PAD_SV(6) /* $cr */;
SV *loc9 = PAD_SV(20) /* t20 */ ;
SV *loc10 = do_add(aTHX_ loc9, loc7, loc8,
    0, 0);
SV *loc11 = PAD_SV(21) /* t21 */ ;
SV *loc12 = do_multiply(aTHX_ loc11, loc0, loc3,
    0, 0);
SV *loc13 = PAD_SV(22) /* t22 */ ;
SV *loc14 = do_multiply(aTHX_ loc13, PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 2 */ , loc12,
    0, 0);
SV *loc15 = PAD_SV(7) /* $ci */;
SV *loc16 = PAD_SV(23) /* t23 */ ;
SV *loc17 = do_add(aTHX_ loc16, loc14, loc15,
    0, 0);
rpp_extend(2);
rpp_push_1(loc10);
rpp_push_1(loc17);
}
// t/95benchmark.t:59
static void
f1(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:59
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(13) /* t13 */ ;
SV *loc2 = do_multiply(aTHX_ loc1, loc0, loc0,
    0, 0);
SV *loc3 = PAD_SV(2) /* $zi */;
SV *loc4 = PAD_SV(14) /* t14 */ ;
SV *loc5 = do_multiply(aTHX_ loc4, loc3, loc3,
    0, 0);
SV *loc6 = PAD_SV(15) /* t15 */ ;
SV *loc7 = do_add(aTHX_ loc6, loc2, loc5,
    0, 0);
rpp_extend(2);
rpp_push_1(loc7);
rpp_push_1(PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 4 */ );
}
```

Plain `use Faster::Maths::CC;` combined with `no overloading;`:
```
// t/95benchmark.t:72
static void
f2(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:72
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(17) /* t17 */ ;
do_multiply_noov(aTHX_ loc1, loc0, loc0);
SV *loc2 = PAD_SV(2) /* $zi */;
SV *loc3 = PAD_SV(18) /* t18 */ ;
do_multiply_noov(aTHX_ loc3, loc2, loc2);
SV *loc4 = PAD_SV(19) /* t19 */ ;
do_subtract_noov(aTHX_ loc4, loc1, loc3);
SV *loc5 = PAD_SV(6) /* $cr */;
SV *loc6 = PAD_SV(20) /* t20 */ ;
do_add_noov(aTHX_ loc6, loc4, loc5);
SV *loc7 = PAD_SV(21) /* t21 */ ;
do_multiply_noov(aTHX_ loc7, loc0, loc2);
SV *loc8 = PAD_SV(22) /* t22 */ ;
do_multiply_noov(aTHX_ loc8, PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 2 */ , loc7);
SV *loc9 = PAD_SV(7) /* $ci */;
SV *loc10 = PAD_SV(23) /* t23 */ ;
do_add_noov(aTHX_ loc10, loc8, loc9);
rpp_extend(2);
rpp_push_1(loc6);
rpp_push_1(loc10);
}
// t/95benchmark.t:76
static void
f3(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:76
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(13) /* t13 */ ;
do_multiply_noov(aTHX_ loc1, loc0, loc0);
SV *loc2 = PAD_SV(2) /* $zi */;
SV *loc3 = PAD_SV(14) /* t14 */ ;
do_multiply_noov(aTHX_ loc3, loc2, loc2);
SV *loc4 = PAD_SV(15) /* t15 */ ;
do_add_noov(aTHX_ loc4, loc1, loc3);
rpp_extend(2);
rpp_push_1(loc4);
rpp_push_1(PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 4 */ );
}
```

Plain `use Faster::Maths::CC "+float";`, overloading enabled:
```
// t/95benchmark.t:88
static void
f4(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:88
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(17) /* t17 */ ;
SV *loc2 = do_multiply_ovfloat(aTHX_ loc1, loc0, loc0,
    0, 0);
SV *loc3 = PAD_SV(2) /* $zi */;
SV *loc4 = PAD_SV(18) /* t18 */ ;
SV *loc5 = do_multiply_ovfloat(aTHX_ loc4, loc3, loc3,
    0, 0);
SV *loc6 = PAD_SV(19) /* t19 */ ;
SV *loc7 = do_subtract_ovfloat(aTHX_ loc6, loc2, loc5,
    0, 0);
SV *loc8 = PAD_SV(6) /* $cr */;
SV *loc9 = PAD_SV(20) /* t20 */ ;
SV *loc10 = do_add_ovfloat(aTHX_ loc9, loc7, loc8,
    0, 0);
SV *loc11 = PAD_SV(21) /* t21 */ ;
SV *loc12 = do_multiply_ovfloat(aTHX_ loc11, loc0, loc3,
    0, 0);
SV *loc13 = PAD_SV(22) /* t22 */ ;
SV *loc14 = do_multiply_ovfloat(aTHX_ loc13, PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 2 */ , loc12,
    0, 0);
SV *loc15 = PAD_SV(7) /* $ci */;
SV *loc16 = PAD_SV(23) /* t23 */ ;
SV *loc17 = do_add_ovfloat(aTHX_ loc16, loc14, loc15,
    0, 0);
rpp_extend(2);
rpp_push_1(loc10);
rpp_push_1(loc17);
}
// t/95benchmark.t:92
static void
f5(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:92
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(13) /* t13 */ ;
SV *loc2 = do_multiply_ovfloat(aTHX_ loc1, loc0, loc0,
    0, 0);
SV *loc3 = PAD_SV(2) /* $zi */;
SV *loc4 = PAD_SV(14) /* t14 */ ;
SV *loc5 = do_multiply_ovfloat(aTHX_ loc4, loc3, loc3,
    0, 0);
SV *loc6 = PAD_SV(15) /* t15 */ ;
SV *loc7 = do_add_ovfloat(aTHX_ loc6, loc2, loc5,
    0, 0);
rpp_extend(2);
rpp_push_1(loc7);
rpp_push_1(PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 4 */ );
}
```

`use Faster::Maths::CC "+float";` with `no overloading;`:

```
// t/95benchmark.t:105
static void
f6(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:105
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(17) /* t17 */ ;
fast_sv_setnv(aTHX_ loc1, SvNV(loc0) * SvNV(loc0));
SV *loc2 = PAD_SV(2) /* $zi */;
SV *loc3 = PAD_SV(18) /* t18 */ ;
fast_sv_setnv(aTHX_ loc3, SvNV(loc2) * SvNV(loc2));
SV *loc4 = PAD_SV(19) /* t19 */ ;
fast_sv_setnv(aTHX_ loc4, SvNV(loc1) - SvNV(loc3));
SV *loc5 = PAD_SV(6) /* $cr */;
SV *loc6 = PAD_SV(20) /* t20 */ ;
fast_sv_setnv(aTHX_ loc6, SvNV(loc4) + SvNV(loc5));
SV *loc7 = PAD_SV(21) /* t21 */ ;
fast_sv_setnv(aTHX_ loc7, SvNV(loc0) * SvNV(loc2));
SV *loc8 = PAD_SV(22) /* t22 */ ;
fast_sv_setnv(aTHX_ loc8, SvNV(PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 2 */ ) * SvNV(loc7));
SV *loc9 = PAD_SV(7) /* $ci */;
SV *loc10 = PAD_SV(23) /* t23 */ ;
fast_sv_setnv(aTHX_ loc10, SvNV(loc8) + SvNV(loc9));
rpp_extend(2);
rpp_push_1(loc6);
rpp_push_1(loc10);
}
// t/95benchmark.t:109
static void
f7(pTHX_ const UNOP_AUX_item *aux) {
// t/95benchmark.t:109
SV *loc0 = PAD_SV(1) /* $zr */;
SV *loc1 = PAD_SV(13) /* t13 */ ;
fast_sv_setnv(aTHX_ loc1, SvNV(loc0) * SvNV(loc0));
SV *loc2 = PAD_SV(2) /* $zi */;
SV *loc3 = PAD_SV(14) /* t14 */ ;
fast_sv_setnv(aTHX_ loc3, SvNV(loc2) * SvNV(loc2));
SV *loc4 = PAD_SV(15) /* t15 */ ;
fast_sv_setnv(aTHX_ loc4, SvNV(loc1) + SvNV(loc3));
rpp_extend(2);
rpp_push_1(loc4);
rpp_push_1(PAD_SV(((OP*)aux[2].pv)->op_targ)/* IV 4 */ );
}
```
