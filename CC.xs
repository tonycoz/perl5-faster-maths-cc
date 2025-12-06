/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2021 -- leonerd@leonerd.org.uk
 */
#include <vector>
#include <string>
#include <variant>
#include <sstream>
#include <iostream>
#include <tuple>
#include <utility>
#include <unordered_map>

// lazy for now
//#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "cpputil.h"

namespace {


enum class CCDebugFlags {
  DumpStack = 0x0001,  // s - dump the stack while processing ops
  DumpCode  = 0x0002,  // c - write code to stderr while generating
  TraceOps  = 0x0004,  // o - display each op type while processing ops
  Failures  = 0x0008,  // f - report any failures
  Register  = 0x0010,  // r - report when the compiled code registers
  Build     = 0x0020,  // b - print each step of the build process
  NoSink    = 0x0040,  // x - don't redirect build output to /dev/null
  Debug     = 0x0080,  // d - trace info mostly for debugging
  TraceFrags = 0x0100, // F - trace calls to the generated code frags
  NoReplace = 0x0200,  // n - don't replace the OPs
};

using CCDebugBits = BitSet<CCDebugFlags>;

CCDebugBits DebugFlags;

IV CodeIndex;

typedef void (*fragment_handler)(pTHX_ const UNOP_AUX_item *aux);

const fragment_handler *fragments;
size_t fragment_count;

void
init_debug_flags() {
  const char *env = getenv("PERL_FMC_DEBUG");
  if (env) {
    while (*env) {
      switch (*env) {
      case 'c': DebugFlags |= CCDebugFlags::DumpCode;   break;
      case 's': DebugFlags |= CCDebugFlags::DumpStack;  break;
      case 'o': DebugFlags |= CCDebugFlags::TraceOps;   break;
      case 'f': DebugFlags |= CCDebugFlags::Failures;   break;
      case 'r': DebugFlags |= CCDebugFlags::Register;   break;
      case 'b': DebugFlags |= CCDebugFlags::Build;      break;
      case 'x': DebugFlags |= CCDebugFlags::NoSink;     break;
      case 'd': DebugFlags |= CCDebugFlags::Debug;      break;
      case 'F': DebugFlags |= CCDebugFlags::TraceFrags; break;
      case 'n': DebugFlags |= CCDebugFlags::NoReplace;  break;
      }
      ++env;
    }
  }
}

/* a variable in the PAD, typically a "my" variable, but it can
   also be a state or our variable.
*/
struct PadSv {
  PadSv(PADOFFSET index_):index(index_) {
    assert(index_ != 0);
  }
  PadSv() = delete;
  PADOFFSET index = 0; // PAD_SV[index]
};

/* these start as OP_CONST, but on threaded builds
   perl moves them to the pad, and the SV won't be valid
   in a new thread, so we remember the OP (saved in aux)
   and fetch the correct SV via the OP, whether it's still an
   OP_CONST or converted to OP_PADSV
*/
struct OpConst {
  OpConst(size_t op_index_, OP *op_): op_index(op_index_), op(op_) {}
  OpConst() = delete;
  size_t op_index = ~0z;
  OP *op; // used only during C code generation
};

/* an SV stored in a C local variable.
   PadSvs are converted into these to save pad lookups.
   Operator results can be these if the result isn't always in a
   PADTMP (as with overloading).
*/
struct LocalSv {
  LocalSv(int local_index_): local_index(local_index_){}
  LocalSv() = delete;
  int local_index; // SV *variable named l%d
};

/* An SV on the C argument stack, we don't know anything about it,
   so we can't optimize it well
*/
struct StackSv {
  StackSv(ssize_t offset_):offset(offset_) {}
  StackSv() = delete;
  ssize_t offset; // PL_stack_sp[-offset]
};

/* Represents an argument on the stack */
  using ArgType = std::variant<PadSv, OpConst, LocalSv, StackSv>;

#if 0 // we may want this again later

/* An argument in NV form.
   For constants this is ideally the number itself, otherwise it's
   typically SvNV(sv of arg)

   Currently unused but it may change if we can optimize some more
   down the track.
*/
struct RawNumber {
  NV num = 0.0;
};

using NumArg = std::variant<ArgType, RawNumber>;

NumArg
as_number(const OpConst &csv) {
  SV *sv = cSVOPx_sv(csv.op);
  return NumArg{RawNumber{SvNV(sv)}};
}

NumArg
as_number(const PadSv &psv) {
  SV *sv = PAD_SV(psv.index);
  // FIXME: what happens if the SV is AMAGICal? (can it happen?)
  return SvREADONLY(sv) ? NumArg{RawNumber{SvNV(sv)}} : NumArg(psv);
}

NumArg
as_number(const LocalSv &lsv) {
  return NumArg{lsv};
}

NumArg
as_number(const ArgType &arg) {
  return
    std::visit([](const auto &val){ return as_number(val); }, arg);
}

std::ostream &
operator <<(std::ostream &out, const RawNumber &num) {
  out << num.num;
  return out;
}

std::ostream &
operator <<(std::ostream &out, const NumArg &arg) {
  std::visit( overloaded {
      [&]( const ArgType &a) { out << "SvNV(" << a << ")"; },
        [&]( const auto &a) { out << a; },
        }, arg);
  return out;
}

// a result returned from a code fragment
struct CodeResult {
  std::variant<PadSv, RawNumber> result;
};

#endif

// abstraction of the perl value stack
struct Stack {
  ArgType
  pop() {
    if (stack.size()) {
      auto result = stack.back();
      stack.pop_back();
      return result;
    }
    else {
      return ArgType{StackSv{over_popped++}};
    }
  }
  void
  push(const ArgType &&arg) {
    stack.emplace_back(arg);
  }
  size_t
  size() {
    return stack.size();
  }
  auto
  begin() {
    return stack.begin();
  }
  auto
  end() {
    return stack.end();
  }
  // values we've pushed
  std::vector<ArgType> stack;
  // number of values from the real perl stack
  ssize_t over_popped = 0;
};

std::ostream &
operator <<(std::ostream &out, const PadSv &psv) {
  out << "PAD_SV(" << psv.index << ")";
  PADLIST *pl = CvPADLIST(PL_compcv);
  auto names = PadlistNAMES(pl);
  PADNAME *pn = padnamelist_fetch(names, psv.index);
  const char *pv;
  if (pn && (pv = PadnamePV(pn))) {
    out << " /* " << pv << " */";
  }
  return out;
}

std::ostream &
operator <<(std::ostream &out, const LocalSv &lsv) {
  out << "loc" << lsv.local_index;
  return out;
}

#if 0
std::ostream &
operator <<(std::ostream &out, const ConstSv &psv) {
  out << "SomeSV /* " << (void *)psv.sv << " */";
  return out;
}
#endif

void
sv_summary(std::ostream &out, SV *sv) {
  if (SvGMAGICAL(sv)) {
    out << "GMAGICAL";
  }
  else if (!SvOK(sv)) {
    out << "undef";
  }
  else if (SvIOK(sv)) {
    out << SvIVX(sv);
  }
  else if (SvNOK(sv)) {
    out << SvNVX(sv);
  }
  else if (SvPOK(sv)) {
    out << '"';
    STRLEN len;
    const char *pv = SvPV(sv, len);
    bool dots = false;
    if (len > 13) {
      len = 10;
      dots = true;
    }
    const char *end = pv+len;
    for (; pv < end; ++pv) {
      if (*pv >= ' ' && *pv <= '~' && *pv != '/') {
        out << *pv;
      }
      else {
        dots = true;
        break;
      }
    }
    if (dots) out << "...";
    out << '"';
  }
  else if (SvROK(sv)) {
    out << "REF";
  }
  else {
    out << "something...";
  }
}

std::ostream &
operator <<(std::ostream &out, const OpConst &psv) {
#ifdef USE_ITHREADS
  out << "PAD_SV(((OP*)aux[" << psv.op_index << "].pv)->op_targ)";
#else
  out << "cSVOPx_sv((OP*)aux[" << psv.op_index << "].pv)";
#endif
  /* at compile time it is still an OP_CONST either way */
  SV *sv = cSVOPx_sv(psv.op);
  out << "/* ";
  sv_summary(out, sv);
  out << " */ ";
  return out;
}

std::ostream &
operator <<(std::ostream &out, const StackSv &ssv) {
  out << "PL_stack_sp[" << ssv.offset << "]";
  return out;
}

std::ostream &
operator <<(std::ostream &out, const ArgType &arg) {
  // std::variant constructor isn't explicit, so if there
  // isn't an implementation of << for the variant type
  // this will recurse infinitely
  // This makes me sad, but not sad enough to fix it yet.
  std::visit( [&]( const auto &a) { out << a; }, arg);
  return out;
}

#if 0
std::ostream &
operator <<(std::ostream &out, SV *sv) {
  out << SvPV_nolen(sv);
  return out;
}
#endif

std::ostream &
operator <<(std::ostream &out, const Stack &s) {
  for (auto i : s.stack) {
      out << i << ' ';
  }
  return out;
}

inline bool
cop_bool_config(pTHX_ const COP *o, std::string_view key) {
  SV *sv = cop_hints_fetch_pvn(cCOPo, key.data(), key.size(), 0, 0);
  return sv && sv != &PL_sv_placeholder && SvTRUE(sv);
}

struct CodeFragment;

CodeFragment &
operator <<(CodeFragment &os, auto const &v);

/* Used to generate code for an op tree fragment */
struct CodeFragment {
  CodeFragment(pTHX_ const COP *cop, OP *next_op):
    line(CopLINE(cop)), file(CopFILE(cop)),
    overloading((CopHINTS_get(cop) & HINT_NO_AMAGIC) == 0),
    use_float(cop_bool_config(aTHX_ cop, "Faster::Maths::CC/float")) {
    ops.push_back(next_op);
  }
  // save an op containing a constant and return an appropriate
  // "argument" value
  OpConst
  save_const_op(OP *op) {
    size_t index = 1 + ops.size();
    ops.push_back(op);
    return OpConst{index, op};
  }
  LocalSv
  make_local_sv() {
    return LocalSv{local_count++};
  }
  LocalSv
  get_local_sv(const PadSv &psv) {
      auto search = pad_locals.find(psv.index);
      if (search == pad_locals.end()) {
        auto loc = make_local_sv();
        pad_locals.emplace(psv.index, loc.local_index);
        *this << "SV *" << loc << " = " << psv << ";\n";
        return loc;
      }
      else {
        return LocalSv{search->second};
      }
  }
  // simplify an argument into a LocalSv if it's a PadSv to
  // save PAD_SV() calls
  ArgType
  simplify_val(const ArgType &arg) {
    if (std::holds_alternative<PadSv>(arg)) {
      return ArgType{get_local_sv(std::get<PadSv>(arg))};
    }
    else
      return arg;
  }

