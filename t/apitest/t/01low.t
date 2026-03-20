#!perl
# lowest level APIs
use v5.42;
use Test2::V0;
use Faster::Maths::CC::TestAPI;

{
    my $x;
    cmp_ok(my_sv_2num(\$x), '==', 0+\$x, "my_sv_2num: bare ref");
    my $ov = OvNumOnly->new(123);
    is(my_sv_2num($ov), 123, "my_sv_2num: overloaded");
    is(my_sv_2num(~0), ~0, "my_sv_2num: large UV");
    is(my_sv_2num(0.1), 0.1, "my_sv_2num: float");
}

{
    no overloading; # prevent assertion
    my $x;
    cmp_ok(my_sv_2num_noov(\$x), '==', 0+\$x, "my_sv_2num_noov: bare ref");
    my $ov = OvNumOnly->new(123);
    cmp_ok(my_sv_2num_noov($ov), '==', 0+$ov, "my_sv_2num_noov: overloaded");
    isnt(my_sv_2num_noov($ov), 123, "my_sv_2num_noov: overloaded");
    is(my_sv_2num_noov(~0), ~0, "my_sv_2num_noov: large UV");
    is(my_sv_2num_noov(0.1), 0.1, "my_sv_2num_noov: float");
}

{
    # sanity check MG
    my $val;
    tie my $mg, "MG", \$val;
    $val = 1;
    is($mg, 1, "fetch");
    $mg = 2;
    is($mg, 2, "store");
}

{
    my $vala = 1;
    tie my $mga, "MG", \$vala;
    my $valb = 2;
    tie my $mgb, "MG", \$valb;
    my $valc;
    tie my $bgc, "MG", \$valc;
    my $out;
    my ($result, $left, $right);
        
    undef $out;
    ($result, $left, $right) = my_try_amagic_bin($out, $mga, $mgb, AMGf_numeric, false);
    is($out, undef, "no operation done");
    is($result, undef, "no overloading");
    is($left, $vala, "left unchanged");
    is($right, $valb, "right unchanged");

    $vala = OvNumOnly->new(10);
    $valb = OvNumOnly->new(12);
    undef $out;
    ($result, $left, $right) = my_try_amagic_bin($out, $mga, $mgb, AMGf_numeric, false);
    is($result, undef, "no + overloading");
    ok(!ref $left, "left no longer a ref");
    ok(!ref $right, "right no longer a ref");
    is($left, 10, "left turned into a number");
    is($right, 12, "right turning into a number");

    undef $vala;
    undef $valb;
    my @dummy = ($mga, $mgb); # invoke magic
    $vala = OvPlus->new(21);
    $valb = OvPlus->new(52);
    undef $out;
    ($result, $left, $right) = my_try_amagic_bin($out, $mga, $mgb, AMGf_numeric, false);
    ok(ref $left, "left still a reference");
    ok(ref $right, "right still a reference");
    is($left, $vala, "left unmodified");
    is($right, $valb, "right unmodified");
    isa_ok($result, "OvPlus");
    is("$result", "21+52", "overloaded addition result");
    is($out, undef, "out unmodified");

    undef $vala;
    undef $valb;
    @dummy = ($mga, $mgb); # invoke magic
    $vala = OvPlus->new(27);
    $valb = OvPlus->new(51);
    undef $out;
    ($result, $left, $right) = my_try_amagic_bin($out, $mga, $mgb, AMGf_numeric, true);
    ok(ref $left, "left still a reference");
    ok(ref $right, "right still a reference");
    is($left, $vala, "left unmodified");
    is($right, $valb, "right unmodified");
    isa_ok($result, "OvPlus");
    is("$result", "27+51", "overloaded addition result");
    is("$out", "27+51", "out updated");
    
}

done_testing;

package OvNumOnly {
    sub new ($class, $val) {
        bless \$val, $class;
    }
    use overload
        fallback => 1,
        '0+' => sub ($self, @) { $$self };
}

package OvPlus {
    sub new ($class, $val) {
        bless \$val, $class;
    }
    use overload
        fallback => 1,
        '""' => sub ($self, @) { $$self },
        '+' => sub ($left, $right, $swap) {
            __PACKAGE__->new("$$left+$$right");
        };
}

package MG {
    use parent 'Tie::Scalar';
    sub TIESCALAR ($class, $ref) {
        bless \$ref, $class;
    }
    sub FETCH ($self) {
        $$$self;
    }
    sub STORE ($self, $value) {
        $$$self = $value;
    }
}
