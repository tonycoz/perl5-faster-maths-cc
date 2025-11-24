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
  Run       = 0x0040,  // R - report programs we run (Makerfile.PL, make)
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
      case 'R': DebugFlags |= CCDebugFlags::Run;        break;
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
  PADOFFSET index = 0;
};

/* these start as OP_CONST, but on threaded builds
   perl moves them to the pad, and the SV won't be valid
   in a new thread, so we remember the OP (saved in aux)
   and fetch the correct SV via the OP, whether it's still an
   OP_CONST or converted to OP_PADSV
*/
struct OpConst {
  size_t op_index = ~0z;
  OP *op; // used only during C code generation
};

struct LocalSv {
  int local_index;
};

using ArgType = std::variant<PadSv, OpConst, LocalSv>;

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
  return SvREADONLY(sv) ? NumArg{RawNumber{SvNV(sv)}} : NumArg(psv);
}

NumArg
as_number(const LocalSv &lsv) {
  return NumArg{lsv};
}

// a result returned from a code fragment
struct CodeResult {
  std::variant<PadSv, RawNumber> result;
};

// helper for visiting
template<class... Ts>
struct overloaded : Ts... { using Ts::operator()...; };
// explicit deduction guide (not needed as of C++20)
template<class... Ts>
overloaded(Ts...) -> overloaded<Ts...>;

NumArg
as_number(const ArgType &arg) {
  //NumArg result;
  return
    std::visit([](const auto &val){ return as_number(val); }, arg);
}

