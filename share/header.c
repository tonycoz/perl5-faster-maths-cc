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
