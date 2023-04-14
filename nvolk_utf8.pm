#
# nvolk_utf8.pm - utf8 normalizations
#
use strict;




sub unicode_fixes2($$) {
  # Finns use char+diacritic version of various characters
  my ( $str, $warn ) = @_;
  my $orig_str = $str;

  my @debug_stack = ();
  # a #
  #if ( $str =~ s/ầ/ầ/g ) { $debug_stack[$#debug_stack+1] = "a-multiple"; }

  if ( $str =~ s/á/á/g ) { $debug_stack[$#debug_stack+1] = "a-acute"; }

  if ( $str =~ s/ă/ă/g ) { $debug_stack[$#debug_stack+1] = "a-breve"; }
  if ( $str =~ s/â/â/g ) { $debug_stack[$#debug_stack+1] = "a-creve"; }
  if ( $str =~ s/à/à/g ) { $debug_stack[$#debug_stack+1] = "a-grave"; }
  if ( $str =~ s/ä/ä/g ) { $debug_stack[$#debug_stack+1] = "a-umlaut"; }


  if ( $str =~ s/å/å/g ) { $debug_stack[$#debug_stack+1] = "a-ring"; }
  if ( $str =~ s/ã/ã/g ) { $debug_stack[$#debug_stack+1] = "a-tilde"; }
  # A #
  if ( $str =~ s/Á/Á/g ) { $debug_stack[$#debug_stack+1] = "A-acute"; }
  if ( $str =~ s/À/À/g ) { $debug_stack[$#debug_stack+1] = "A-grave"; }
  if ( $str =~ s/Ä/Ä/g ) { $debug_stack[$#debug_stack+1] = "A-umlaut"; }

  if ( $str =~ s/Å/Å/g ) { $debug_stack[$#debug_stack+1] = "A-ring"; }
  if ( $str =~ s/Â/Â/g ) { $debug_stack[$#debug_stack+1] = "A-creve"; }
  
  if ( $str =~ s/ā/ā/g ) { $debug_stack[$#debug_stack+1] = "a-line"; }

  if ( $str =~s/ą/ą/g ) { $debug_stack[$#debug_stack+1] = "a-ogonek"; }


  if ( $str =~ s/ć/ć/g ) { $debug_stack[$#debug_stack+1] = "c-acute"; }
  if ( $str =~ s/č/č/g  ) { $debug_stack[$#debug_stack+1] = "c-caron"; }
  if ( $str =~ s/Č/Č/g  ) { $debug_stack[$#debug_stack+1] = "C-caron"; }
  if ( $str =~ s/ç/ç/g ) { $debug_stack[$#debug_stack+1] = "c-cedilla"; }

  if ( $str =~ s/ḍ/ḍ/g ) { $debug_stack[$#debug_stack+1] = "d-dot"; }
  # e #
  if ( $str =~ s/é/é/g ) { $debug_stack[$#debug_stack+1] = "e-acute"; }
  if ( $str =~ s/É/É/g ) { $debug_stack[$#debug_stack+1] = "E-acute"; }
  if ( $str =~ s/è/è/g ) { $debug_stack[$#debug_stack+1] = "e-grave"; }
  if ( $str =~ s/È/È/g ) { $debug_stack[$#debug_stack+1] = "E-grave"; }
  if ( $str =~ s/ê/ê/g ) { $debug_stack[$#debug_stack+1] = "e-circum"; }
  if ( $str =~ s/ē/ē/g ) { $debug_stack[$#debug_stack+1] = "e-line"; }
  if ( $str =~ s/ė/ė/g ) { $debug_stack[$#debug_stack+1] = "e-upper dot"; }
  if ( $str =~ s/ĕ/ĕ/g  ) { $debug_stack[$#debug_stack+1] = "e-breve"; }
  if ( $str =~ s/ë/ë/g ) { $debug_stack[$#debug_stack+1] = "e-umlaut"; }
  if ( $str =~ s/Ë/Ë/g ) { $debug_stack[$#debug_stack+1] = "E-umlaut"; }
  if ( $str =~ s/ẽ/ẽ/g ) { $debug_stack[$#debug_stack+1] = "e-tilde"; }

  if ( $str =~ s/ę/ę/g ) { $debug_stack[$#debug_stack+1] = "e-ogonek"; } # p216674 should be 'Oświęcim', got ' 7^_aOświęcim^_2yso/swe^_0http://www.yso.fi/onto/yso/p216674'

  # TODO: MEL-16299025 has ģ
  if ( 0 && $str =~ s/ǧ/ǧ/g ) { $debug_stack[$#debug_stack+1] = "g-carot"; }

  if ( $str =~ s/ğ/ğ/g  ) { $debug_stack[$#debug_stack+1] = "g-breve"; }

  if ( $str =~ s/í/í/g ) { $debug_stack[$#debug_stack+1] = "i-acute"; }
  if ( $str =~ s/Í/Í/g ) { $debug_stack[$#debug_stack+1] = "I-acute"; }
  if ( $str =~ s/ì/ì/g ) { $debug_stack[$#debug_stack+1] = "i-grave"; }
  if ( $str =~ s/Ì/Ì/g ) { $debug_stack[$#debug_stack+1] = "I-grave"; }
  if ( $str =~ s/ī/ī/g ) { $debug_stack[$#debug_stack+1] = "i-line"; }
  if ( $str =~ s/î/î/g ) { $debug_stack[$#debug_stack+1] = "i-creve"; }
  if ( $str =~ s/Ï/Ï/g ) { $debug_stack[$#debug_stack+1] = "I-umlaut"; }
  if ( $str =~ s/ï/ï/g ) { $debug_stack[$#debug_stack+1] = "i-umlaut"; }
  if ( $str =~ s/ĩ/ĩ/g ) { $debug_stack[$#debug_stack+1] = "i-tilde"; }
  # TODO: ł

  if ( $str =~ s/ń/ń/g ) { $debug_stack[$#debug_stack+1] = "n-acute"; }
  if ( $str =~ s/ñ/ñ/g ) { $debug_stack[$#debug_stack+1] = "n-tilde"; }

  if ( $str =~ s/ṇ/ṇ/g ) {
    $debug_stack[$#debug_stack+1] = "n-dot";
  }

  if ( 0 && $str =~ s/ñ/n̄/g ) { # tää on virheellinen, tä
    $debug_stack[$#debug_stack+1] = "n-line";
  }

  if ( $str =~ s/ṅ/ṅ/g ) {
    $debug_stack[$#debug_stack+1] = "n-upper dot";
  }

  if ( $str =~ s/ó/ó/g ) { $debug_stack[$#debug_stack+1] = "o-acute"; }
  if ( $str =~ s/Ó/Ó/g ) { $debug_stack[$#debug_stack+1] = "O-acute"; }

  if ( $str =~ s/ò/ò/g ) { $debug_stack[$#debug_stack+1] = "o-grave"; }
  if ( $str =~ s/Ò/ò/g ) { $debug_stack[$#debug_stack+1] = "O-grave"; }


  if ( $str =~ s/õ/õ/g ) { $debug_stack[$#debug_stack+1] = "o-tilde"; }

  # wīlwīl'tĕlhuku
  # wīlwīl'tĕlhuku

  if ( $str =~ s/ō/ō/g ) { $debug_stack[$#debug_stack+1] = "o-line"; }
  if ( $str =~ s/ô/ô/g ) { $debug_stack[$#debug_stack+1] = "o-^"; }
  if ( $str =~ s/Ô/Ô/g ) { $debug_stack[$#debug_stack+1] = "O-^"; }
  if ( $str =~ s/ŏ/ŏ/g  ) { $debug_stack[$#debug_stack+1] = "o-breve"; }

  if ( $str =~ s/ŕ/ŕ/g ) { $debug_stack[$#debug_stack+1] = "r-acute"; }

  # Record: 1587445
  # PROCESS-500.0	'  aBible: překlady české, komentáře.'
  # PROCESS-500.1	'  aBible: překlady české, komentáře.'
  if ( $str =~ s/ř/ř/g ) { $debug_stack[$#debug_stack+1] = "r-caron"; }
  
  if ( $str =~ s/ś/ś/g ) { $debug_stack[$#debug_stack+1] = "s-acute"; }
  if ( $str =~ s/ş/ş/g ) { $debug_stack[$#debug_stack+1] = "s-cedilla"; }
  if ( $str =~ s/Ş/Ş/g ) { $debug_stack[$#debug_stack+1] = "S-cedilla"; }
  if ( $str =~ s/š/š/g  ) { $debug_stack[$#debug_stack+1] = "s-caron"; }
  # TODO: š (auth-37705)
  if ( $str =~ s/ṭ/ṭ/g ) { $debug_stack[$#debug_stack+1] = "t-dot"; }

  if ( $str =~ s/ú/ú/g ) { $debug_stack[$#debug_stack+1] = "u-acute"; }
  if ( $str =~ s/Ú/Ú/g ) { $debug_stack[$#debug_stack+1] = "U-acute"; }
  if ( $str =~ s/ŭ/ŭ/g  ) { $debug_stack[$#debug_stack+1] = "u-breve"; }
  if ( $str =~ s/û/û/g ) { $debug_stack[$#debug_stack+1] = "u-creve"; }
  if ( $str =~ s/Û/Û/g ) { $debug_stack[$#debug_stack+1] = "U-creve"; }
  if ( $str =~ s/ù/ù/g ) { $debug_stack[$#debug_stack+1] = "u-grave"; }
  if ( $str =~ s/Ù/Ù/g ) { $debug_stack[$#debug_stack+1] = "U-grave"; }


  if ( $str =~ s/ū/ū/g ) { $debug_stack[$#debug_stack+1] = "u-line"; }
  if ( $str =~ s/ũ/ũ/g ) { $debug_stack[$#debug_stack+1] = "u-tilde"; }
  # Ũ seems like erronous Estonian ü
  #if ( $str =~ s/Ũ/Ũ/g ) { $debug_stack[$#debug_stack+1] = "U-tilde"; }
  if ( $str =~ s/ü/ü/g ) { $debug_stack[$#debug_stack+1] = "u-umlaut"; }
  if ( $str =~ s/Ü/Ü/g ) { $debug_stack[$#debug_stack+1] = "U-umlaut"; }
  if ( $str =~ s/û/û/g ) { $debug_stack[$#debug_stack+1] = "u-^"; }

  if ( 0 && $str =~ s/XXX/ǔ/g ) { # ǎ breve ǔ
    $debug_stack[$#debug_stack+1] = "u-carot";
  }

  # Ei tunnu tällä korjaantuvan...
  if ( $str =~ s/ý/ý/g ) { $debug_stack[$#debug_stack+1] = "y-acute"; }
  if ( $str =~ s/ỳ/ỳ/g ) { $debug_stack[$#debug_stack+1] = "y-grave"; }
  if ( $str =~ s/ÿ/ÿ/g ) { $debug_stack[$#debug_stack+1] = "y-umlaut"; }
  if ( $str =~ s/ỹ/ỹ/g ) { $debug_stack[$#debug_stack+1] = "y-tilde"; }

  if ( $str =~ s/Ý/Ý/g ) { $debug_stack[$#debug_stack+1] = "Y-acute"; }

  if ( $str =~ s/ź/ź/g  ) { $debug_stack[$#debug_stack+1] = "z-acute"; } # TODO
  if ( $str =~ s/ž/ž/g  ) { $debug_stack[$#debug_stack+1] = "z-caron"; }

  # Some random shit:
  $orig_str = $str;
  $str = &string_replace($str, "ä̈", "ä");
  if ( $str ne $orig_str ) { $debug_stack[$#debug_stack+1] = "ä-umlaut!"; }

  $orig_str = $str;
  $str = &string_replace($str, "ö̈", "ö");
  if ( $str ne $orig_str ) { $debug_stack[$#debug_stack+1] = "ö-umlaut!"; }


  # Mystisestä syystä nämä aiheuttivat virheen s///-muodossa.
  # Tutki myöhemmin paremmin...
  $orig_str = $str;
  $str = &string_replace($str, "ö", "ö");
  if ( $str ne $orig_str ) { $debug_stack[$#debug_stack+1] = "o-umlaut"; }


  $orig_str = $str;
  $str = &string_replace($str, "Ö", "Ö");
  if ( $str ne $orig_str ) {
    $debug_stack[$#debug_stack+1] = "O-umlaut";
  }

  # Add these normalizations here as well:
  if ( $str =~ s/Ⓒ/©/g ) {
      $debug_stack[$#debug_stack+1] = "Ⓒ => ©";
  }
  if ( $str =~ s/Ⓟ/℗/g ) {
      $debug_stack[$#debug_stack+1] = "Ⓟ => ℗\n";
  }
  
  if ( $warn && $#debug_stack > -1 ) {
    print STDERR "Fixed ", join(", ", @debug_stack), ( $warn != 2 ? " in '$str'..." : "" ), "\n";
  }

  # TODO? Normalize various lines to '-'? NodeJS had something like that...
  
  return $str;
}

sub unicode_fixes($) {
  my $str = $_[0];
  return unicode_fixes2($str, 1);
}

sub encoding_fixes($) { # Rename...
  my $str = $_[0];
  $str =~ s/\&amp;/\&/g;
  $str =~ s/\&apos;/'/g;
  $str =~ s/\&lt;/</g;
  $str =~ s/\&gt;/>/g;
  $str =~ s/\&quot;/\"/g;

  #$str = &unicode_fixes($str);

  return $str;
}


sub html_escapes($) {
  my $str = $_[0];
  if ( $str =~ /[<>&]/ ) { # trying to optimize...
    $str =~ s/\&/\&amp;/g;
    $str =~ s/</\&lt;/g;
    $str =~ s/>/\&gt;/g;
    # No need to do &apos; etc
  }
  return $str;
}


sub remove_diacritics($) {
  my ( $name ) = $_[0];
  my $val = $name;
  # these have been copypasted from jp.perl:
  $val =~ s/ä/ä/g;
  $val =~ s/Ä/Ä/g;

  $val =~ s/ö/ö/g;
  $val =~ s/Ö/Ö/g;
  # 2019-04-16: Miksi mä tutkin merkkejä, enkä vaan heitä kaikkia diakriitteja
  # jorpakkoon? Ainakin kaikki graavit ja akuutit voisi klaarata noin...
  # Mites viron õ?
  $val =~ s/æ/ä/g;
  $val =~ s/(Ā|Á|Á|À)/A/g;
  $val =~ s/á́́/a/g;
  $val =~ s/(â̂)/a/g; # Nähty tupla-lappalaisnimi: "Mikkâ̂l" (typo?)
  $val =~ s/(ạ|á|á|ā|â|á|á|à|ã|ą|ă|ắ)/a/g; # Nähty tupla-lappalaisnimi: "Mikkâ̂l" (typo?)
  $val =~ s/(Č|Č)/C/g;
  $val =~ s/(ç|č|ç|ć|č|ć)/c/g;
  $val =~ s/đ/d/g; # Balkan
  $val =~ s/Đ/D/g; # Balkan Nockovic, Dorde
  $val =~ s/(Ē|É|Ê)/E/g;
  $val =~ s/(è̀|é́)/e/;
  $val =~ s/(ë|é|è|ě|ĕ|ë|ė|é|è|ê|ę|ē|ĕ|ĕ|ě)/e/g; # 2019Q2: nähty tupla-´
  $val =~ s/(g̓|ǧ)/g/g;
  $val =~ s/ḥ/h/g;
  $val =~ s/(ị|ı́|í|ï|ī|ì|í|ï|î)/i/g;
  $val =~ s/ı/i/g;
  $val =~ s/(İ|Í)/I/g;
  $val =~ s/ķ/k/g;
  $val =~ s/(ł|ļ|ļ)/l/g;
  $val =~ s/Ł/l/g;
  $val =~ s/(ń|ň|ñ|ņ|n̦|ń|ñ)/n/g;

  $val =~ s/(ó|ò|õ|ő|ō|ő|ó|ô)/o/g;

  $val =~ s/(Ó|Õ|Ō|Ó)/o/g;
  $val =~ s/ø/ö/g;
  $val =~ s/Ø/Ö/g;
  $val =~ s/(ř|r̆|ř|ṛ)/r/g;
  $val =~ s/s̆̌|š̌/s/g;
  $val =~ s/(š|s̆|ş|ś|š|š|š)/s/g; # Poleš̌tšuk, Oleg Nikolajevitš
  $val =~ s/(Š̌)/S/g;
  $val =~ s/(Š|Š|Ş|Ṣ|Ş)/S/g; # ?? Miten tämä käsitellään? S? Sh?
  $val =~ s/(ţ|ț)/t/g;
  $val =~ s/Ţ/T/g;
  $val =~ s/ü̈/u/g;

  $val =~ s/(ů|û|ū|ú|ü|ů|ú|ù|ü̈|ü)/u/g; # ü => y?
  $val =~ s/(Ú|Û)/U/g;
  $val =~ s/Ý/Y/g;
  $val =~ s/(ÿ|ý|ý|ỳ|ý)/y/g;
  $val =~ s/(ž|ż|ž)/z/g;
  $val =~ s/Ž/Z/g;
  return $val;
}

1;
