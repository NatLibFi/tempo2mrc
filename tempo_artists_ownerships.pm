#
# tempo_artists_ownerships.pm - process author informations
#
# Handle both artists_publishing_ownerships and artists_master_ownerships.
# Used via provess_tempo_authors).

use strict;
use tempo_utils;
use Data::Dumper;
use nvolk_utf8; # unicode_fixes2

my $debug = 1;
my $robust = 0;
our $localhost = `hostname`;

our %name2auth_records;   # koottu siistityistä (100|110|700|710)#a-kentistä

my %X00_score; # order between different X00 fields.
$X00_score{'säveltäjä'} = 100;
$X00_score{'sanoittaja'} = 90;
$X00_score{'sovittaja'} = 80;
$X00_score{'editointi'} = 70; # NB! TODO: Not really supported currently...
$X00_score{'johtaja'} = 60;
$X00_score{'orkesterinjohtaja'} = 60;
$X00_score{'esittäjä'} = 50;

our @X00_scorelist = sort { $X00_score{$b} <=> $X00_score{$a} } keys %X00_score;


my %X00e_score; # Order between diffent X00$e *sub*fields
$X00e_score{'säveltäjä'} = 1000;
$X00e_score{'kirjoittaja'} = 990;
$X00e_score{'sanoittaja'} = 980;
$X00e_score{'säveltäjä (ekspressio)'} = 975;
$X00e_score{'sanoittaja (ekspressio)'} = 974;
$X00e_score{'kokoaja'} = 970;
$X00e_score{'sovittaja'} = 960;
$X00e_score{'esittäjä'} = 950;
$X00e_score{'johtaja'} = 940;
$X00e_score{'musiikkiohjelmoija'} = 10;
our @X00e_scorelist = sort { $X00e_score{$b} <=> $X00e_score{$a} } keys %X00e_score;


#our %wrong_name2auth_records; # source: FIN11 fields 400/410
our %name2tarke; # Mamba => yhtye (vrt. "Mamba (yhtye)")

our $fin11_read = 0;
our $fin11_file = '/dev/shm/index/asteri/fin11_for_fono.seq';

my $dd_regexp = get_dd_regexp();
my $mm_regexp = get_mm_regexp();
my $yyyy_regexp = get_yyyy_regexp();

my $rejectables = "(?:Anonyymi|Kansan(sävelmä|perinne|runo|laulu)|Kanteletar|Koraalitoisinto|Negro spiritual|Nimeämätön|Raamattu|Ruotsin kirkon virsikirja|Tuntematon|Virsikirja)";


# We should really trust our auth records, and not use this legacy list:
my $human_names = "2pac/66KES88/Aksim 2000/Centro 53/js15/JS16/Jussi 69/Jyrki 69/Kid1/Kurt 49/Melody Boy 2000/Mars 31 Heaven/M1tsQ/Sairas T/Steen1/T1tsQ/Vilunki 3000";
my @human_names = split("/", $human_names);
my %human_names;
foreach my $n ( @human_names ) { $human_names{$n} = 1; }



sub not_really_a_name($) {
    my ( $name ) = @_;
    if ( $name =~ /$rejectables/i ) {
	return 1;
    }
    return 0;
}


sub extract_pseudonym_from_full_name($) {
    my ( $full_name_ref ) = @_;

    # Pseudonym, identity included:
    if ( ${$full_name_ref} =~ s/ *\/pseud \/ \(= *([^\)]+)\) */ / ||
	 ${$full_name_ref} =~ s/ \(pseud\) \(= *([^\)]+)\) */ / ) {
	return $1;
    }
    
    # Pseudonym, real identity not defined:
    if ( ${$full_name_ref} !~ /=/ ) {
	if ( ${$full_name_ref} =~ s/ *\/pseud \/ */ / ||
	     ${$full_name_ref} =~ s/ \(pseud\)$// ) {
	    print STDERR "DEBUG\tTempo: '", ${$full_name_ref}, "' is an unnamed pseudonym\n";
	    return 1;
	}
    }
    
    # 'Paradise Oskar (= Ehnström, Axel) (laulu)'
    if ( ${$full_name_ref} =~ s/ *\(= ([^\)\( ]+, [^\)\( ]+)\) *// ) {
	return $1;
    }
    return undef;
}


sub process_tempo_full_name($) {
    my $name = shift;
    my $orig_name = $name;
    my %data;

    my $pseudonym = extract_pseudonym_from_full_name(\$name);
    if ( defined($pseudonym) ) {
	$data{'pseudonym'} = $pseudonym;
	$name =~ s/ +$//;
    }

    
    # Handle years data:
    if ( !not_really_a_name($name) && $name =~ s/ *\[([^\]]*)\] *\.? */ / ) {
	my $cand_lived = $1;
	if ( $cand_lived =~ /^([0-9]{4})-([0-9]{4})$/ ) {
	    $data{'birth_year'} = $1;
	    $data{'death_year'} = $2;
	}
	else {
	    print STDERR "WARNING\tUnhandled years: $cand_lived\n";
	    die($orig_name); # die() for coverage's sake
	}
    }
    # Handle functions:
    if ( $name =~ s/\((laulu)\)// ) {
	$data{'laulaja'} = $1; # hack
    }
    if ( $name =~ s/\((san)\)// ) {
	$data{'sanoittaja'} = $1;
    }
    if ( $name =~ s/\((sov)\)// ) {
	$data{'sovittaja'} = $1;
    }
			
    $name =~ s/  +/ /g;

    # '4th Line Horn Quartet (4th Line-käyrätorvikvartetti)' =>
    # '4th Line Horn Quartet' =>
    while ( $name =~ s/(\S) *(\([^=\)][^\)]+\)) *$/$1/ ) { 
	print STDERR "Remove '$2' from '$name'\n";
    }

    if ( $name =~ /(\/|\()/ ) {
	print STDERR "WARNING\tCheck '$name'\n";
    }

    # Pre- and decompose:
    $data{'name'} = unicode_fixes2($name, 1);
    
    if ( $debug && 0 ) {
	foreach my $key ( sort keys %data ) {
	    print STDERR "AUTHOR DATA $key '", $data{$key}, "'\n";
	}
    }
    return %data;
}


