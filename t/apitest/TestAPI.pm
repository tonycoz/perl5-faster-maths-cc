package Faster::Maths::CC::TestAPI;
use v5.42;
use Exporter "import";

require XSLoader;
our $VERSION = "0.001";

XSLoader::load();

our @EXPORT =
    qw(my_sv_2num my_sv_2num_noov my_try_amagic_bin
       AMGf_numeric AMGf_unary AMGf_noright);

1;
