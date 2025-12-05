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

static inline SV *
my_sv_2num_noov(pTHX_ SV *sv) {
    if (!SvROK(sv))
        return sv;

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

static SV *
do_try_amagic_un(pTHX_ SV **psv, int method, int flags) {
    if (SvAMAGIC(*psv)) {
        OP *saved = PL_op; /* to get scalar context /cry */
        PL_op = NULL;
        SV *result = amagic_call(*psv, NULL, method,
                                 flags | AMGf_unary | AMGf_noright);
        PL_op = saved;
        if (result)
            return result;

        if (flags & AMGf_numeric) {
            *psv = my_sv_2num(aTHX_ *psv);
        }
    }
    return NULL;
}

PERL_STATIC_INLINE SV *
my_try_amagic_un(pTHX_ SV **psv, int method, int flags) {
    /* eventually this will happen during code gen */
    if (UNLIKELY(PL_hints & HINT_NO_AMAGIC))
        return NULL;
    return (UNLIKELY(((SvFLAGS(*psv)) & SVf_ROK)) == SVf_ROK)
      ? do_try_amagic_un(aTHX_ psv, method, flags) : NULL;
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

// adapted from TARGu()
static inline void
fast_sv_setuv(pTHX_ SV *sv, UV u) {
  if (LIKELY(
              ((SvFLAGS(sv) & (SVTYPEMASK|SVf_THINKFIRST|SVf_IVisUV)) == SVt_IV)
              && (u <= (UV)IV_MAX))) {
    /* Cheap SvIOK_only().
     * Assert that flags which SvIOK_only() would test or
     * clear can't be set, because we're SVt_IV */
    assert(!(SvFLAGS(sv) &
             (SVf_OOK|SVf_UTF8|(SVf_OK & ~(SVf_IOK|SVp_IOK)))));
    SvFLAGS(sv) |= (SVf_IOK|SVp_IOK);
    /* SvIV_set() where sv_any points to head */
    sv->sv_u.svu_iv = u;
  }
  else
    sv_setuv_mg(sv, u);
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
my_iv_sub_may_overflow(IV il, IV ir, IV *result) {
#  if defined(I_STDCKDINT) && !IV_ADD_SUB_OVERFLOW_IS_EXPENSIVE
#    return ckd_sub(result, il, ir)
#  elif defined(HAS_BUILTIN_SUB_OVERFLOW) && !IV_ADD_SUB_OVERFLOW_IS_EXPENSIVE
     return __builtin_sub_overflow(il, ir, result);
#  else
    PERL_UINT_FAST8_T const topl = ((UV)il) >> (UVSIZE * 8 - 2);
    PERL_UINT_FAST8_T const topr = ((UV)ir) >> (UVSIZE * 8 - 2);

    /* if both are in a range that can't under/overflow, do a simple integer
     * subtract: if the top of both numbers are 00  or 11, then it's safe */
    if (!( ((topl+1) | (topr+1)) & 2)) {
        *result = il - ir;
        return false;
    }
    return true;                   /* subtraction may overflow */
#endif
}

static inline bool
my_iv_mul_may_overflow(IV il, IV ir, IV *result) {
#if defined(I_STDCKDINT) && !IV_MUL_OVERFLOW_IS_EXPENSIVE
  return ckd_mul(result, il, ir)
#elif defined(HAS_BUILTIN_MUL_OVERFLOW) && !IV_MUL_OVERFLOW_IS_EXPENSIVE
    return __builtin_mul_overflow(il, ir, result);
#  else
    UV const topl = ((UV)il) >> (UVSIZE * 4 - 1);
    UV const topr = ((UV)ir) >> (UVSIZE * 4 - 1);

    /* if both are in a range that can't under/overflow, do a simple integer
     * multiply: if the top halves(*) of both numbers are 00...00  or 11...11,
     * then it's safe.
     * (*) for 32-bits, the "top half" is the top 17 bits,
     *     for 64-bits, its 33 bits */
    if (!(
              ((topl+1) | (topr+1))
            & ( (((UV)1) << (UVSIZE * 4 + 1)) - 2) /* 11..110 */
    )) {
        *result = il * ir;
        return false;
    }
    return true;                   /* multiplication may overflow */
#endif
}

PERL_STATIC_INLINE bool
my_uv_mul_overflow (UV auv, UV buv, UV *const result)
{
#  if defined(I_STDCKDINT)
  return ckd_mul(result, auv, buv);
#  elif defined(HAS_BUILTIN_MUL_OVERFLOW)
  return __builtin_mul_overflow(auv, buv, result);
#  else
    const UV topmask = (~ (UV)0) << (4 * sizeof (UV));
    const UV botmask = ~topmask;

#    if UVSIZE > LONGSIZE && UVSIZE <= 2 * LONGSIZE
    /* If UV is double-word integer, declare these variables as single-word
       integers to help compiler to avoid double-word multiplication.  */
    unsigned long alow, ahigh, blow, bhigh;
#    else
    UV alow, ahigh, blow, bhigh;
#    endif

    /* If this does sign extension on unsigned it's time for plan B  */
    ahigh = auv >> (4 * sizeof (UV));
    alow  = auv & botmask;
    bhigh = buv >> (4 * sizeof (UV));
    blow  = buv & botmask;

    if (ahigh && bhigh)
        /* eg 32 bit is at least 0x10000 * 0x10000 == 0x100000000
           which is overflow.  */
        return true;

    UV product_middle = 0;
    if (ahigh || bhigh) {
        /* One operand is large, 1 small */
        /* Either ahigh or bhigh is zero here, so the addition below
           can't overflow.  */
        product_middle = (UV)ahigh * blow + (UV)alow * bhigh;
        if (product_middle & topmask)
            return true;
        /* OK, product_middle won't lose bits when we shift it.  */
        product_middle <<= 4 * sizeof (UV);
    }
    /* else: eg 32 bit is at most 0xFFFF * 0xFFFF == 0xFFFE0001
       so the unsigned multiply cannot overflow.  */

    /* (UV) cast below is necessary to force the multiplication to produce
       UV result, as alow and blow might be narrower than UV */
    UV product_low = (UV)alow * blow;
    return my_uv_add_overflow(product_middle, product_low, result);
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

static inline void
do_add_noov(pTHX_ SV *out, SV *svl, SV *svr) {
    SvGETMAGIC(svl);
    if (svl != svr)
        SvGETMAGIC(svr);
    svl = my_sv_2num_noov(aTHX_ svl);
    svr = my_sv_2num_noov(aTHX_ svr);
    do_add_raw(aTHX_ out, svl, svr);
}

static void
do_subtract_raw(pTHX_ SV *out, SV *svl, SV *svr) {
    NV nv;

#ifdef PERL_PRESERVE_IVUV

    /* special-case some simple common cases */
    if (!((svl->sv_flags|svr->sv_flags) & (SVf_IVisUV|SVs_GMG))) {
        IV il, ir;
        U32 flags = (svl->sv_flags & svr->sv_flags);
        if (flags & SVf_IOK) {
            /* both args are simple IVs */
            IV result;
            il = SvIVX(svl);
            ir = SvIVX(svr);
          do_iv:
            if (!my_iv_sub_may_overflow(il, ir, &result)) {
                fast_sv_setiv(aTHX_ out, result); /* args not GMG, so can't be tainted */
                return;
            }
            goto generic;
        }
        else if (flags & SVf_NOK) {
            /* both args are NVs */
            NV nl = SvNVX(svl);
            NV nr = SvNVX(svr);

            if (my_lossless_NV_to_IV(nl, &il) && my_lossless_NV_to_IV(nr, &ir)) {
                /* nothing was lost by converting to IVs */
                goto do_iv;
            }
            fast_sv_setnv(aTHX_ out, nl - nr); /* args not GMG, so can't be tainted */
            return;
        }
    }

  generic:

    bool useleft = USE_LEFT(svl);
    /* See comments in pp_add (in pp_hot.c) about Overflow, and how
       "bad things" happen if you rely on signed integers wrapping.  */
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
            /* left operand is undef, treat as zero.  */
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
               a - b =>  (a - b)
               A - b => -(a + b)
               a - B =>  (a + b)
               A - B => -(a - b)
               all UV maths. negate result if A negative.
               subtract if signs same, add if signs differ. */

            if (auvok ^ buvok) {
                /* Signs differ.  */
                result = auv + buv;
                if (result >= auv)
                    result_good = 1;
            } else {
                /* Signs same */
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
            }
            if (result_good) {
                if (auvok)
                    sv_setuv(out, result);
                else {
                    /* Negate result */
                    if (result <= ABS_IV_MIN)
                        sv_setiv(out, NEGATE_2IV(result));
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

    /* If left operand is undef, treat as zero - value */
    nv = useleft ? SvNV_nomg(svl) : 0.0;
    /* Separate statements here to ensure SvNV_nomg(svl) is evaluated
       before SvNV_nomg(svr) */
    nv -= SvNV_nomg(svr);
  ret_nv:
    sv_setnv(out, nv);
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

static inline void
do_subtract_noov(pTHX_ SV *out, SV *svl, SV *svr) {
    SvGETMAGIC(svl);
    if (svl != svr)
        SvGETMAGIC(svr);
    svl = my_sv_2num_noov(aTHX_ svl);
    svr = my_sv_2num_noov(aTHX_ svr);
    do_subtract_raw(aTHX_ out, svl, svr);
}

static void
do_multiply_raw(pTHX_ SV *out, SV *svl, SV *svr) {
#ifdef PERL_PRESERVE_IVUV
    /* special-case some simple common cases */
    if (!((svl->sv_flags|svr->sv_flags) & (SVf_IVisUV|SVs_GMG))) {
        IV il, ir;
        U32 flags = (svl->sv_flags & svr->sv_flags);
        if (flags & SVf_IOK) {
            /* both args are simple IVs */
            IV result;
            il = SvIVX(svl);
            ir = SvIVX(svr);
          do_iv:
            if (!my_iv_mul_may_overflow(il, ir, &result)) {
              fast_sv_setiv(aTHX_ out, result);
              return;
            }
        }
        else if (flags & SVf_NOK) {
            /* both args are NVs */
            NV nl = SvNVX(svl);
            NV nr = SvNVX(svr);
            NV result;

            if (my_lossless_NV_to_IV(nl, &il) && my_lossless_NV_to_IV(nr, &ir)) {
                /* nothing was lost by converting to IVs */
                goto do_iv;
            }
            result = nl * nr;
#  if defined(__sgi) && defined(USE_LONG_DOUBLE) && LONG_DOUBLEKIND == LONG_DOUBLE_IS_DOUBLEDOUBLE_128_BIT_BE_BE && NVSIZE == 16
            if (Perl_isinf(result)) {
                Zero((U8*)&result + 8, 8, U8);
            }
#  endif
            fast_sv_setnv(aTHX_ out, result);
            return;
        }
    }

    if (SvIV_please_nomg(svr)) {
        /* Unless the left argument is integer in range we are going to have to
           use NV maths. Hence only attempt to coerce the right argument if
           we know the left is integer.  */
        /* Left operand is defined, so is it IV? */
        if (SvIV_please_nomg(svl)) {
            bool auvok = SvIsUV(svl);
            bool buvok = SvIsUV(svr);
            UV alow;
            UV blow;
            UV product;

            if (auvok) {
                alow = SvUVX(svl);
            } else {
                const IV aiv = SvIVX(svl);
                if (aiv >= 0) {
                    alow = aiv;
                    auvok = TRUE; /* effectively it's a UV now */
                } else {
                    /* abs, auvok == false records sign */
                    alow = NEGATE_2UV(aiv);
                }
            }
            if (buvok) {
                blow = SvUVX(svr);
            } else {
                const IV biv = SvIVX(svr);
                if (biv >= 0) {
                    blow = biv;
                    buvok = TRUE; /* effectively it's a UV now */
                } else {
                    /* abs, buvok == false records sign */
                    blow = NEGATE_2UV(biv);
                }
            }

            if (!my_uv_mul_overflow(alow, blow, &product)) {
                if (auvok == buvok) {
                    /* -ve * -ve or +ve * +ve gives a +ve result.  */
                  sv_setuv(out, product);
                  return;
                } else if (product <= ABS_IV_MIN) {
                    /* -ve result, which could overflow an IV  */
                  sv_setiv(out, NEGATE_2IV(product));
                  return;
                } /* else drop to NVs below. */
            } /* ahigh && bhigh */
        } /* SvIOK(svl) */
    } /* SvIOK(svr) */
#endif
    {
      NV left  = SvNV_nomg(svl);
      NV right = SvNV_nomg(svr);
      NV result = left * right;

#if defined(__sgi) && defined(USE_LONG_DOUBLE) && LONG_DOUBLEKIND == LONG_DOUBLE_IS_DOUBLEDOUBLE_128_BIT_BE_BE && NVSIZE == 16
      if (Perl_isinf(result)) {
          Zero((U8*)&result + 8, 8, U8);
      }
#endif
      sv_setnv(out, result);
      return;
    }
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

static inline void
do_multiply_noov(pTHX_ SV *out, SV *svl, SV *svr) {
    SvGETMAGIC(svl);
    if (svl != svr)
        SvGETMAGIC(svr);
    svl = my_sv_2num_noov(aTHX_ svl);
    svr = my_sv_2num_noov(aTHX_ svr);
    do_multiply_raw(aTHX_ out, svl, svr);
}

static void
do_divide_raw(pTHX_ SV *out, SV *svl, SV *svr) {
    /* Only try to do UV divide first
       if ((SLOPPYDIVIDE is true) or
           (PERL_PRESERVE_IVUV is true and one or both SV is a UV too large
            to preserve))
       The assumption is that it is better to use floating point divide
       whenever possible, only doing integer divide first if we can't be sure.
       If NV_PRESERVES_UV is true then we know at compile time that no UV
       can be too large to preserve, so don't need to compile the code to
       test the size of UVs.  */

#if defined(SLOPPYDIVIDE) || (defined(PERL_PRESERVE_IVUV) && !defined(NV_PRESERVES_UV))
#  define PERL_TRY_UV_DIVIDE
    /* ensure that 20./5. == 4. */
#endif

#ifdef PERL_TRY_UV_DIVIDE
    if (SvIV_please_nomg(svr) && SvIV_please_nomg(svl)) {
            bool left_non_neg = SvIsUV(svl);
            bool right_non_neg = SvIsUV(svr);
            UV left;
            UV right;

            if (right_non_neg) {
                right = SvUVX(svr);
            }
            else {
                const IV biv = SvIVX(svr);
                if (biv >= 0) {
                    right = biv;
                    right_non_neg = TRUE; /* effectively it's a UV now */
                }
                else {
                    right = NEGATE_2UV(biv);
                }
            }
            /* historically undef()/0 gives a "Use of uninitialized value"
               warning before dieing, hence this test goes here.
               If it were immediately before the second SvIV_please, then
               DIE() would be invoked before left was even inspected, so
               no inspection would give no warning.  */
            if (right == 0)
                croak("Illegal division by zero");

            if (left_non_neg) {
                left = SvUVX(svl);
            }
            else {
                const IV aiv = SvIVX(svl);
                if (aiv >= 0) {
                    left = aiv;
                    left_non_neg = TRUE; /* effectively it's a UV now */
                }
                else {
                    left = NEGATE_2UV(aiv);
                }
            }

            if (left >= right
#ifdef SLOPPYDIVIDE
                /* For sloppy divide we always attempt integer division.  */
#else
                /* Otherwise we only attempt it if either or both operands
                   would not be preserved by an NV.  If both fit in NVs
                   we fall through to the NV divide code below.  However,
                   as left >= right to ensure integer result here, we know that
                   we can skip the test on the right operand - right big
                   enough not to be preserved can't get here unless left is
                   also too big.  */

                && (left > ((UV)1 << NV_PRESERVES_UV_BITS))
#endif
                ) {
                /* Integer division can't overflow, but it can be imprecise.  */

                /* Modern compilers optimize division followed by
                 * modulo into a single div instruction */
                const UV result = left / right;
                if (left % right == 0) {
                    /* result is valid */
                    if (left_non_neg == right_non_neg) {
                        /* signs identical, result is positive.  */
                      fast_sv_setuv(aTHX_ out, result);
                      return;
                    }
                    /* 2s complement assumption */
                    if (result <= ABS_IV_MIN)
                      fast_sv_setiv(aTHX_ out, NEGATE_2IV(result));
                    else {
                        /* It's exact but too negative for IV. */
                      fast_sv_setnv(aTHX_ out, -(NV)result);
                    }
                    return;
                } /* tried integer divide but it was not an integer result */
            } /* else (PERL_ABS(result) < 1.0) or (both UVs in range for NV) */
    } /* one operand wasn't SvIOK */
#endif /* PERL_TRY_UV_DIVIDE */
    {
        NV left  = SvNV_nomg(svl);
        NV right = SvNV_nomg(svr);
#if defined(NAN_COMPARE_BROKEN) && defined(Perl_isnan)
        if (! Perl_isnan(right) && right == 0.0)
#else
        if (right == 0.0)
#endif
            croak("Illegal division by zero");
        fast_sv_setnv(aTHX_ out, left / right);
    }
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

static inline void
do_divide_noov(pTHX_ SV *out, SV *svl, SV *svr) {
    SvGETMAGIC(svl);
    if (svl != svr)
        SvGETMAGIC(svr);
    svl = my_sv_2num_noov(aTHX_ svl);
    svr = my_sv_2num_noov(aTHX_ svr);
    do_divide_raw(aTHX_ out, svl, svr);
}

static bool
my_negate_string(pTHX_ SV *out, SV *sv) {
    /* based on S_negate_string() in pp.c */
    assert(SvPOKp(sv));
    if (SvNIOK(sv) || (!SvPOK(sv) && SvNIOKp(sv)))
        return false;

    STRLEN len;
    const char *s = SvPV_nomg_const(sv, len);
    if (isIDFIRST(*s)) {
        if (LIKELY(out != sv)) {
            sv_setpvs(out, "-");
            sv_catsv(out, sv);
        } else {
            sv_insert_flags(out, 0, 0, "-", 1, 0);
        }
    }
    else if (*s == '+' || (*s == '-' && !looks_like_number(sv))) {
        sv_setsv_nomg(out, sv);
        *SvPV_force_nomg(out, len) = *s == '-' ? '+' : '-';
    }
    else
        return false;
    SvSETMAGIC(out);
    return true;
}

static void
do_negate_low(pTHX_ SV *out, SV *sv) {
    /* magic should already be called */
    /* overloading (including sv_2num() if overloading is disabled)
       should already have been resolved
    */
    /* based on pp_negate */
    assert(!SvROK(sv));
    if (SvPOKp(sv) && my_negate_string(aTHX_ out, sv))
        return;

    {

        if (SvIOK(sv)) {
            /* It's publicly an integer */
        oops_its_an_int:
            if (SvIsUV(sv)) {
                if (SvUVX(sv) <= ABS_IV_MIN) {
                    fast_sv_setiv(aTHX_ out, NEGATE_2IV(SvUVX(sv)));
                    return;
                }
            }
#ifdef PERL_PRESERVE_IVUV
            else if (SvIVX(sv) < 0) {
                fast_sv_setuv(aTHX_ out, NEGATE_2UV(SvIVX(sv)));
                return;
            }
            else {
                fast_sv_setiv(aTHX_ out, -SvIVX(sv));
                return;
            }
#else
            else if (SvIVX(sv) != IV_MIN) {
                fast_sv_setiv(aTHX_ out, -SvIVX(sv));
                return;
            }
#endif
        }
        if (SvNIOKp(sv) && (SvNIOK(sv) || !SvPOK(sv)))
            fast_sv_setnv(aTHX_ out, -SvNV_nomg(sv));
        else if (SvPOKp(sv) && SvIV_please_nomg(sv))
                  goto oops_its_an_int;
        else
            fast_sv_setnv(aTHX_ out, -SvNV_nomg(sv));
    }
}

static inline SV *
do_negate(pTHX_ SV *out, SV *sv) {
  SvGETMAGIC(sv);
  SV *result = my_try_amagic_un(aTHX_ &sv, neg_amg, AMGf_numeric);
  if (result)
    return result;

  do_negate_low(aTHX_ out, sv);
  return out;
}

/* API END */
