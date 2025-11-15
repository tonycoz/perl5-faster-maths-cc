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
#include <print>

// lazy for now
//#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include "cpputil.h"

enum class CCDebugFlags {
  DumpStack = 0x0001,
  DumpCode  = 0x0002,
  TraceOps  = 0x0004,
};

using CCDebugBits = BitSet<CCDebugFlags>;

static CCDebugBits DebugFlags;

static void
init_debug_flags() {
  const char *env = getenv("PERL_MFC_DEBUG");
  if (env) {
    while (*env) {
      switch (*env) {
      case 'c': DebugFlags |= CCDebugFlags::DumpCode;  break;
      case 's': DebugFlags |= CCDebugFlags::DumpStack; break;
      case 'o': DebugFlags |= CCDebugFlags::TraceOps;  break;
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

namespace {

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
  sv_dump(psv.sv);
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

std::ostream &
operator <<(std::ostream &out, SV *sv) {
  out << SvPV_nolen(sv);
  return out;
}

std::ostream &
operator <<(std::ostream &out, const Stack &s) {
  for (auto i : s) {
      out << i << ' ';
  }
  return out;
}

}

#if 0

struct Code {
  struct Entry {
    std::string name;
    std::vector<OP*> ops;
    ostringstream code;
  };

  int index;
  std::vector<Entry> Code;

  void
  add_binop(char type, Stack &stack, OP *o) {
    auto left = stack.back(); // ugly, but std::stack is too
    stack.pop_back();
    auto right = stack.back();
    stack.pop_back();
    auto out = o->op_flags & OPf_STACKED ? left : PadSv{o->op_targ};

    std::ostringstream s;
    s << "sv_setnv(" << out << ", SvNV(" << left
      << ") " << type << " SvNV(" << right << "));\n";
    Code.emplace_back(Entry{std::string{1, type}, {}, s.str()});
    std::cout << s.str() << std::endl;
  }
};

#endif

static XOP xop_callcompiled;
static OP *pp_callcompiled(pTHX)
{
  dSP;
  abort(); // nothing yet
  RETURN;
}

static void
add_code(pTHX_ const char *name, SV *out) {
  HV *code_hv = get_hv("Faster::Maths::CC::code", 0);
  assert(code_hv);
  SV **code_sv = hv_fetch(code_hv, name, strlen(name), 0);
  if (!code_sv)
    Perl_croak(aTHX_ "Cannot find code %s", name);

  sv_catsv(out, *code_sv);
}

#define compile_code(code, start, final) \
  MY_compile_code(aTHX_ start, final)
static OP *
MY_compile_code(pTHX_ OP *start, OP *final)
{
  OP *o;
  /* Phase 1: just count the number of aux items we need
   * We'll need one for every constant or padix
   * Also count the maximum stack height
   */

  Stack stack;
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
          
          std::cout << "sv_setnv(" << out << ", "
                    << left << " + " << right << ");\n";
          stack.emplace_back(out);
          //code.add_binop('+', stack, o);
        }
        break;

      default:
        croak("ARGH unsure how to optimize this op\n");
    }

    if(o == final)
      break;
  }
  std::cout << "Stack: " << stack << "\n";

  return o;

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

static void rpeep_for_callcompiled(pTHX_ OP *o, bool init_enabled);
static void
rpeep_for_callcompiled(pTHX_ OP *o, bool init_enabled)
{
  bool enabled = init_enabled;

  OP *prevo = NULL;

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
  OP *oprev = NULL;
  DEBUG_u( PerlIO_printf(PerlIO_stderr(), "rpeep enabled %d\n",
                         enabled) );
  while(o && o != slowo) {
    if(o->op_type == OP_NEXTSTATE) {
      SV *sv = cop_hints_fetch_pvs(cCOPo, "Faster::Maths::CC/faster", 0);
      enabled = sv && sv != &PL_sv_placeholder && SvTRUE(sv);
      if (first && oprev && count > 1)
        compile_code(code, first, oprev);
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
        if (first && oprev && count > 1)
          compile_code(code, first, oprev);
        first = o->op_next;
        count = 0;
        break;
      }
    }
    oprev = o;
    o = o->op_next;
  }
}

static void (*next_rpeepp)(pTHX_ OP *o);

static void
my_rpeepp(pTHX_ OP *o)
{
  if(!o)
    return;

  (*next_rpeepp)(aTHX_ o);

  rpeep_for_callcompiled(aTHX_ o, false);
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