using Stack = std::vector<ArgType>;

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
operator <<(std::ostream &out, const ArgType &arg) {
  std::visit( [&]( const auto &a) { out << a; }, arg);
  return out;
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

#if 0
std::ostream &
operator <<(std::ostream &out, SV *sv) {
  out << SvPV_nolen(sv);
  return out;
}
#endif

std::ostream &
operator <<(std::ostream &out, const Stack &s) {
  for (auto i : s) {
      out << i << ' ';
  }
  return out;
}

struct CodeFragment;

CodeFragment &
operator <<(CodeFragment &os, auto const &v);

/* Used to generate code for an op tree fragment */
struct CodeFragment {
  CodeFragment(const COP *cop, OP *next_op):
    line(CopLINE(cop)), file(CopFILE(cop)) {
    ops.push_back(next_op);
  }
#undef save_op
  OpConst
  save_op(OP *op) {
    size_t index = 1 + ops.size();
    ops.push_back(op);
    return OpConst{index, op};
  }
  ArgType
  simplify_val(const ArgType &arg) {
    if (std::holds_alternative<PadSv>(arg)) {
      PADOFFSET pad_index = std::get<PadSv>(arg).index;
      auto search = pad_locals.find(pad_index);
      if (search == pad_locals.end()) {
        pad_locals[pad_index] = local_count;
        ArgType result{LocalSv{local_count++}};
        *this << "SV *" << result << " = " << arg << ";\n";
        return result;
      }
      else {
        return ArgType{LocalSv{search->second}};
      }
    }
    else
      return arg;
  }

  std::ostringstream code;
  std::vector<OP*> ops;
  std::unordered_map<PADOFFSET, int> pad_locals;
  //CodeResult result;
  line_t line = 0;
  const char *file = 0;
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
CodeFragment &
operator <<(CodeFragment &os, auto const &v) {
  os.code << v;
  if (DebugFlags(CCDebugFlags::DumpCode))
    std::cerr << v;
  return os;
}

XOP xop_callcompiled;

OP *
pp_callcompiled(pTHX)
{
  if (fragments == nullptr) {
    if (DebugFlags(CCDebugFlags::Run))
      std::cerr << "could not run " << (void*)PL_op << ": not generated\n";
    return NORMAL; // use the old
  }
  const UNOP_AUX_item *aux = cUNOP_AUX->op_aux;
  UV index = aux[0].uv;
  if (index >= fragment_count) {
    if (DebugFlags(CCDebugFlags::Run))
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

void
code_finalize(pTHX_ CodeFragment &code, Stack &stack, OP *start,
              OP *final, OP *prev) {
  // no result?
  if (stack.size() == 0) {
    if (DebugFlags(CCDebugFlags::Failures)) {
      std::cerr << "Failed to finalize: stack empty\n";
    }
    return;
  }
  code << "rpp_extend(" << stack.size() << ");\n";
  for (auto item : stack) {
    // this may need to change
    code << "rpp_push_1(" << item << ");\n";
  }

  IV index = CodeIndex++;
  SV *out = Perl_newSVpvf(aTHX_ "static void\nf%" UVf "(pTHX, "
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

  // we don't really need an UNOP_AUX yet, but I expect we will later
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
  OP *oprev = NULL;
  assert(parent->op_flags & OPf_KIDS); // if not, how did we get here?
  OP *o = cUNOPx(parent)->op_first;
  while (o != NULL && o != final) {
    oprev = o;
    o = OpSIBLING(o);
  }
  assert(o); // we must find "final"
  if (DebugFlags(CCDebugFlags::Debug))
    std::cerr << "finalize oprev " << oprev
              << " next " << (oprev ? (void *)oprev->op_next : nullptr)
              << " start " << (void *)start
              << " prev " << (void *)prev << "\n";
  //  assert(oprev == nullptr || oprev->op_next == start);
  if (DebugFlags(CCDebugFlags::Debug)) {
    std::cerr << "insertion parent " << (void*)parent
              << " after " << (void *)oprev
              << " start " << (void *)start
              << " final " << (void *)final << "\n";
  }

  op_sibling_splice(parent, prev, 0, retop);
  prev->op_next = retop;
}

void
add_binop(OP *o, CodeFragment &code, Stack &stack, std::string_view opname) {
  auto right = as_number(code.simplify_val(stack.back()));
  stack.pop_back();
  auto raw_left = code.simplify_val(stack.back());
  auto left = as_number(raw_left);
  stack.pop_back();
  auto out = o->op_flags & OPf_STACKED ? raw_left : code.simplify_val(PadSv{o->op_targ});

  code << "sv_setnv(" << out << ", "
       << left << ' ' << opname << " " << right << ");\n";
  // only push a result if non-void
  if (OP_GIMME(o, OPf_WANT_SCALAR) != OPf_WANT_VOID)
    stack.emplace_back(out);
}

#define compile_code(code, start, final, prev)               \
  MY_compile_code(aTHX_ code, start, final, prev)
void
MY_compile_code(pTHX_ CodeFragment &code, OP *start, OP *final, OP *prev)
{
  OP *o;
  /* Phase 1: just count the number of aux items we need
   * We'll need one for every constant or padix
   * Also count the maximum stack height
   */

  Stack stack;
  OP *oprev = NULL;
  for(o = start; o; o = o->op_next) {
    if (DebugFlags(CCDebugFlags::TraceOps)) {
    }
    if (DebugFlags(CCDebugFlags::DumpStack))
      std::cerr << "Stack: " << stack << "\n";
    if (DebugFlags(CCDebugFlags::TraceOps))
      std::cerr << "Op: " << OP_NAME(o) << "\n";
    switch(o->op_type) {
      case OP_CONST:
        stack.emplace_back(code.save_op(o));
        break;

      case OP_PADSV:
        stack.emplace_back(PadSv{o->op_targ});
        break;

      case OP_ADD:
        add_binop(o, code, stack, "+");
        break;

      case OP_SUBTRACT:
        add_binop(o, code, stack, "-");
        break;

      case OP_MULTIPLY:
        add_binop(o, code, stack, "*");
        break;

      case OP_DIVIDE:
        add_binop(o, code, stack, "/");
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
  //return o;

#if 0
  if(SvPVX(prog)[0] != '(')
    croak("ARGH: expected prog to begin (");

  /* Steal the buffer */
  SET_UNOP_AUX_item_pv(aux[0], SvPVX(prog)); SvLEN(prog) = 0;
  SvREFCNT_dec(prog);

  OP *retop = newUNOP_AUX(OP_CUSTOM, 0, NULL, aux);
  retop->op_ppaddr = &pp_multimath;
  retop->op_private = ntmps;
  retop->op_targ = final->op_targ;

  return retop;
#endif
}

void rpeep_for_callcompiled(pTHX_ OP *o, bool init_enabled);
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
  //int slowotick = 0;

  size_t depth = 0;
  int count = 0;
  OP *first = NULL;
  OP *firstprev = NULL;
  OP *oprev = NULL;
  const COP *last_cop = PL_curcop;
  DEBUG_u( PerlIO_printf(PerlIO_stderr(), "rpeep enabled %d\n",
                         enabled) );
  while(o && o != slowo) {
    if(o->op_type == OP_NEXTSTATE) {
      SV *sv = cop_hints_fetch_pvs(cCOPo, "Faster::Maths::CC/faster", 0);
      enabled = sv && sv != &PL_sv_placeholder && SvTRUE(sv);
      if (first && oprev && count > 1) {
        if (DebugFlags(CCDebugFlags::Debug)) {
          std::cerr << "Trace: calling code gen\n";
        }
        CodeFragment code{last_cop, o};
        compile_code(code, first, oprev, firstprev);
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
          CodeFragment code {last_cop, o};
          compile_code(code, first, oprev, firstprev);
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


}

void
register_fragments(pTHX_ const fragment_handler *frags,
                   size_t frag_count) {
  fragment_count = frag_count;
  fragments = frags;
  if (DebugFlags(CCDebugFlags::Register))
    std::cerr << "Registered " << frag_count << " handlers\n";
}

MODULE = Faster::Maths::CC    PACKAGE = Faster::Maths::CC

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
