#include "header.h"

MODULE = Faster::Maths::CC::TestAPI  PACKAGE = Faster::Maths::CC::TestAPI

PROTOTYPES: DISABLE

SV *
my_sv_2num(SV *sv)
  CODE:
    // can return the supplied SV, so return a copy
    // XS will mortalize it
    RETVAL = newSVsv(my_sv_2num(aTHX_ sv));
  OUTPUT: RETVAL

SV *
my_sv_2num_noov(SV *sv)
  CODE:
    // can return the supplied SV, so return a copy
    // XS will mortalize it
    RETVAL = newSVsv(my_sv_2num_noov(aTHX_ sv));
  OUTPUT: RETVAL

void
my_try_amagic_bin(SV *out, SV *left, SV *right, int flags, bool mutator)
  PPCODE:
    SV *result = my_try_amagic_bin(aTHX_ out, &left, &right, add_amg,
                                   flags, mutator);
    EXTEND(SP, 3);
    PUSHs(result ? sv_mortalcopy(result) : &PL_sv_undef);
    PUSHs(sv_mortalcopy(left));
    PUSHs(sv_mortalcopy(right));

U32
AMGf_numeric()
  PROTOTYPE:
  ALIAS:
    AMGf_numeric = AMGf_numeric
    AMGf_unary = AMGf_unary
    AMGf_noright = AMGf_noright
  CODE:
    RETVAL = ix;
  OUTPUT: RETVAL

BOOT:
    1;

