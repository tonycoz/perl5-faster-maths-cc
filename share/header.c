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

/* adapted from TARGi() */
static inline void
fast_sv_setiv(pTHX_ SV *sv, IV iv) {
    if (LIKELY(
               ((SvFLAGS(sv) & (SVTYPEMASK|SVf_THINKFIRST|SVf_IVisUV)) == SVt_IV))) {
        /* Cheap SvIOK_only().
         * Assert that flags which SvIOK_only() would test or
         * clear can't be set, because we're SVt_IV */
        assert(!(SvFLAGS(sv) &
                 (SVf_OOK|SVf_UTF8|(SVf_OK & ~(SVf_IOK|SVp_IOK)))));
        SvFLAGS(sv) |= (SVf_IOK|SVp_IOK);
        /* SvIV_set() where sv_any points to head */
        sv->sv_u.svu_iv = iv;
    }
    else
      sv_setiv_mg(sv, iv);
}

/* adapted from TARGn */
static inline void
fast_sv_setnv(pTHX_ SV *sv, NV n) {
    if (LIKELY(
               ((SvFLAGS(sv) & (SVTYPEMASK|SVf_THINKFIRST)) == SVt_NV))) {
        /* Cheap SvNOK_only().
         * Assert that flags which SvNOK_only() would test or
         * clear can't be set, because we're SVt_NV */
        assert(!(SvFLAGS(sv) &
                 (SVf_OOK|SVf_UTF8|(SVf_OK & ~(SVf_NOK|SVp_NOK)))));
        SvFLAGS(sv) |= (SVf_NOK|SVp_NOK);
        SvNV_set(sv, n);
    }
    else
        sv_setnv_mg(sv, n);
}

static inline bool
my_iv_add_may_overflow(IV il, IV ir, IV *result) {
#  if defined(I_STDCKDINT) && !IV_ADD_SUB_OVERFLOW_IS_EXPENSIVE
    return ckd_add(result, il, ir);
#  elif defined(HAS_BUILTIN_ADD_OVERFLOW) && !IV_ADD_SUB_OVERFLOW_IS_EXPENSIVE
    return __builtin_add_overflow(il, ir, result);
#  else
    /* topl and topr hold only 2 bits */
    PERL_UINT_FAST8_T const topl = ((UV)il) >> (UVSIZE * 8 - 2);
    PERL_UINT_FAST8_T const topr = ((UV)ir) >> (UVSIZE * 8 - 2);

    /* if both are in a range that can't under/overflow, do a simple integer
     * add: if the top of both numbers are 00  or 11, then it's safe */
    if (!( ((topl+1) | (topr+1)) & 2)) {
        *result = il + ir;
        return false;
    }
    return true;                   /* addition may overflow */
#  endif
}

static inline bool
my_lossless_NV_to_IV(NV nv, IV *ivp)
{
    /* This function determines if the input NV 'nv' may be converted without
     * loss of data to an IV.  If not, it returns FALSE taking no other action.
     * But if it is possible, it does the conversion, returning TRUE, and
     * storing the converted result in '*ivp' */

#  if defined(NAN_COMPARE_BROKEN) && defined(Perl_isnan)
    /* Normally any comparison with a NaN returns false; if we can't rely
     * on that behaviour, check explicitly */
    if (UNLIKELY(Perl_isnan(nv))) {
        return FALSE;
    }
#  endif

#  ifndef NV_PRESERVES_UV
    STATIC_ASSERT_STMT(((UV)1 << NV_PRESERVES_UV_BITS) - 1 <= (UV)IV_MAX);
#  endif

    /* Written this way so that with an always-false NaN comparison we
     * return false */
    if (
#  ifdef NV_PRESERVES_UV
        LIKELY(nv >= (NV) IV_MIN) && LIKELY(nv < IV_MAX_P1) &&
#  else
        /* If the condition below is not satisfied, lower bits of nv's
         * integral part is already lost and accurate conversion to integer
         * is impossible.
         * Note this should be consistent with S_sv_2iuv_common in sv.c. */
        Perl_fabs(nv) < (NV) ((UV)1 << NV_PRESERVES_UV_BITS) &&
#  endif
        (IV) nv == nv) {
        *ivp = (IV) nv;
        return TRUE;
    }
    return FALSE;
}

