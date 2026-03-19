#include "header.h"

MODULE = Faster::Maths::CC::TestAPI  PACKAGE = Faster::Maths::CC::TestAPI

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

PROTOTYPES: DISABLE

BOOT:
    1;

