#!perl -w
use strict;
use ExtUtils::MakeMaker;
use File::Copy;

WriteMakefile(
    NAME         => 'Faster::Maths::CC::TestAPI',
    VERSION_FROM => 'TestAPI.pm',
    OBJECT       => 'TestAPI$(OBJ_EXT)',
    H            => [ qw(ppport.h header.h) ],
);

sub MY::postamble {
    my $self = shift;
    return <<"EOS";

header.h : ../../share/header.c
\t\$(PERL) -MExtUtils::Command -e cp ../../share/header.c header.h

EOS
}
