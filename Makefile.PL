#!perl -w
use strict;
use ExtUtils::MakeMaker 6.46;
use Config;
use ExtUtils::CppGuess;
use 5.022;

my %opts = 
  (
   NAME => 'Faster::Maths::CC',
   VERSION_FROM => 'lib/Faster/Maths/CC.pm',
   OBJECT => 'CC$(OBJ_EXT)',
   LICENSE => "perl_5",
   AUTHOR => 'Tony Cook <tony@develop-help.com>',
   ABSTRACT => 'Compile perl code fragments to C (eventually)',
   META_MERGE =>
   {
     'meta-spec' =>
     {
       version => "2",
       url => "https://metacpan.org/pod/CPAN::Meta::Spec",
     },
     resources =>
     {
       homepage => "http://github.com/tonycoz/perl5-faster-maths-cc/",
       repository =>
       {
         type => "git",
         url => "https://github.com/tonycoz/perl5-faster-maths-cc.git",
         web => "https://github.com/tonycoz/perl5-faster-maths-cc/",
       },
       bugtracker =>
       {
         web => "https://github.com/tonycoz/perl5-faster-maths-cc/",
       },
     },
   },
  );


$opts{META_MERGE}{prereqs} =
  {
    configure =>
    {
      requires =>
      {
        "ExtUtils::MakeMaker" => "6.46",
        "ExtUtils::CppGuess" => 0,
      },
    },
    build =>
    {
      requires =>
      {
        "Test::More" => "0.47",
        perl => "5.022",
      }
    },
    runtime =>
    {
      requires =>
      {
      }
    },
    test =>
    {
      requires =>
      {
        "Test::More" => "0.47",
      }
    },
  };
$opts{PREREQ_PM} =
  {
    XSLoader => 0,
  };

my $guess = ExtUtils::CppGuess->new;

my $std = $guess->cpp_standard_flag("C++23");
$guess->add_extra_compiler_flags($std);

WriteMakefile
  (
    %opts,
    $guess->makemaker_options,
   );
