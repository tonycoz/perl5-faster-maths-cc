# Faster::Maths::CC

Generate C code from perl ops at runtime, compile them into XS code
and call that instead of the OPs.

Or that's the idea.

Currently it only handles addition and always works in floating point
and I'm sure it's broken in many ways.  In fact it is, the expressions
in the Faster::Maths test code aren't being replace at all.

Some tests from Faster::Maths still run and code is being compiled to
C.  This isn't especially fast since I still put intermediate results
into SVs, but under the right conditions:

```
no overloading;
use Faster::Maths::CC "float";
... code here ...
```

it should be possible the optimize the code into fairly pure floating
point code when applicable, but this hasn't happened yet.

Requires a modern C++ compiler to build and uses fairly modern C++
features, though probably badly, and I don't plan to change this,
except the badly bit.

There's a few things I want to do here, of which none might happen:

- compile ops to C code and run that code instead of the OPs
- produce output the same as the OPs, in particular, try to preserve
  integers the way the core OPs do (and Faster::Maths doesn't)
- handle overloads too, and optionally disable overloads
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
  nothing else the compiler can optimize away the memory access
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
  compiling it.
- UNOP_AUX isn't a LOGOP, we don't have an "other", so we'll need to
  do some nasty op tree traversal.
- caching, yay

```
$ PERL_MFC_DEBUG=csF ~/perl/v5.42.0-debug/bin/perl -Mblib -e ' { use Faster::Maths::CC; my ($x, $y, $z); $z = 2 + $x + $y + 1; print "$z\n" }' 
Stack: 
Stack: SomeSV /* 0x55ea85b93800 */ 
Stack: SomeSV /* 0x55ea85b93800 */ PAD_SV(1) /* $x */ 
sv_setnv(PAD_SV(4), 2 + SvNV(PAD_SV(1) /* $x */));
Stack: PAD_SV(4) 
Stack: PAD_SV(4) PAD_SV(2) /* $y */ 
sv_setnv(PAD_SV(5), SvNV(PAD_SV(4)) + SvNV(PAD_SV(2) /* $y */));
Stack: PAD_SV(5) 
Stack: PAD_SV(5) SomeSV /* 0x55ea85bc14d8 */ 
sv_setnv(PAD_SV(3) /* $z */, SvNV(PAD_SV(5)) + 1);
Stack: PAD_SV(3) /* $z */ 
rpp_extend(1);
rpp_push_1(PAD_SV(3) /* $z */);
calling fragment 0
3
```