  std::ostringstream code; // generated code
  std::vector<OP*> ops;    // ops to be saved in the aux block
  bool overloading;        // is overloading enabled?
  bool use_float;          // prefer floating point

  // hash-in-perl-speak of PadSvs we've made locals for
  std::unordered_map<PADOFFSET, int> pad_locals;
  //CodeResult result;
  // code fragment source line extracted from the COP used to
  // generate the function "// file:line" header
  line_t line = 0;
  const char *file = 0;

  // number of generated local variables
  int local_count = 0;

  // don't allow copying or moving, though this may change
  CodeFragment(CodeFragment const &) = delete;
  CodeFragment(CodeFragment &&) = delete;
  CodeFragment &operator=(CodeFragment const &) = delete;
  CodeFragment &operator=(CodeFragment &&) = delete;
};

// I wanted to make the inserter below check the v was insertable
// but got compilation failures and couldn't figure it out
//template <typename T>
//concept Insertable = requires (T a) {
//  { std::declval<std::ostream>() << a };//->std::convertible_to<std::ostream &>;
//};

//template <Insertable Val>

// make ostream inserters available as CodeFragment inserters
CodeFragment &
operator <<(CodeFragment &os, auto const &v) {
  os.code << v;
  if (DebugFlags(CCDebugFlags::DumpCode))
    std::cerr << v;
  return os;
}

XOP xop_callcompiled;

inline OP *
oCCOP_SKIP(OP *o) {
  const UNOP_AUX_item *aux = cUNOP_AUXo->op_aux;

  // I was OPs in UNOP_AUX_item for christmas
  return (OP*)aux[1].pv;
}

// ppfunc for our ops
OP *
pp_callcompiled(pTHX)
{
  // op_next points to the op tree fragment we're generating this
  // C code fragment from, so NORMAL will be sane when we don't have
  // compiled code to run yet
  if (fragments == nullptr) {
    if (DebugFlags(CCDebugFlags::Debug))
      std::cerr << "could not run " << (void*)PL_op << ": not generated\n";
    return NORMAL; // use the old
  }
  const UNOP_AUX_item *aux = cUNOP_AUX->op_aux;
  UV index = aux[0].uv;
  if (index >= fragment_count) {
    if (DebugFlags(CCDebugFlags::Debug))
      std::cerr << "could not run " << (void*)PL_op
                << ": high index " << index << "\n";
    return NORMAL; // use the old
  }

  if (DebugFlags(CCDebugFlags::TraceFrags)) {
    std::cerr << "calling fragment " << index << "\n";
  }
  fragments[index](aTHX_ aux);

  // skip the old op tree
  return (OP*)aux[1].pv; // umm
}

// given generated code finish it up:
// - generate code:
//   - to pop consumed stack
//   - push return values
//   - function definition header and trailer
// - save it generated code to @collection for later use
// - build the OP and insert it into the OP tree
void
code_finalize(pTHX_ CodeFragment &code, Stack &stack, OP *start,
              OP *final, OP *prev) {
  // FIXME: if we're pushing something we popped this will free it
  // and then try to use it for reference counted stack builds
  // which would be bad
  if (stack.over_popped) {
    code << "rpp_popfree_to(PL_stack_sp-"
         << stack.over_popped << ");\n";
  }
  if (stack.size() != 0)
    code << "rpp_extend(" << stack.size() << ");\n";
  for (auto item : stack) {
    // this may need to change
    code << "rpp_push_1(" << item << ");\n";
  }

  IV index = CodeIndex++;
  SV *out = Perl_newSVpvf(aTHX_ "static void\nf%" UVf "(pTHX_ "
                          "const UNOP_AUX_item *aux) {\n", index);
  std::string codestring = code.code.str();
  sv_catpvn(out, codestring.c_str(), codestring.size());
  sv_catpvs(out, "}\n");

  SV *func = Perl_newSVpvf(aTHX_ "f%" UVf, index);
  AV *entry = newAV();
  av_store(entry, 0, out);
  av_store(entry, 1, func);
  av_store(entry, 2, newSVuv(code.line));
  av_store(entry, 3, newSVpvn(code.file, strlen(code.file)));
  AV *collection = get_av("Faster::Maths::CC::collection", GV_ADD);
  av_store(collection, index, newRV_noinc((SV*)entry));

  if (DebugFlags(CCDebugFlags::NoReplace)) {
    std::cerr << "Skipping OP replacement\n";
    return;
  }
  if (DebugFlags(CCDebugFlags::Debug))
    std::cerr << "Performing OP replacement\n";

  UNOP_AUX_item *aux;
  Newx(aux, 1+code.ops.size(), UNOP_AUX_item);
  aux[0].iv = index;
  size_t op_index = 1;
  for (auto op : code.ops) {
    aux[op_index++].pv = (char *)op; // booo!
  }
  OP *retop = newUNOP_AUX(OP_CUSTOM, 0, NULL, aux);

  // we want this between the final and it's previous sibling
  retop->op_ppaddr = &pp_callcompiled;
  retop->op_next = start;

  OP *parent = op_parent(final);
  if (DebugFlags(CCDebugFlags::Debug)) {
    std::cerr << "insertion parent " << (void*)parent
              << " after " << (void *)prev
              << " start " << (void *)start
              << " final " << (void *)final << "\n";
  }

  op_sibling_splice(parent, prev, 0, retop);
  prev->op_next = retop;
}

ArgType
binop_normal(pTHX_ OP *o, std::string_view opname, CodeFragment &code,
             const ArgType &out, const ArgType &left, const ArgType &right) {
  bool mutator =
    (PL_opargs[o->op_type] & OA_TARGLEX)
    && (o->op_private & OPpTARGET_MY);

  // the result might be in out, or it might be in a mortal
  // so just some SV
  ArgType result = code.make_local_sv();
  code << "SV *" << result << " = "
       << opname << "(aTHX_ " << out << ", "
       << left << ", "
       << right << ",\n    0";
  if (o->op_flags & OPf_STACKED) {
    code << " | AMGf_assign";
  }
  code << ", " << mutator << ");\n";

  return result;
}

ArgType
binop_noov(pTHX_ std::string_view opname, CodeFragment &code,
           const ArgType &out, const ArgType &left,
           const ArgType &right) {
    code << opname << "_noov" << "(aTHX_ "
         << out << ", "
         << left << ", "
         << right << ");\n";
    return out;
}

ArgType
binop_float(pTHX_ std::string_view op, CodeFragment &code,
            const ArgType &out, const ArgType &left,
            const ArgType &right) {
  code << "sv_setnv(" << out << ", SvNV("
       << left << ") "
       << op << " SvNV("
       << right << "));\n";
  return out;
}

// generate code for a binop
void
add_binop(pTHX_ OP *o, CodeFragment &code, Stack &stack,
          std::string_view opname, std::string_view op) {
  auto right = code.simplify_val(stack.pop());
  auto left = code.simplify_val(stack.pop());
  auto out = o->op_flags & OPf_STACKED ? left : code.simplify_val(PadSv{o->op_targ});

  ArgType result = code.overloading
    ? binop_normal(aTHX_ o, opname, code, out, left, right)
    : code.use_float
    ? binop_float(aTHX_ op, code, out, left, right)
    : binop_noov(aTHX_ opname, code, out, left, right);

  // only push a result if non-void
  if (OP_GIMME(o, OPf_WANT_SCALAR) != OPf_WANT_VOID)
    stack.push(std::move(result));
}

void
compile_code(pTHX_ CodeFragment &code, OP *start, OP *final, OP *prev)
{
  Stack stack;
  OP *oprev = NULL;
  for(OP *o = start; o; o = o->op_next) {
    if (DebugFlags(CCDebugFlags::TraceOps)) {
      std::cerr << "Compile op: " << o->op_type << " "
                << OP_NAME(o) << "\n";
    }
    if (DebugFlags(CCDebugFlags::DumpStack))
      std::cerr << "Stack: " << stack << "\n";
    if (DebugFlags(CCDebugFlags::TraceOps))
      std::cerr << "Op: " << OP_NAME(o) << "\n";
    switch(o->op_type) {
      case OP_CONST:
        stack.push(code.save_const_op(o));
        break;

      case OP_PADSV:
        stack.push(PadSv{o->op_targ});
        break;

      case OP_ADD:
        // FIXME: SvSETMAGIC() as needed
        add_binop(aTHX_ o, code, stack, "do_add", "+");
        break;

      case OP_SUBTRACT:
        add_binop(aTHX_ o, code, stack, "do_subtract", "-");
        break;

      case OP_MULTIPLY:
        add_binop(aTHX_ o, code, stack, "do_multiply", "*");
        break;

      case OP_DIVIDE:
        add_binop(aTHX_ o, code, stack, "do_divide", "/");
        break;

      case OP_NEGATE:
        {
          auto arg = code.simplify_val(stack.pop());
          auto out = code.simplify_val(PadSv{o->op_targ});
          code << "sv_setnv(" << out << ", -SvNV(" << arg << "));\n";
          if (OP_GIMME(o, OPf_WANT_SCALAR) != OPf_WANT_VOID)
            stack.push(ArgType{out});
        }
        break;

      default:
        croak("ARGH unsure how to optimize this op\n");
    }
    oprev = o;
    if (o == final)
      break;
  }
  if (DebugFlags(CCDebugFlags::DumpStack))
    std::cerr << "Stack: " << stack << "\n";

  code_finalize(aTHX_ code, stack, start, oprev, prev);
  return;
}

void
rpeep_for_callcompiled(pTHX_ OP *o, bool init_enabled)
{
  bool enabled = init_enabled;

  /* In some cases (e.g.  while(1) { ... } ) the ->op_next chain actually
   * forms a closed loop. In order to detect this loop and break out we'll
   * advance the `slowo` pointer half as fast as o. If o is ever equal to
   * slowo then we have reached a cycle and should stop
   */
  OP *slowo = NULL;
  int slowotick = 0;

  size_t depth = 0;
  int count = 0;
  OP *first = NULL;
  OP *firstprev = NULL;
  OP *oprev = NULL;
  const COP *last_cop = PL_curcop;
  if (DebugFlags(CCDebugFlags::Debug))
    std::cerr << "rpeep enabled " << enabled << "\n";

  while(o && o != slowo) {
    if(o->op_type == OP_NEXTSTATE) {
      SV *sv = cop_hints_fetch_pvs(cCOPo, "Faster::Maths::CC/faster", 0);
      enabled = sv && sv != &PL_sv_placeholder && SvTRUE(sv);
      if (first && oprev && count > 1) {
        if (DebugFlags(CCDebugFlags::Debug)) {
          std::cerr << "Trace: calling code gen\n";
        }
        CodeFragment code{aTHX_ last_cop, o};
        compile_code(aTHX_ code, first, oprev, firstprev);
      }
      else if (DebugFlags(CCDebugFlags::Debug)) {
        std::cerr << "Trace: skipped code gen first "
                  << (void *)first
                  << " oprev " << (void *)oprev
                  << " count " << count << "\n";
      }
      last_cop = (const COP *)o;
      firstprev = o;
      first = o->op_next;
      count = 0;
      depth = 0;
      DEBUG_u( PerlIO_printf(PerlIO_stderr(), "nextstate %p file %s line %d enabled %d\n",
                             o, CopFILE(cCOPo), CopLINE(cCOPo), enabled) );
    }
    if (enabled) {
      DEBUG_u( PerlIO_printf(PerlIO_stderr(), "scan op %d (%s %p) depth %zu count %d prev %p\n",
                             o->op_type, OP_NAME(o), (void *)o, depth, count, (void *)oprev) );
      switch(o->op_type) {
      case OP_CUSTOM:
        if (o->op_ppaddr == pp_callcompiled) {
          if (DebugFlags(CCDebugFlags::Debug))
            std::cerr << "Trace: saw our custom op... skipping\n";
          // we've processed this block
          // make sure we don't do it again
          firstprev = oprev = o;
          o = oCCOP_SKIP(o);
          first = o;
          depth = 0;
          count = 0;
        }
        break;

      case OP_CONST:
      case OP_PADSV:
        ++depth;
        break;

      case OP_ADD:
      case OP_SUBTRACT:
      case OP_MULTIPLY:
      case OP_DIVIDE:
         --depth;
         ++count;
        break;
      case OP_NEGATE:
        ++count;
        break;

      case OP_OR:
      case OP_AND:
      case OP_DOR:
#if PERL_VERSION_GE(5,32,0)
      case OP_CMPCHAIN_AND:
#endif
      case OP_COND_EXPR:
      case OP_MAPWHILE:
      case OP_ANDASSIGN:
      case OP_ORASSIGN:
      case OP_DORASSIGN:
      case OP_RANGE:
      case OP_ONCE:
#if PERL_VERSION_GE(5,26,0)
      case OP_ARGDEFELEM:
#endif
        /* Optimize on the righthand side of `or` / `and` operators and other.
         * similar cases. This might catch more things than perl's own
         * recursion inside because simple expressions don't begin with an
         * OP_NEXTSTATE
         */
        // this recursion is probably badly broken right now (as in
        // produce bad code or crash)
        if(cLOGOPo->op_other && cLOGOPo->op_other->op_type != OP_NEXTSTATE)
          rpeep_for_callcompiled(aTHX_ cLOGOPo->op_other, enabled);
        break;

      default:
        if (DebugFlags(CCDebugFlags::Debug))
          std::cerr << "Trace: unrecognized op\n";
        if (first && oprev && count > 1) {
          if (DebugFlags(CCDebugFlags::Debug)) {
            std::cerr << "Trace: calling code gen\n";
          }
          CodeFragment code {aTHX_ last_cop, o};
          compile_code(aTHX_ code, first, oprev, firstprev);
        }
        else if (DebugFlags(CCDebugFlags::Debug)) {
          std::cerr << "Trace: skipped code gen first "
                    << (void *)first
                    << " oprev " << (void *)oprev
                    << " count " << count << "\n";
        }
        firstprev = o;
        first = o->op_next;
        count = 0;
        break;
      }
    }
    if (!slowo)
      slowo = o;
    else if ((slowotick++) % 2)
      slowo = slowo->op_next;
    oprev = o;
    o = o->op_next;
  }
}

void (*next_rpeepp)(pTHX_ OP *o);

void
my_rpeepp(pTHX_ OP *o)
{
  if(!o)
    return;

  (*next_rpeepp)(aTHX_ o);

  if (!fragments)
    rpeep_for_callcompiled(aTHX_ o, false);
}

#ifdef XOPf_xop_dump
static void
my_xop_dump(pTHX_ const OP *o, struct Perl_OpDumpContext *ctx) {
  UNOP_AUX_item *aux = cUNOP_AUXo->op_aux;

  Perl_opdump_printf(aTHX_ ctx, "INDEX = %" UVuf "\n", aux[0].uv);
  Perl_opdump_printf(aTHX_ ctx, "OTHEROP = 0x%p\n", (void*)aux[1].pv);
}
#endif

// called via PL_modglobal from the generated module to register
// the code fragment lookup table
void
register_fragments(pTHX_ const fragment_handler *frags,
                   size_t frag_count) {
  fragment_count = frag_count;
  fragments = frags;
  if (DebugFlags(CCDebugFlags::Register))
    std::cerr << "Registered " << frag_count << " handlers\n";
}

}

MODULE = Faster::Maths::CC    PACKAGE = Faster::Maths::CC

PROTOTYPES: DISABLE

BOOT:
  init_debug_flags();
  next_rpeepp = PL_rpeepp;
  PL_rpeepp = &my_rpeepp;

  XopENTRY_set(&xop_callcompiled, xop_name, "callcompiled");
  XopENTRY_set(&xop_callcompiled, xop_desc,
    "call into C compiled code generated from the OP tree");
  XopENTRY_set(&xop_callcompiled, xop_class, OA_UNOP_AUX);
#ifdef XOPf_xop_dump
  XopENTRY_set(&xop_callcompiled, xop_dump, my_xop_dump);
#endif
  Perl_custom_op_register(aTHX_ &pp_callcompiled, &xop_callcompiled);
  (void) hv_stores(PL_modglobal, "Faster::Maths::CC::register",
                            newSViv(PTR2IV(register_fragments)));
  // FIXME: hook PL_opfreehook to clean up aux items
