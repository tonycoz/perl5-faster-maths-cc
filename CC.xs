/*  You may distribute under the terms of either the GNU General Public License
 *  or the Artistic License (the same terms as Perl itself)
 *
 *  (C) Paul Evans, 2021 -- leonerd@leonerd.org.uk
 */


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "docc.h"

MODULE = Faster::Maths::CC    PACKAGE = Faster::Maths::CC

PROTOTYPES: DISABLE

BOOT:
  fmcc::boot(aTHX);
