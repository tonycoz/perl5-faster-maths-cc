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
};

using CCDebugBits = BitSet<CCDebugFlags>;

CCDebugBits DebugFlags;

IV CodeIndex;

typedef void (*fragment_handler)(pTHX);

const fragment_handler *fragments;
size_t fragment_count;

void
init_debug_flags() {
  const char *env = getenv("PERL_MFC_DEBUG");
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
      }
      ++env;
    }
  }
}

struct PadSv {
  PADOFFSET index = 0;
};

struct ConstSv {
  SV *sv = nullptr;
};

using ArgType = std::variant<PadSv, ConstSv>;

struct RawNumber {
  NV num = 0.0;
};

using NumArg = std::variant<ArgType, RawNumber>;

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
    std::visit(overloaded {
        [&](const ConstSv &sv) { return NumArg{RawNumber{SvNV(sv.sv)}}; },
        [&](const PadSv &psv) {
          SV *sv = PAD_SV(psv.index);
          return SvREADONLY(sv) ? NumArg{RawNumber{SvNV(sv)}} : NumArg(arg);
        }
      }, arg);
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
operator <<(std::ostream &out, const ConstSv &psv) {
  out << "SomeSV /* " << (void *)psv.sv << " */";
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

/* Used to generate code for an op tree fragment */
struct CodeFragment {
  CodeFragment(const COP *cop):
    line(CopLINE(cop)), file(CopFILE(cop)) {
  }
  std::ostringstream code;
  //std::vector<OP*> ops;
  //CodeResult result;
  line_t line = 0;
  const char *file = 0;
};

// I wanted to make the inserter below check the v was insertable
// but got compilation failures and couldn't figure it out
template <typename T>
concept Insertable = requires (T a) {
  { std::declval<std::ostream>() << a };//->std::convertible_to<std::ostream &>;
};

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
  UNOP_AUX_item *aux = cUNOP_AUX->op_aux;
  UV index = aux->uv;
  if (index >= fragment_count) {
    if (DebugFlags(CCDebugFlags::Run))
      std::cerr << "could not run " << (void*)PL_op
                << ": high index " << index << "\n";
    return NORMAL; // use the old
  }

  if (DebugFlags(CCDebugFlags::TraceFrags)) {
    std::cerr << "calling fragment " << index << "\n";
  }
  fragments[index](aTHX);

  // skip the old op tree
  return OpSIBLING(PL_op)->op_next;
}

#if 0

void
add_code(pTHX_ const char *name, SV *out) {
  HV *code_hv = get_hv("Faster::Maths::CC::code", 0);
  assert(code_hv);
  SV **code_sv = hv_fetch(code_hv, name, strlen(name), 0);
  if (!code_sv)
    Perl_croak(aTHX_ "Cannot find code %s", name);

  sv_catsv(out, *code_sv);
}

#endif

void
code_finalize(pTHX_ CodeFragment &code, Stack &stack, OP *start, OP *final) {
  // no result?
  if (stack.size() != 1) {
    if (DebugFlags(CCDebugFlags::Failures)) {
      std::cerr << "Failed to finalize " << stack.size() << " values left on stack\n";
    }
    return;
  }
  auto top = stack.back();
  stack.pop_back();
  // this may need to change
  code << "rpp_extend(1);\n";
  code << "rpp_push_1(" << top << ");\n";

  IV index = CodeIndex++;
  SV *out = Perl_newSVpvf(aTHX_ "static void\nf%" UVf "(pTHX) {\n", index);
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

  // we don't really need an UNOP_AUX yet, but I expect we will later
  UNOP_AUX_item *aux;
  Newx(aux, 1, UNOP_AUX_item);
  aux->iv = index;
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
  assert(oprev == nullptr || oprev->op_next == start);
  if (DebugFlags(CCDebugFlags::Debug)) {
    std::cerr << "insertion parent " << (void*)parent
              << " after " << (void *)oprev
              << " start " << (void *)start
              << " final " << (void *)final << "\n";
  }

  op_sibling_splice(parent, oprev, 0, retop);
  oprev->op_next = retop;
}

#define compile_code(code, start, final) \
  MY_compile_code(aTHX_ code, start, final)
void
MY_compile_code(pTHX_ CodeFragment &code, OP *start, OP *final)
{
  OP *o;
  /* Phase 1: just count the number of aux items we need
   * We'll need one for every constant or padix
   * Also count the maximum stack height
   */

  Stack stack;
  OP *oprev = NULL;
  for(o = start; o; o = o->op_next) {
    if (DebugFlags(CCDebugFlags::DumpStack))
      std::cerr << "Stack: " << stack << "\n";
    if (DebugFlags(CCDebugFlags::TraceOps))
      std::cerr << "Op: " << OP_NAME(o) << "\n";
    switch(o->op_type) {
      case OP_CONST:
        stack.emplace_back(ConstSv{cSVOPo->op_sv});
        break;

      case OP_PADSV:
        stack.emplace_back(PadSv{o->op_targ});
        break;

      case OP_ADD:
        {
          auto right = as_number(stack.back());
          stack.pop_back();
          auto raw_left = stack.back();
          auto left = as_number(raw_left);
          stack.pop_back();
          auto out = o->op_flags & OPf_STACKED ? raw_left : PadSv{o->op_targ};
          
          code << "sv_setnv(" << out << ", "
                    << left << " + " << right << ");\n";
          stack.emplace_back(out);
          //code.add_binop('+', stack, o);
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

  code_finalize(aTHX_ code, stack, start, oprev);
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
  OP *oprev = NULL;
  const COP *last_cop = PL_curcop;
  DEBUG_u( PerlIO_printf(PerlIO_stderr(), "rpeep enabled %d\n",
                         enabled) );
  while(o && o != slowo) {
    if(o->op_type == OP_NEXTSTATE) {
      SV *sv = cop_hints_fetch_pvs(cCOPo, "Faster::Maths::CC/faster", 0);
      enabled = sv && sv != &PL_sv_placeholder && SvTRUE(sv);
      if (first && oprev && count > 1) {
        CodeFragment code{last_cop};
        compile_code(code, first, oprev);
      }
      last_cop = (const COP *)last_cop;
      first = o->op_next;
      count = 0;
      DEBUG_u( PerlIO_printf(PerlIO_stderr(), "nextstate %p line %d enabled %d\n",
                             o, CopLINE(cCOPo), enabled) );
    }
    if (enabled) {
      DEBUG_u( PerlIO_printf(PerlIO_stderr(), "op %d (%s) depth %zu count %d\n",
                             o->op_type, OP_NAME(o), depth, count) );
      switch(o->op_type) {
      case OP_CONST:
      case OP_PADSV:
        ++depth;
        break;

      case OP_ADD:
        if (o->op_flags & OPf_STACKED)
          ++depth; // left arg on stack (OP= operator)
        if (depth >= 2) {
          ++count;
          --depth;
        }
        else {
          depth = 0;
          first = NULL;
        }
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
        if (first && oprev && count > 1) {
          CodeFragment code {last_cop};
          compile_code(code, first, oprev);
        }
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
  Perl_custom_op_register(aTHX_ &pp_callcompiled, &xop_callcompiled);
  (void) hv_stores(PL_modglobal, "Faster::Maths::CC::register",
                            newSViv(PTR2IV(register_fragments)));
  // FIXME: hook PL_opfreehook to clean up aux items