sub merge_names($$) {
    my ( $nameP1, $nameP2 ) = @_;
    # Boldly assume that same name means smae person
    foreach my $key ( sort keys %{$nameP2} ) {
	my $val = ${$nameP2}{$key};
	if ( ${$nameP1}{$key} eq $val ) {
	    # No action required
	}
	elsif ( !defined(${$nameP1}{$key}) ) {
	    if ( $debug ) {
		print STDERR "Add $key:$val\n";
	    }
	    ${$nameP1}{$key} = $val;
	}
	else {
	    print STDERR "1: $key:'", ${$nameP1}{$key}, "'\n";
	    print STDERR "2: $key:'$val'\n";
	    die();
	}

    }
}


# Finnish three-letter abbreviations come from addition notes
our %norm_funcs = (
    'arranger' => 'sovittaja',
    'ensemble' => 'esittäjä',
    # 'author' => 'kirjoittaja',
    'composer' => 'säveltäjä',
    'lyricist' => 'sanoittaja',
    'musician' => 'esittäjä',
    'san' => 'sanoittaja',
    'sov' => 'sovittaja',
    'special-lyricist' => 'sanoittaja', # sanoittaja (ekspressio)?
    'säv' => 'säveltäjä'
    ); 
# Huh: 'special-lyricist'!

sub normalize_function($) {
    my $function = shift;
    if ( defined($norm_funcs{$function}) ) {
	return $norm_funcs{$function};
    }
    die("'$function' not mapped");
}


sub debug_remaining_keys {
    my $prefix = shift;
    my %remaining_keys = @_;
    # Recheck remaining keys. We might stop here to handle
    # unhandled keys.
    if ( $debug ) {
	my @keys = sort keys %remaining_keys;
	if ( $#keys > -1 ) {
	    print STDERR "WARNING\tREMAINING KEYS FOR '$prefix':\n";
	    foreach my $curr_key ( @keys ) {
		my $val = $remaining_keys{$curr_key};
		print STDERR " KEY '$curr_key'\tVAL '$val'\n";
	    }
	}
    }
}


sub get_tempo_authors($$$) {
    my ( $head, $arr_ref, $marc_record_ref ) = @_;

    my %authors;
    # should artists_publishing_ownerships[0] come before
    # artists_master_ownerships[0] or vice versa?
    # Currently index (=position) is shared.
    my @prefixes = ( "/$head/artists_publishing_ownerships", "/$head/artists_master_ownerships" );
    for ( my $i=0; $i <= $#prefixes; $i++ ) {
	my $curr_prefix = $prefixes[$i];
	my $index = 0;
	my @data;
	print STDERR "FOO: '$curr_prefix'\n";
	while ( @data = extract_keys($curr_prefix."[$index]", $arr_ref) ) {
	    print STDERR "BAR $curr_prefix\[$index]\n";
	    if ( $#data > -1 ) {
		# remove key/ from start:
		@data = map { substr($_, length($curr_prefix."[$index]")+1) } @data; 
		# Store artist-specific data to %foo:
		my %foo;
		for ( my $j=0; $j <= $#data; $j++ ) {
		    if ( $data[$j] =~ /^(.*) = '(.*)'$/ ) {
			$foo{$1} = $2;
		    }
		}
		# Handle artist-specific data:
		if ( !defined($foo{'artist/_id'}) ) {
		    die(join("\n", @data)); # critical shit.
		}
		my $id = $foo{'artist/_id'};
		print STDERR "New ID '$id'\n";
		my $new_id = ( defined($authors{$id}) ? 0 : 1 );
		
		if ( $new_id ) {
		    $authors{$id} = {};
		}

	 	my $curr_key = 'artist/full_name';   
		if ( defined($foo{$curr_key}) ) {
		    my $curr_name = $foo{$curr_key};
		    my %name_data = process_tempo_full_name($curr_name);

		    # Index is meaningful, when we compare two authors:
		    # Eg. if we have two composers, prefer the one with lower
		    # index (eg: she'll get 100, and the other guy gets 700).
		    # However, we currently have two indexes, so this
		    # needs thinking...
		    if ( $new_id ) {
			$name_data{'index'} = $index;
			$authors{$id} = \%name_data;
			print STDERR "INDEX: ", $authors{$id}{'index'}, "\n";
		    }
		    else {
			merge_names($authors{$id}, \%name_data);
		    }
		    delete $foo{$curr_key};
		}
		
		$curr_key = 'rights_type/key';
		if ( defined($foo{$curr_key}) ) {
		    my $tmp = $foo{$curr_key};
		    if ( $tmp eq 'author' ) {
			# "author", joka tarkoittanee toimijaa, joka on
			# vastuussa koko teoksesta eli tekstisisältöisessä
			# laulussa säveltäjä ja sanoittaja."
			$authors{$id}{'säveltäjä'} = 'säveltäjä';
			$authors{$id}{'sanoittaja'} = 'sanoittaja';
		    }
		    else {
			$tmp = normalize_function($tmp);
			if ( defined($tmp) ) {
			    $authors{$id}{$tmp} = $tmp;

			}
			else {
			    die($tmp); # NB! The key gets deleted as well
			}
		    }
		    delete $foo{$curr_key};
		}

		$curr_key = 'rights_type/key';
		if ( defined($foo{$curr_key}) ) {
		}
		# Delete uninteresting data:
		my @deletables = ( 'artist/_id',
				   'artist/created_at',
				   'artist/ingestion_id',
				   'artist/tenant',
				   'artist/updated_at',
				   'rights_type/_id',
				   'rights_type/created_at',
				   'rights_type/type',
				   'rights_type/updated_at' );

		for ( my $j=0; $j <= $#deletables; $j++ ) {
		    my $curr_key = $deletables[$j];
		    delete $foo{$curr_key};
		}

		# Handle, delete or complain about unused (undeleted) keys:
		my @keys = sort keys %foo;
		if ( $#keys > -1 ) {
		    foreach my $key ( @keys ) {
			my $val = $foo{$key};
			if ( $key eq 'additional_notes' ) {
			    my $proceed = 1;
			    while ( $proceed ) {
				$proceed = 0;
				if ( $val =~ s/^(?:myös )?(san|sov|säv)($|, *)//i ) {
				    my $func = normalize_function(tempo_lc($1));
				    #$authors{$id}{$func} = $func;
				    $proceed = 1;
				}
				# Tail
				elsif ( $val =~ s/(?:^|, )(san|sov|säv)$//i ) {
				    my $func = normalize_function(tempo_lc($1));
				    #$authors{$id}{$func} = $func;
				    $proceed = 1;
				}
				
				elsif ( $val ) {
				    # die($val);
				}
			    }

			    if ( $val eq '' ) {
				delete $foo{$key};
			    }
			    else {
				$foo{$key} = $val;
			    }
			}
		    }
		    @keys = sort keys %foo;
		    foreach my $key ( @keys ) {
			my $val = $foo{$key};
			# Handle (and delete):
			if ( $key =~ /^instruments\[\d+\]+\/key$/ ) {
			    if ( $val eq 'yhtye' ) {
				$authors{$id}{'yhtye'} = 1;
			    }
			    elsif ( $val eq 'johtaja' ) {
				$authors{$id}{$val} = $val;
			    }
			    elsif ( $val eq 'ym' ) {
				# ignorable shit
			    }
			    elsif ( $debug ) {
				print STDERR "Warning: ignore instrument '$val' ($key)\n";
			    }
			    delete $foo{$key};
			}
			# Seen with Jan 2022 samples.
			# What happened to death/birth year?
			elsif ( $key eq "artist/custom" &&
				$foo{$key} =~ /^($yyyy_regexp) ($yyyy_regexp)$/ ) {
			    $authors{$id}{'birth_year'} = $1;
			    $authors{$id}{'death_year'} = $2;
			    delete $foo{$key};
			}
			elsif ( $key eq "artist/custom/birth_year" ) {
			    $authors{$id}{'birth_year'} = $foo{$key};
			    delete $foo{$key};
			}
			elsif ( $key =~ /^artist\/custom\/death_year$/ ) {
			    $authors{$id}{'death_year'} = $foo{$key};
			    delete $foo{$key};
			}
			# Delete:
			elsif ( $key =~ /(created_at|updated_at)$/ ||
				$key =~ /^instruments\[\d+\]\/_id$/ ) {
			    delete $foo{$key};
			}
			# Complain:
			else {
			    print STDERR "TODO: AUTH $key -> ", $foo{$key}, "\n";
			}
		    }
		    debug_remaining_keys("$curr_prefix\[$index\]", %foo);
		}
		$index++;
	    }
	}
    }


    remove_non_authors(\%authors, $marc_record_ref);

    return %authors;
}


