#!perl
# lowest level APIs
use v5.42;
use Test2::V0;
use Faster::Maths::CC::TestAPI;

{
    my $x;
    cmp_ok(my_sv_2num(\$x), '==', 0+\$x, "my_sv_2num: bare ref");
    my $ov = bless {}, "OV";
    is(my_sv_2num($ov), 123, "my_sv_2num: overloaded");
    is(my_sv_2num(~0), ~0, "my_sv_2num: large UV");
    is(my_sv_2num(0.1), 0.1, "my_sv_2num: float");
}

{
    no overloading; # prevent assertion
    my $x;
    cmp_ok(my_sv_2num_noov(\$x), '==', 0+\$x, "my_sv_2num_noov: bare ref");
    my $ov = bless {}, "OV";
    cmp_ok(my_sv_2num_noov($ov), '==', 0+$ov, "my_sv_2num_noov: overloaded");
    isnt(my_sv_2num_noov($ov), 123, "my_sv_2num_noov: overloaded");
    is(my_sv_2num_noov(~0), ~0, "my_sv_2num_noov: large UV");
    is(my_sv_2num_noov(0.1), 0.1, "my_sv_2num_noov: float");
}

done_testing;

package OV {
    use overload '0+' => sub { 123 };
}