static void
do_add_raw(pTHX_ SV *out, SV *svl, SV *svr) {
    /* magic must have been called already */
    assert(!SvROK(svl));
    assert(!SvROK(svr));

#ifdef PERL_PRESERVE_IVUV
    if (!((svl->sv_flags|svr->sv_flags) & (SVf_IVisUV|SVs_GMG))) {
        IV il, ir;
        U32 flags = (svl->sv_flags & svr->sv_flags);
        if (flags & SVf_IOK) {
            /* both args are simple IVs */
            IV result;
            il = SvIVX(svl);
            ir = SvIVX(svr);
          do_iv:
            if (!my_iv_add_may_overflow(il, ir, &result)) {
                fast_sv_setiv(aTHX_ out, result); /* args not GMG, so can't be tainted */
                return;
            }
        }
        else if (flags & SVf_NOK) {
            /* both args are NVs */
            NV nl = SvNVX(svl);
            NV nr = SvNVX(svr);

            if (my_lossless_NV_to_IV(nl, &il) && my_lossless_NV_to_IV(nr, &ir)) {
                /* nothing was lost by converting to IVs */
                goto do_iv;
            }
            fast_sv_setnv(aTHX_ out, nl + nr); /* args not GMG, so can't be tainted */
            return;
        }
      
    }

    bool useleft = USE_LEFT(svl);
    NV nv;
    if (SvIV_please_nomg(svr)) {
        /* Unless the left argument is integer in range we are going to have to
           use NV maths. Hence only attempt to coerce the right argument if
           we know the left is integer.  */
        UV auv = 0;
        bool auvok = FALSE;
        bool a_valid = 0;

        if (!useleft) {
            auv = 0;
            a_valid = auvok = 1;
            /* left operand is undef, treat as zero. + 0 is identity,
               Could TARGi or TARGu right now, but space optimise by not
               adding lots of code to speed up what is probably a rare-ish
               case. */
        } else {
            /* Left operand is defined, so is it IV? */
            if (SvIV_please_nomg(svl)) {
                if ((auvok = SvIsUV(svl)))
                    auv = SvUVX(svl);
                else {
                    const IV aiv = SvIVX(svl);
                    if (aiv >= 0) {
                        auv = aiv;
                        auvok = 1;	/* Now acting as a sign flag.  */
                    } else {
                        auv = NEGATE_2UV(aiv);
                    }
                }
                a_valid = 1;
            }
        }
        if (a_valid) {
            bool result_good = 0;
            UV result;
            UV buv;
            bool buvok = SvIsUV(svr); /* svr is always IOK here */
        
            if (buvok)
                buv = SvUVX(svr);
            else {
                const IV biv = SvIVX(svr);
                if (biv >= 0) {
                    buv = biv;
                    buvok = 1;
                } else
                    buv = NEGATE_2UV(biv);
            }
            /* ?uvok if value is >= 0. basically, flagged as UV if it's +ve,
               else "IV" now, independent of how it came in.
               if a, b represents positive, A, B negative, a maps to -A etc
               a + b =>  (a + b)
               A + b => -(a - b)
               a + B =>  (a - b)
               A + B => -(a + b)
               all UV maths. negate result if A negative.
               add if signs same, subtract if signs differ. */

            if (auvok ^ buvok) {
                /* Signs differ.  */
                if (auv >= buv) {
                    result = auv - buv;
                    /* Must get smaller */
                    if (result <= auv)
                        result_good = 1;
                } else {
                    result = buv - auv;
                    if (result <= buv) {
                        /* result really should be -(auv-buv). as its negation
                           of true value, need to swap our result flag  */
                        auvok = !auvok;
                        result_good = 1;
                    }
                }
            } else {
                /* Signs same */
                result = auv + buv;
                if (result >= auv)
                    result_good = 1;
            }
            if (result_good) {
                if (auvok)
                    sv_setuv(out, result);
                else {
                    /* Negate result */
                    if (result <= ABS_IV_MIN)
                        fast_sv_setiv(aTHX_ out, NEGATE_2IV(result));
                    else {
                        /* result valid, but out of range for IV.  */
                        nv = -(NV)result;
                        goto ret_nv;
                    }
                }
                return;
            } /* Overflow, drop through to NVs.  */
        }
    }

#else
    useleft = USE_LEFT(svl);
#endif

    /* If left operand is undef, treat as zero. */
    nv = useleft ? SvNV_nomg(svl) : 0.0;
    /* Separate statements here to ensure SvNV_nomg(svl) is evaluated
       before SvNV_nomg(svr) */
    nv += SvNV_nomg(svr);
  ret_nv:
    fast_sv_setnv(aTHX_ out, nv);
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