sub get_functions($) {
    my $author_ref = shift();
    my %author = %{$author_ref};

    my @e_array = ();
    # Hacky: delete generic 'esittäjä' if we have more specific function:
    # (T.M. did not want $e esittäjä, $e johtaja for Osmo Vänskä,
    #  just $e johtaja)
    # (In future this list may or may nor grow.)
    if ( defined($author{'johtaja'}) ||
	 defined($author{'laulaja'}) ) {
	delete $author{'esittäjä'};
    }
    # However, we don't want to use 'laulaja' so put the 'esittäjä' key back in
    if ( defined($author{'laulaja'}) ) {
    	delete $author{'laulaja'};
	$author{'esittäjä'} = 'laulaja';
    }
    
    # Go thru X00$e fields from best to worst. Add hits.
    # This way the top-priority function comes first.
    for ( my $i=0; $i <= $#X00e_scorelist; $i++ ) {
	my $curr_funk = $X00e_scorelist[$i];
	if ( defined($author{$curr_funk}) ) {
	    $e_array[$#e_array+1] = $curr_funk;
	}
    }
    return @e_array;
}




sub remove_non_authors($$) {
    my ( $authorsP, $marc_recordP ) = @_;
    # Remove non-authors from %authors data structure.
    # Typically pllace them in field 500 instead.

    foreach my $key ( sort keys %{$authorsP} ) {
	my %curr_author = %{${$authorsP}{$key}};
	my $name = $curr_author{'name'};
	my $content = undef;

	if ( $debug ) {
	    print STDERR "DEBUG\tInspect '$name' (non-authority)\n";
	}
	if ( $name =~ /soitinnus/ ) { 
	    $content = "  \x1FaMusiikin esityskokoonapano: $name.";
	    die(); #testaamatta ja hiomatta...
	}
	elsif ( not_really_a_name($name) ) {
	    if ( $name !~ /$rejectables$/i && $name !~ /^$rejectables/ ) {
		if ( !$robust ) {
		    die();
		}
	    }
	    
	    if ( $debug ) {
		print STDERR "DEBUG\t'$name' is not an author. It goes to 500 instead.\n";
	    }
	    $content = "  \x1Fa";
	    if ( $name =~ /(Kanteletar|Raamattu)/i ) {
		$content .= "Sanat: ";
	    }
	    if ( $name eq 'Nimeämätön' ) {
		my @authors_functions = get_functions(\%curr_author);
		$name .= ' '.join(', ', @authors_functions);
		$name =~ s/, ([^,]+)$/ ja $1/; # && die($name); # untested
		$name = "Tekijähuomautus: $name";
	    }
	    $content .= $name.'.';
	}

	if ( defined($content) ) {
	    add_marc_field($marc_recordP, '500', $content);
	    delete ${$authorsP}{$key};
	}
    }
}


sub score_author($$$) {
    my ( $author_ref, $is_classical_music, $is_host ) = @_;
    my %author = %{$author_ref};
    if ( 1 || $is_classical_music || !$is_host ) {
	for ( my $i=0; $i <= $#X00_scorelist; $i++ ) {
	    my $curr_funk = $X00_scorelist[$i];
	    if ( defined($author{$curr_funk}) ) {
		return $X00_score{$curr_funk};
	    }
	}
    }
    else {
	# Fono took the first 190 field, but what if counterpair for Fono-190...
	die();
    }
    return 0;
}


sub map_name2auth_record($$) {
    my ( $name, $auth_record ) = @_;

    if ( !$fin11_read ) { read_minified_fin11(); }

    my $i;
    my @stack = ( $name );
    
    my $normalized_name = remove_diacritics($name);
    if ( $normalized_name ne $name ) {
	$stack[$#stack+1] = $normalized_name;
    }

    my $authstr = $auth_record->toString();
    foreach my $n ( @stack ) {
	my $skip = 0;
	for ( $i = 0; $i <= $#{$name2auth_records{$n}}; $i++ ) {
	    if ( $authstr eq $name2auth_records{$n}[$i]->toString() ) {
		$skip = 1;
	    }
	}
	if ( !$skip ) {
	    push(@{$name2auth_records{$name}}, $auth_record);
	}
    }
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


sub get_name_variants($) {
    # NB! Hammerstein, Oscar, II track_60455260b7cc3b0168460681.json 
    # 1001  L $$aHammerstein, Oscar,$$bII,$$d1895-1960$$0(FIN11)000195616
    my ( $field ) = @_;
    my $subfield_a = $field->get_first_matching_subfield('a');

    if ( !defined($subfield_a) ) {
	# 2022-06-16 this got triggered.
	return (); # Try to be robust...
	die($field->{content});
    }
    $subfield_a =~ s/,$//; # What about '.'?

    if ( $debug && $subfield_a =~ /Hammerstein/ ) {
	print STDERR "GNV: ", $field->toString(), " => ‡a:", $subfield_a, "\n";
    }
    
    my $subfield_b = $field->get_first_matching_subfield('b');
    if ( defined($subfield_b) ) {
	$subfield_b =~ s/,$//; # What about '.'?
	if ( $debug && $subfield_a =~ /Hammerstein/ ) {
	    print STDERR "GNV: ‡b:", $subfield_b, " in  ", $field->toString(), "\n";
	}
    }

    # Add $a as such:
    my %cands;
    $cands{$subfield_a} = 1;

    # Yle stores names in "Forename Surname" format.
    

    if ( $field->{tag} =~ /00$/ ) {
	# "Surname, Forname":
	if ( $field->{content} =~ /^1/ ) {
	    # Assumes single ','
	    if ( $subfield_a =~ /^([^,]+), ([^,]+)$/ ) {
		my $tmp = "$2 $1";
		$cands{$tmp} = 1;
		
		# With $b: Hammerstein, Oscar, II
		if ( defined($subfield_b) ) {
		    $tmp = $subfield_a . ", " . $subfield_b;
		    $cands{$tmp} = $tmp;
		}
	    }
	}
	# "Forname Surname"
	elsif ( $field->{content} =~ /^0/ ) {
	    # TODO: handle $b 
	    if ( defined($subfield_b) ) {
		# $a Johannes Paavali $b II
		my $tmp = $subfield_a . " " . $subfield_b;
		$cands{$tmp} = $tmp;
	    }		
	}
    }

    # TODO: Handle case normalizations: van vs Van..

    foreach my $curr_cand ( sort keys %cands ) {
	my $tmp = $curr_cand;
	if ( $tmp =~ s/\b(af|van|von)\b/\u$1/ ) {
	    $cands{$tmp} = $curr_cand;
	}
	elsif ( $tmp =~ s/\b(Af|Van|Von)\b/\l$1/ ) {
	    $cands{$tmp} = $curr_cand;
	}
	
    }
    # TODO: Handle normalizations II: diacritics
    foreach my $curr_cand ( sort keys %cands ) {
	my $tmp = &remove_diacritics($curr_cand);
	if ( $tmp ne $curr_cand ) {
	    $cands{$tmp} = $curr_cand;
	}
    }

    my @result = sort keys %cands;
    if ( $debug && $subfield_a =~ /(Hammerstein|Gustaf von|Hertzen)/ ) {
	print STDERR "Name variants for ", $field->{tag}, ": '", join("', '", @result), "'\n";
    }

    return @result;
}


sub process_fin11_auth_record($) {
    my $sequential = shift;

    my $record = new nvolk_marc_record($sequential);
    my $f001 = $record->get_first_matching_field('001');
    my $record_id = $f001->{content};
    if ( !$record_id ) { die(); }
    
    my $f100 = $record->get_first_matching_field('100');
    my $f110 = $record->get_first_matching_field('110');

    if ( !defined($f100) && !defined($f110) ) { die(); }
#NV#
#NV#  # 100/110
#NV#  # 400/410: kielletyt muodot
#NV#  # 500/510: "katso myös"
#NV#  # 700/710
#NV#
#NV#
#NV#  my $yhtye = 1; # 
#NV#  # Ylempänä katsotaan, että 040:sta löytyy FI-NLD, se riittäköön...
#NV#  if ( 0 && defined($f110) ) {
#NV#    my @f368 = marc21_record_get_fields($record, '368', undef);
#NV#    for ( my $i=0; $i <= $#f368; $i++ ) {
#NV#      if ( $f368[$i] =~ /\x1Fa([^\x1F]*(big band|duo|kuoro|kvartetti|kvintentti|orkesteri|sekstetti|trio|yhtye))($|\x1F)/ ) {
#NV#	$yhtye = 1;
#NV#      }
#NV#      # not interested in these:
#NV#      elsif ( $f368[$i] =~ /\x1F[ab][^\x1F]*(akatemia|alue|apteekki|arkisto|asema|autolautta|baari|divisioona|elin|elimet\)|festivaali|galleria|hallinto|hanke|harjoittaja|hautomo|hotelli|instituutti|istuin|jaosto|järjestö|kanava|kapituli|kassa|kauppa|kauppala|kaupunki|kerho|keskus|keskukset\)|ketju|kilta|kirjasto|kirkko|klubi|kokoelma|kokous|komitea|komppania|konserni|konsortio|koti|koulu|kunta|kurssi|kustantaja|kustantamo|laboratorio|laitos|laitokset\)|laiva|lehti|liike|liitto|luettelo|lukio|lyseo|lähetystö|merkki|ministeriö|museo|myymälä|neuvola|neuvosto|nimi|ohjelma|omainen|operaattori|opisto|opistot\)|organisaatio|osasto|osasto \(museot\)|osasto \(yhtiöt\)|paja|palvelu|pankki|parantola|pataljoona|piiri\)?|poliisi|prikaati|puisto|projekti|puolue|rahasto|rakennus|ravintola|rata|ryhmä|rykmentti|sairaala|\(sairaalat\)|seminaari|seura|sihteeristö|sivusto|studio|säätiö|tapahtuma|teatteri|tehdas|tila|toimiala|toimisto|toimitus|työ|verkosto|virasto|verkosto|väki|yhdistys|yhteisö|yhtiö|yhtymä|yksikkö|yritys)($|\x1F)/i ) {
#NV#	# 
#NV#      }
#NV#      else {
#NV#	print STDERR "368 TODO Contents: '$f368[$i]'\n";
#NV#      }
#NV#    }
#NV#  }

    my @tags = ( '100', '400' ); # no relevant 700 data
    foreach my $curr_tag ( @tags ) {
	my @X00 = $record->get_all_matching_fields($curr_tag);
	for ( my $i=0; $i <= $#X00; $i++ ) {
	    my $X00 = $X00[$i];
	    my @names = get_name_variants($X00);
	    foreach my $name ( @names ) {
		if ( $curr_tag !~ /^4/ ) {
		    &map_name2auth_record($name, $record);
		    if ( $debug && $name =~ /(Hammerstein|Hertzen)/i ) {
			my $f001 = $record->get_first_matching_field('001');
			print STDERR "MAP '$name' TO (FIN11)", $f001->{content}, "\n";
		    }
		}
		else {
		    #NV#	&add_wrong_name2auth_record($X00a, $record);
		}
	    }
	}
    }


    if ( defined($f110) ) {
	#NV#      #print STDERR "AUTH-$record_id\t110\t$f110\n";
	#NV#    #die("TODO: pitää tutkia holdareita, ja ottaa vain yhtyeet...");
	my $f110a = $f110->get_first_matching_subfield('a');
	if ( $f110a ) {
	    &map_name2auth_record($f110a, $record);
	    #NV#      $names10{$f110a} = 1;
	    my $tarke = '';
	    # Lisää sulutonkin versio:
	    if ( $f110a =~ s/ \((.*)\)$// ) {
		$tarke = $1;
		&map_name2auth_record($f110a, $record);
	    }

	    if ( !defined($name2tarke{$f110a}) ) {
		if ( $tarke ne '' ) {
		    $name2tarke{$f110a} = $tarke;
		} else {
		    $name2tarke{$f110a} = "__TYHJÄ__";
		}
	    }
	    # Both auth records agree about tarke, so there's no problem:
	    elsif ( $name2tarke{$f110a} eq $tarke ) { }
	    # Both auth records lack tarke, so no problem here either:
	    elsif ( $tarke eq '' && $name2tarke{$f110a} eq '__TYHJÄ__' ) { } 
	    # Tarke mismatch:
	    else {
		print STDERR "Unsupported ambiguous tarke: $f110a: '$tarke' vs '", $name2tarke{$f110a}, "'\n";
		$name2tarke{$f110a} .= "\t$tarke";
	    }
	}
    }

    
#NV#  # Onkohan näissä mitään järkeä...
#NV#  if  ( $yhtye ) {
#NV#    my @f410 = marc21_record_get_fields($record, '410', '');
#NV#    for ( $i=0; $i <= $#f410; $i++ ) {
#NV#      my $f410 = $f410[$i];
#NV#      my $f410a = marc21_field_get_subfield($f410, 'a');
#NV#      if ( $f410a ) {
#NV#	$f410a =~ s/,$//;
#NV#	&add_wrong_name2auth_record($f410a, $record);
#NV#	$names10{$f410a} = 1;
#NV#	if ( $f410a =~ s/ \(.*\)$// ) { # "foo (yhtye)" => "foo"
#NV#	  &add_wrong_name2auth_record($f410a, $record);
#NV#	  $names10{$f410a} = 1;
#NV#	}
#NV#      }
#NV#      # TODO: näillekin pitäs tehdä jotain...
#NV#      my $f410d = marc21_field_get_subfield($f410, 'd');
#NV#      my $f410e = marc21_field_get_subfield($f410, 'e');
#NV#    }
#NV#  }
#NV#
#NV#  my $f700 = marc21_record_get_field($record, '700', '');
#NV#
#NV#  if ( defined($f700) && $f700 ) { # Paljon melua tyhjästä: näitä on tasan 1
#NV#    #print STDERR " NV 700 $f700\n";
#NV#    my $f700a = marc21_field_get_subfield($f700, 'a');
#NV#
#NV#    if ( defined($f700a) && $f700a ) {
#NV#      $f700a =~ s/,$//;
#NV#      if ( defined($human_names{$f700a}) ) {
#NV#	print STDERR " NV debug 700: outo ihmisnimi: $f700a\n";
#NV#      }
#NV#
#NV#      &map_name2auth_record($f700a, $record);
#NV#      $names00{$f700a} = 1;
#NV#    }
#NV#    my $f700d = marc21_field_get_subfield($f700, 'd');
#NV#    my $f700e = marc21_field_get_subfield($f700, 'e');
#NV#  }
#NV#
#NV#  if ( $yhtye ) {
#NV#    my $f710 = marc21_record_get_field($record, '710', '');
#NV#    if ( defined($f710) && $f710 ) {
#NV#      my $f710a = marc21_field_get_subfield($f710, 'a');
#NV#      # Talleta molemmat versiot nimestä (pelkkä lyhyt versio saattaisi riittää):
#NV#      &map_name2auth_record($f710a, $record);
#NV#      $names10{$f710a} = 1;
#NV#      if ( $f710a =~ s/ \(.*\)$// ) {
#NV#	&map_name2auth_record($f710a, $record);
#NV#	$names10{$f710a} = 1;
#NV#      }
#NV#
#NV#      my $f710d = marc21_field_get_subfield($f710, 'd');
#NV#      my $f710e = marc21_field_get_subfield($f710, 'e');
#NV#    }
#NV#  }
}

	

sub get_best_author($$$) {
    my ( $authors_ref, $is_classical_music, $is_host ) = @_;
    my %authors = %{$authors_ref};
    # Unlike
    
    # Composer:
    if ( $is_classical_music || !$is_host ) {
	my $hits = 0;
	my $composer = undef;
	foreach my $auth_id ( sort keys %authors ) {
	    if ( defined($authors{$auth_id}->{'säveltäjä'}) ) {
		$hits++;
		$composer = $auth_id;
	    }
	}
	# Don't give preference to any of the composers. They all go to 700...
	# This is iffy...
	if ( $hits == 1 ) { return $composer; }
	return undef;
    }

    # Performer.
    # Note that we no longer have distinction between main and other
    # performers! (= Fono fields 190 and 191)
    
    # Should this correspond with 245$c?
    my $hits = 0;
    my $musician = undef;
    foreach my $auth_id ( sort keys %authors ) {
	if ( defined($authors{$auth_id}->{'esittäjä'}) ) {
	    $hits++;
	    $musician = $auth_id;
	}
    }
    # Don't give preference to any of the performers. This is iffy though.
    if ( $hits == 1 ) { return $musician; }
    return undef;
}


sub read_minified_fin11() {
    if ( $fin11_read ) { return; }
    $fin11_read = 1;
    
    # Read minified FIN11 authority data:
    if ( $localhost =~ /ehistoria-kk/ ) {
	if ( ! -e $fin11_file ) {
	    die();
	}
    }
    else {
	print STDERR "WARNING!\tWrong server! Unable to read FIN11 data.\n";
	return;
    }



    # NB! Melinda runs a script "minify_fin11_for_tempo.perl" via crontab
    # which can create minified version of FIN11 for our purposes

    # [melinda@tietuehistoria-kk 0:130] 0.85 ~
    # $ ~/bin/minify_fin11_for_tempo.perl /dev/shm/index/asteri/fin11.seq > /dev/shm/index/asteri/fin11_for_fono.seq

    my $FH;
    my $file = $fin11_file;
    if ( $debug && -e "./fin11test.seq" ) {
	# $file = "./fin11test.seq";
    }
    if ( ! -e $file ) {
	print STDERR "$file: $!\nCREATE IT FIRST!\n";
	print STDERR "[melinda\@tietuehistoria-kk 0:130] 0.85 ~\n";
	print STDERR "\$ ~/bin/minify_fin11_for_tempo.perl /dev/shm/index/asteri/fin11.seq > /dev/shm/index/asteri/fin11_for_fono.seq\n";
	exit();
    }
    elsif ( open($FH, "<$file") ) {
	my $old_id = '';
	my $record = '';
	my $n = 0;
	while ( my $line = <$FH> ) {
	    $line =~ /^(\d+) (.*)$/;
	    my $curr_id = $1;
	    if ( $curr_id eq $old_id ) {
		$record .= $line;
	    } else {
		if ( $old_id ne '' ) {
		    #print STDERR "OLD $old_id NEW $curr_id END\n";
		    process_fin11_auth_record($record);
		    $n++;
		}
		$record = $line;
		$old_id = $curr_id;
	    }
	}
	close($FH);
	if ( $record) { $n++; process_fin11_auth_record($record); }
	if ( $debug ) {
	    print STDERR "$n auktoriteettitietuetta luettu!\n";
	}
    }
    else {
	print STDERR "ERROR: $file: $!\n";
	die();
    }
}



sub name2auth_records($) {
    my ( $name ) = @_;

    if ( !$fin11_read ) { read_minified_fin11(); }

    if ( defined($name2auth_records{$name}) ) {
	return @{$name2auth_records{$name}};
    }
    return ();
}


sub tempo_is_definitely_human($) {
    my ( $author_ref ) = shift;
    my %author = %{$author_ref};
    if ( defined($author{'birth_year'}) ||
	 defined($author{'death_year'}) ||
	 is_pseudonym($author_ref) ) {
	return 1;
    }
    return 0;
}


sub birth_and_death_year_mismatch($$$) {
    my ( $birth_year, $death_year, $author_ref ) = @_;
    # It's ok not to have this information:
    if ( !defined($birth_year) && !defined($death_year) ) { return 0; }

    my $f100 = ${$author_ref}->get_first_matching_field('100');
    if ( !defined($f100) ) { die(); return 0; }
    my $d = $f100->get_first_matching_subfield('d');

    if ( !defined($d) ) { return 0; }

    if ( defined($birth_year) && defined($death_year) ) {
	if ( "$birth_year-$death_year" eq $d ) {
	    return 0;
	}
	print STDERR "WARNING\t", $f100->toString(), "\tYEAR MISMATCH: '$birth_year-$death_year' vs '$d'\n";
	return 1;
    }

    if ( defined($birth_year) && !defined($death_year) ) {
	if ( "$birth_year-" eq $d || index($d, "$birth_year-") == 0 ) {
	    return 0;
	}
	print STDERR "WARNING\t", $f100->toString(), "\tYEAR MISMATCH: '$birth_year-' vs '$d'\n";
	return 1;
    }
    die();
    return 0;
}


sub remove_birth_and_death_mismatches($$) {
    my ( $author_ref, $cand_records_ref ) = @_;
    my $birth_year = ${$author_ref}{'birth_year'};
    my $death_year = ${$author_ref}{'death_year'};

    my @cands = grep { !birth_and_death_year_mismatch($birth_year, $death_year, \$_) } @{$cand_records_ref};
    return @cands;
}


sub tempo_author2asteri_record($$) {
    my ( $author_ref, $cand_records_ref ) = @_;

    if ( !$fin11_read ) { read_minified_fin11(); }
    
    if ( $#{$cand_records_ref} == -1 ) {
	return undef;
    }
    if ( $#{$cand_records_ref} == 0 ) {
	# Can we be sure, that the match is correct?
	# If Tempo person has no birth nor death year,
	# We don't dare to use this.
	if ( ${$cand_records_ref}[0]->get_first_matching_field('100') ) {
	    if ( !defined(${$author_ref}{'birth_year'}) &&
		 !defined(${$author_ref}{'death_year'}) ) {
		if ( $debug ) {
		    print STDERR "NB\tDon't map ", ${$author_ref}{'name'}, " to Asteri, since we don't have a birth/death year in Tempo data.\n";
		    print STDERR Dumper($author_ref), "\n";
		}
		return undef;
	    }
	}
	return ${$cand_records_ref}[0];
    }
    print STDERR "Multiple candidates remains. Skip.\n";
    foreach my $record ( @{$cand_records_ref}) {
	print STDERR $record->toString();
    }
    return undef;
}


sub count_persons_and_bands($) {
    my ( $auth_record_ref ) = @_;
    my $persons = 0;
    my $bands = 0;
    foreach my $record ( @{$auth_record_ref} ) {
	if ( $record->get_first_matching_field('100') ) {
	    $persons++;
	}
	elsif ( $record->get_first_matching_field('110') ) {
	    $bands++;
	}
	else {
	    die();
	}
    }
    return ( $persons, $bands );
}


sub educated_guess_is_person($) {
    my $author_ref = shift;
    my %author = %{$author_ref};

    if ( &tempo_is_definitely_human($author_ref) ) {
	# Has pseudonym, birth year or death year
	return 1;
    }

    if ( defined($author{'johtaja'}) ) {
	#die(Dumper($author_ref));
	return 1;
    }

    # Matias Sassali had this defined...
    if ( 0 && defined($author{'yhtye'}) ) {
	return 0;
    }

    
    my $name = $author{'name'};
    if ( $debug ) {
	print STDERR "Educated X00/X10 guess is based on string '$name'\n";
    }

    if ( $name =~ /[0-9]/ ) {
	if ( defined($human_names{$name}) ) {
	    # NB! No need to list the ones with an authority record
	    die(); # untested after mods
	    return 1;
	}
	return 0;
    }
    # TODO: "The bands" etc
    if ( $name !~ / / ) {
	if ( defined($human_names{$name}) ) {
	    # NB! No need to list the ones with an authority record
	    die(); # untested after mods
	    return 1;
	}
	return 0;
    }

    if ( $name =~ /('s |kuoro|kvintett|orkester)/i ||
	 $name =~ /(^| )(and|band|duo|ensemble|ja|of|orchestra|project|the|trio)($| )/i ) {
	return 0;
    }
    
    if ( $debug ) {
	print STDERR "Educated X00/X10 guess fallback '$name' defaults to person\n";
    }
    return 1;
}


sub get_tens($$$) {
    my ( $author_ref, $asteri_record, $cand_records_ref ) = @_;

    # Use values from an Asteri record:
    if ( defined($asteri_record) ) {
	if ( $asteri_record->get_first_matching_field('110') ) { return '1'; }
	return '0';
    }

    my ( $n_person, $n_band ) = count_persons_and_bands($cand_records_ref);

    if ( $n_person > 0 || $n_band > 0 ) {
	print STDERR "X00: $n_person, X10: $n_band\n";
    }

    # All candidate Asteri records think it's a band:
    if ( $n_person == 0 && $n_band > 0 ) {
	print STDERR " WP2a X00: $n_person, X10: $n_band\n";
	return '1';
    }

    if ( $n_person > 0 && $n_band == 0 ) {
	print STDERR " WP2n X00: $n_person, X10: $n_band\n";
	return '0';
    }


    # 62985aecb6275d003bb6e0f2.json has "Pihlaja" that is ambiguous.
    # (in this case it's a person. However, FAIL.)
    
    # Educated guess based on name
    print STDERR " WP3 X00: $n_person, X10: $n_band\n";
    return educated_guess_is_person($author_ref) ? '0' : '1';

}


sub is_pseudonym($) {
    my ( $author_ref ) = @_;
    # TODO: If auth record containd $c pseudonym...
#    if ( FIN11 100$c salanimi ) {
#	die(); # not seen yet, catch first instance
#	return 1;
#    }
    if ( !$fin11_read ) { read_minified_fin11(); }
    
    # Pseudonym as per Tempo:
    if ( defined(${$author_ref}{'pseudonym'}) ) { # Tempo
	return 1;
    }
    return 0;
}



sub tempo_author_to_marc_field($$$) {
    my ( $author_ref, $marc_record_ref, $hundred ) = @_;
    my %author = %{$author_ref};

    my $name = $author{'name'};

    my @cand_records = &name2auth_records($name);
    my $n_cands = $#cand_records+1;
    if ( $debug ) { print STDERR "author ($name) => asteri: $n_cands cand(s) found.\n"; }
    #if ( $#cand_records > -1 ) { die(); } # test: found something


    if ( $name =~ /ja\/tai/ ) { die(); } # Fono crap. Sanity check: do we see this also in Tempo...
    
    my $must_be_human = tempo_is_definitely_human($author_ref);
    if ( $must_be_human ) {
	# TODO: remove non-humans from @records;
	@cand_records = grep { $_->get_first_matching_field('100') } @cand_records;
	@cand_records = remove_birth_and_death_mismatches($author_ref, \@cand_records);
    }
    if ( $n_cands != $#cand_records+1 ) {
	if ( $debug ) {
	    print STDERR "  after filtering", ($#cand_records+1), " cand(s) found.\n";
	}
	$n_cands = $#cand_records+1;
    }

    # Try to find an Asteri record.
    my $asteri_record = tempo_author2asteri_record($author_ref, \@cand_records);
    #if ( $asteri_record ) { die(); }
    my $ten = get_tens($author_ref, $asteri_record, \@cand_records);

    my $content = '';

    print STDERR "A2M $name BAND? X${ten}0, ASTERI: ", ($asteri_record ? 'Y':'N'), ", $n_cands\n";
    my $sf0 = undef;
    if ( defined($asteri_record) ) {
	my $f1X0 = $asteri_record->get_first_matching_field('1.0');
	if ( !defined($f1X0) ) { die(); }
	# Do we dare to add $0 for bands based on just name? Risky...
	if ( $f1X0->{tag} =~ /00$/ ) {
	    if ( $f1X0->{content} =~ /^(..\x1Fa[^\x1F]+(?:\x1F[bcd][^\x1F]+)*)/ ) {
		$content = $1;
		$content =~ s/,$//;
		if ( $f1X0->{content} =~ /\x1F0([^\x1F]+)/ ) {
		    $sf0 = $1;
		}
	    }
	    else {
		die();
	    }
	}
    }

    if ( !$content ) {
	if ( $ten ) { # is band
	    # Add tarke such as "(yhtye)" after band's name etc.
	    # We just hope that $name refers to the FIN11 record...
	    if ( defined($name2tarke{$name}) ) {
		my $tarke = $name2tarke{$name};
		if ( $tarke eq "MONISELITTEINEN" ) {
		    print STDERR "WARNING\tAmbiguous name '$name' detected. Tarke not added.\n";
		}
		elsif ( $tarke ne '__TYHJÄ__' ) {
		    $name .= ' ('.$tarke.')';
		    if ( $debug ) {
			print STDERR "DEBUG\tAdded tarke to '$name'\n";
		    }
		}
	    }
	    $content = "0 \x1Fa$name";
	}
	else {
	    my $ind1 = ( $name =~ /,/ ? 1 : 0 );
	    	
	    # Change IND1 and name from "Etunimi Sukunimi" => "Sukunimi, Etunimi".
	    if ( $ind1 eq '0' && $name =~ s/^(\S+) (\S+)$/$2, $1/ ) {
		$ind1 = '1';
	    }
	    $content = "${ind1} \x1Fa$name";
	    
	    # TODO: check whether FIN11 auth record contains $c pseudonym
	    # $c: pseudonyms from Tempo data and FIN11:

	    if ( is_pseudonym($author_ref) ) {
		$content .= ",\x1Fcsalanimi";
	    }


	    # $d: birth and death TODO: use auth record if exists
	    if ( defined($author{'birth_year'}) ) {
		$content .= ",\x1Fd".$author{'birth_year'}.'-';
		if ( defined($author{'death_year'}) ) {
		    $content .= $author{'death_year'};
		}
	    }
	    elsif ( defined($author{'death_year'}) ) {
		$content .= ",\x1Fd-".$author{'death_year'}.'-';
	    }
	}
    }


    
    
    my @authors_functions = get_functions(\%author);
    if ( $#authors_functions > -1 ) {
	my $authors_functionstr = join(",\x1Fe", @authors_functions);
	$content .= ','; # NB! TODO "$d 1999-" -> omit ','
	$content .= "\x1Fe".$authors_functionstr;
    }
    $content .= "."; # NB! TODO "$d 1999-" -> omit '.'
    if ( defined($sf0) ) {
	$content .= "\x1F0".$sf0;
    }
    
    add_marc_field($marc_record_ref, $hundred.$ten.'0', $content);
}


sub compare_two_authors($$$$$) {
    # Returns the id of the better author.
    # The authors are called ruler and pretender here. If tie, ruler wins.
    
    # Songs and classical music
    my ( $is_classical_music, $is_host, $authors_ref, $ruler_id, $pretender_id ) = @_;
    #print STDERR "COMP IDS $ruler_id vs $pretender_id\n";
    my %authors = %{$authors_ref};
    #print STDERR Dumper(\%authors);
    my %ruler = %{$authors{$ruler_id}};
    my %pretender = %{$authors{$pretender_id}};

    if ( $debug ) {
	print STDERR "COMPARE ", $ruler{'name'}, " vs ", $pretender{'name'}, "\n";
    }
    my $rulers_score = $ruler{score}; # score_author(\%ruler, $is_classical_music, $is_host);
    my $pretenders_score = $pretender{score}; # score_author(\%pretender, $is_classical_music, $is_host);

    
#    foreach my $key ( sort keys %ruler ) {
#	print STDERR "RULER: $key => ", $ruler{$key}, "\n";
#    }
    if ( $rulers_score > $pretenders_score ) {
	return $ruler_id;
    }
    if ( $rulers_score < $pretenders_score ) {
	return $pretender_id;
    }
    # Equal rank! Base the decision on index in tempo JSON:
    if ( $ruler{'index'} <= $pretender{'index'} ) {
	return $ruler_id;
    }
    return $pretender_id;    

    # NB! We might need to rethink this for non-classic hosts...
    if ( 1 || $is_classical_music || !$is_host ) {
	for ( my $i=0; $i <= $#X00_scorelist; $i++ ) {
	    my $curr_funk = $X00_scorelist[$i];
	    if ( defined($ruler{$curr_funk}) ) {
		if ( !defined($pretender{$curr_funk}) ) {
		    if ( 0 && $debug ) {
			print STDERR " ", $ruler{'name'}, " is $curr_funk, and thus precedes ", $pretender{'name'}, "\n";
		    }
		    return $ruler_id;
		}

	    }
	    elsif ( defined($pretender{$curr_funk}) ) {
		if ( 0 && $debug ) {
		    print STDERR " ", $pretender{'name'}, " is $curr_funk, and thus precedes ", $ruler{'name'}, "\n";
		}
		return $pretender_id;
	    }
	}
    }
    else {
	# Fono took the first 190 field, but what if counterpair for Fono-190...
	die();
    }
    return $ruler_id;
}


sub get_best_remaining_author($$$) {
    my ( $is_classical_music, $is_host, $authors_ref ) = @_;
    my %authors = %{$authors_ref};
    my @author_ids = sort keys %authors;
    my $id = undef;
    for ( my $i=0; $i <= $#author_ids; $i++ ) {
	my $curr_id = $author_ids[$i];
	if ( !defined($id) ) {
	    $id = $curr_id;
	}
	else {
	    $id = compare_two_authors($is_classical_music, $is_host, $authors_ref, $id, $curr_id);
	}
    }
    return $id;

}


sub sanity_check_functions($) {
    my ( $authorsP ) = @_;
    foreach my $id ( sort keys %{$authorsP} ) {
	my $hits = 0;
	my %author = ${$authorsP}{$id};
	for ( my $i=0; $i <= $#X00e_scorelist && !$hits ; $i++ ) {
	    my $key = $X00e_scorelist[$i];
	    if ( defined($author{$key}) ) {
		die($key); # test
		$hits++;
	    }
	}
	# If no functions are found, mark as esittäjä (TODO: add translation of 'esittäjä' here):
	if ( !$hits ) {
	    if ( $debug ) {
		print STDERR "DEBUG\t", ${$authorsP}{$id}{name}, " has no funcs. Add 'esittäjä' func.\n";
	    }
	    ${$authorsP}{$id}{'esittäjä'} = '__SANITY_CHECK__';
	    die();
	}
    }
}
    


sub process_tempo_authors($$$$$) {
    my ( $prefix, $tempo_dataP, $marc_recordP, $is_classical_music, $is_host ) = @_;

    my %authors = get_tempo_authors($prefix, $tempo_dataP, $marc_recordP);
    


    #sanity_check_functions(\%authors);
    
    # Score each author:
    my $max = 0;
    my %seen;
    foreach my $auth_id ( sort keys %authors ) {
	my $score = score_author($authors{$auth_id}, $is_classical_music, $is_host);
	$authors{$auth_id}->{score} = $score;
	if ( $max < $score ) {
	    $max = $score;
	}
	if ( defined($seen{$score}) ) { $seen{$score} += 1; }
	else { $seen{$score} = 1; }
    }

    # Add 1XX author field:
    my $best_author_id = get_best_author(\%authors, $is_classical_music, $is_host);
    if ( defined($best_author_id) ) {
	my %curr_author = %{$authors{$best_author_id}};
	tempo_author_to_marc_field(\%curr_author, $marc_recordP, '1');
	delete $authors{$best_author_id};
    }

    # Add 7XX author fields:
    while ( keys %authors ) {
	#print STDERR Dumper(\%authors);
	my $curr_author_id = get_best_remaining_author($is_classical_music, $is_host, \%authors);
	my %curr_author = %{$authors{$curr_author_id}};

	#enrich_tempo_author_with_fin11_data(\%curr_author);
	tempo_author_to_marc_field(\%curr_author, $marc_recordP, '7');

	delete $authors{$curr_author_id};
    }
        
    # Tempo title => marc 245, possibly 240, 031, 500 (etc.?) as well...
}

#sub potential_human_name($) {
#    my $name = shift;
#
#    if ( $name =~ /^((${etunimi_regexp}|${nimikirjain}\.) )+(${sukunimi_regexp})$/ ||
#	 $name =~ /\'${etunimi_regexp}\'/ ) {	 
#	return 1;
#    }
#    return 0;
#}


#sub get_author_parameter($$) {
#    my ( $author_ref, $parameter ) = @_;	
#    if ( defined(${$author_ref}{$parameter}) ) {
#	return ${$author_ref}{$parameter};
#    }
#    return undef;
#}



1;
