# Faster::Maths::CC

Generate C code from perl ops at runtime, compile them into XS code
and call that instead of the OPs.

Or that's the idea.

This seems to be basically working, though the native math is still
always floating point.  It supports overloads, though the support
there is ugly enough that I have limited trust in it.

The latest changed removed treating constants as constants since that
would have interfered with overloading.

Requires a modern C++ compiler to build and uses fairly modern C++
features, though probably badly, and I don't plan to change this,
except hopefully the badly bit.

There's a few things I want to do here, of which none might happen:

- compile ops to C code and run that code instead of the OPs (works mostly)
- produce output the same as the OPs, in particular, try to preserve
  integers the way the core OPs do (and Faster::Maths doesn't)
- handle overloads too, and optionally disable overloads (works, but can be optimized)
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
- we don't want a so/dll for every code fragment we compile, so
  ideally delay producing that until everything is compiled, but this
  means we need to keep the OP tree around until we get around to
  compiling it. (done, but it means code compiled to perl ops after
  CHECK time isn't compiled to C code.
- UNOP_AUX isn't a LOGOP, we don't have an "other", so we'll need to
  do some nasty op tree traversal. (done by storing the next op)
- caching, yay

```
 PERL_FMC_DEBUG=csF ~/perl/v5.42.0-debug/bin/perl -Mblib -e ' { use Faster::Maths::CC; my ($x, $y, $z); $z = 2 + $x + $y + 1; print "$z\n" }' 
Stack: 
Stack: PAD_SV(((OP*)aux[2].pv)->op_targ)/* 2 */  
Stack: PAD_SV(((OP*)aux[2].pv)->op_targ)/* 2 */  PAD_SV(1) /* $x */ 
SV *loc0 = PAD_SV(1) /* $x */;
SV *loc1 = PAD_SV(4);
SV *loc2 = do_add(aTHX_ loc1, PAD_SV(((OP*)aux[2].pv)->op_targ)/* 2 */ , loc0,
    0, 0);
Stack: loc2 
Stack: loc2 PAD_SV(2) /* $y */ 
SV *loc3 = PAD_SV(2) /* $y */;
SV *loc4 = PAD_SV(5);
SV *loc5 = do_add(aTHX_ loc4, loc2, loc3,
    0, 0);
Stack: loc5 
Stack: loc5 PAD_SV(((OP*)aux[3].pv)->op_targ)/* 1 */  
SV *loc6 = PAD_SV(3) /* $z */;
SV *loc7 = do_add(aTHX_ loc6, loc5, PAD_SV(((OP*)aux[3].pv)->op_targ)/* 1 */ ,
    0, 1);
Stack: 
calling fragment 0
```
