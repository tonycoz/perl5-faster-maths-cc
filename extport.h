/* code that should be in ppport.h */
#pragma once

#if PERL_VERSION_GE(5,28,0)
#  define GET_UNOP_AUX_item_pv(aux)    ((aux).pv)
#  define SET_UNOP_AUX_item_pv(aux,v)  ((aux).pv = (v))
#else
#  define GET_UNOP_AUX_item_pv(aux)    INT2PTR(char *, (aux).uv)
#  define SET_UNOP_AUX_item_pv(aux,v)  ((aux).uv = PTR2UV(v))
#endif
