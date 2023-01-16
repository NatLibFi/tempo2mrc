#
# tempo_artists_ownerships.pm - process author informations
#
# Handle both artists_publishing_ownerships and artists_master_ownerships.
# Used via provess_tempo_authors).

use strict;
use tempo_utils;
use Data::Dumper;
use nvolk_utf8; # unicode_fixes2
use tempo_asteri;

my $debug = 1;
my $robust = 0;



my %X00_score; # order between different X00 fields.
$X00_score{'säveltäjä'} = 100;
$X00_score{'sanoittaja'} = 90;
$X00_score{'sovittaja'} = 80;
$X00_score{'editointi'} = 70; # NB! TODO: Not really supported currently...
$X00_score{'esittäjä'} = 60;
$X00_score{'johtaja'} = 50;
#$X00_score{'orkesterinjohtaja'} = 60; # Use johtaja


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

my $iso_kirjain =  "(?:[A-Z]|Á|Å|Ä|Ç|É|Md|Ø|Ó|Õ|Ö|Ø|Š|Ü|Ž)"; # Md. on mm. Bangladeshissä yleinen lyhenne M[ou]hammedille...
#my $pikkukirjain =  Encode::encode('UTF-8', "[a-z]|a\-a|à|á|å|ä|æ|č|ç|ć|è|é|ë|ì|í|ï|ñ|ń|ò|ó|õ|ö|š|ù|ú|ü|ỳ|ý|ø|ß");
my $pikkukirjain =  "(?:[a-z]|a\-a|à|á|â|å|ã|ä|æ|ă|ā|č|ç|ć|è|é|ê|ë|ě|ė|ȩ|ì|í|ï|î|ī|ł|ñ|ń|o-o|ò|ó|õ|ö|ô|š|ş|ð|ù|ú|ü|û|ū|ỳ|ý|ÿ|ž|ø|ß)";

my $aatelisalku = "(?:af [A-Z]|Al [A-Z]|[Dd]a [A-Z]|[dD]'[A-Z]|[dD]all\'[A-Z]|[Dd]e [A-Z]|De[A-Z]|de la [A-Z]|del [A-Z]|dela [A-Z]|den [A-Z]|[Dd]i [A-Z]|du [A-Z]|Fitz[A-Z]|[Ll]e ?[A-Z]|Mc [A-Z]|Ma?c[A-Z]|O'[A-Z]|St[.] [A-Z]|ten [A-Z]|ter [A-Z]|[vV][ao]n [A-Z]|[Vv]an de [A-Z]|[vV]an den [A-Z]|[Vv][ao]n [dD]er [A-Z]|[Vv]an't [A-Z]|von dem [A-Z]|von und zu [A-Z])";


my $sukunimen_alku = "(?:$aatelisalku|$iso_kirjain)";
my $sukunimen_loppu = "(?:$pikkukirjain(?:\-$iso_kirjain$pikkukirjain|\-$aatelisalku$pikkukirjain)?)+";

my $sukunimi_regexp = "$sukunimen_alku$sukunimen_loppu";
my $etunimen_loppu = "(?:$pikkukirjain(?:\-$iso_kirjain$pikkukirjain)?)+";
my $nimikirjain = "(?:$iso_kirjain|${iso_kirjain}[.]-$iso_kirjain|Ch|Sz|Th|Yu)";
my $etunimi_regexp = "(?:$iso_kirjain$etunimen_loppu|Kari'm)";



my $dd_regexp = get_dd_regexp();
my $mm_regexp = get_mm_regexp();
my $yyyy_regexp = get_yyyy_regexp();

my $rejectables = "(?:Anonyymi|Kansan(sävelmä|perinne|runo|laulu)|Kanteletar|Koraalitoisinto|Negro spiritual|Nimeämätön|Raamattu|Ruotsin kirkon virsikirja|Tuntematon|Virsikirja)";


# We should really trust our auth records, and not use this legacy list:
my $human_names = "2pac/66KES88/Aksim 2000/Centro 53/js15/JS16/Jussi 69/Jyrki 69/Kid1/Kurt 49/Melody Boy 2000/Mars 31 Heaven/M1tsQ/Sairas T/Steen1/Tactic L/T1tsQ/Vilunki 3000";
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


sub normalize_name($) {
    my ( $name ) = @_;

    # Pre- and decompose:
    $name = unicode_fixes2($name, 1);
    
    # 3 "full_name": "Neville 'Noddy' Holder",
    # 3 "full_name": "Kalervo 'Kassu' Halonen",
    # 2 "full_name": "William 'Bill' Cook",
    # 2 "full_name": "Ville 'Little Willie' Mehto",
    # 2 "full_name": "Pasi 'Poju' Heinonen",
    # 2 "full_name": "Kyösti 'Adi' Remes",
    # 2 "full_name": "Ville 'Little Willie' Mehto" # NB! Two quoted names
    # 1 "full_name": "Markus 'Marzi' Nyman",
    # 1 "full_name": "Juha 'Jay' Kortehisto",
    # 1 "full_name": "James 'Jimmy' Lea",
    $name =~ s/ '($iso_kirjain$pikkukirjain+( $iso_kirjain$pikkukirjain+)?)' / "$1" /;

    return $name;
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
    $name =~ s/ +$//;
    
    # '4th Line Horn Quartet (4th Line-käyrätorvikvartetti)' =>
    # '4th Line Horn Quartet' =>
    while ( $name =~ s/(\S) *(\([^=\)][^\)]+\)) *$/$1/ ) { 
	print STDERR "Remove '$2' from '$name'\n";
    }

    if ( $name =~ /(\/|\()/ ) {
	print STDERR "WARNING\tCheck '$name'\n";
    }

    
    $name = &normalize_name($name);
    $data{'name'} = $name;
    
    if ( $debug && 0 ) {
	foreach my $key ( sort keys %data ) {
	    print STDERR "AUTHOR DATA $key '", $data{$key}, "'\n";
	}
    }
    return %data;
}


sub merge_names($$) {
    my ( $nameP1, $nameP2 ) = @_;
    # Boldly assume that same name means same person
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
	elsif ( $key eq 'index' ) {
	    if ( ${$nameP1}{$key} > $val ) {
		${$nameP1}{$key} = $val;
		print STDERR "RESET INDEX: ", ${$nameP1}{'name'}, " = $val\n";
	    }
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
    'conductor' => 'johtaja', # TODO: better term? orkesterinjohtaja',
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
	if ( scalar(@keys) > 0 ) {
	    print STDERR "WARNING\tREMAINING KEYS FOR '$prefix':\n";
	    foreach my $curr_key ( @keys ) {
		my $val = $remaining_keys{$curr_key};
		print STDERR " KEY '$curr_key'\tVAL '$val'\n";
	    }
	}
    }
}

sub johtaja_hack($) {
    my $author_ref = shift();

    foreach my $key ( keys %{$author_ref} ) {
	# Hacky: delete generic 'esittäjä' if we have more specific function:
	# (T.M. did not want $e esittäjä, $e johtaja for Osmo Vänskä,
	#  just $e johtaja)
	# (In future this list may or may nor grow.)
	if ( defined(${$author_ref}{$key}{'johtaja'}) ||
	     defined(${$author_ref}{$key}{'laulaja'}) ) {
	    delete ${$author_ref}{$key}{'esittäjä'}; 
	}
	# However, we don't want to use 'laulaja' so put the 'esittäjä' key
	# back in:
	if ( defined(${$author_ref}{$key}{'laulaja'}) ) {
	    delete ${$author_ref}{$key}{'laulaja'};
	    ${$author_ref}{$key}{'esittäjä'} = 'laulaja';
	}
    }
}

sub get_tempo_authors($$$) {
    my ( $head, $arr_ref, $marc_record_ref ) = @_;

    my %authors;
    # Should artists_publishing_ownerships[0] come before
    # artists_master_ownerships[0] or vice versa?
    # Currently index (=position) is shared.
    my @prefixes = ( "/$head/artists_publishing_ownerships", "/$head/artists_master_ownerships" );
    for ( my $i=0; $i < scalar(@prefixes); $i++ ) {
	my $curr_prefix = $prefixes[$i];
	my $index = 0;
	my $index2 = ( $curr_prefix =~ /master/ ? 100 : 0 );
	my @data;
	print STDERR "FOO: '$curr_prefix'\n";
	while ( @data = extract_keys($curr_prefix."[$index]", $arr_ref) ) {
	    print STDERR "BAR $curr_prefix\[$index]\n";
	    if ( scalar(@data) > 0 ) {
		# remove key/ from start:
		@data = map { substr($_, length($curr_prefix."[$index]")+1) } @data; 
		# Store artist-specific data to %foo:
		my %foo;
		for ( my $j=0; $j < scalar(@data); $j++ ) {
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
		    $name_data{'index'} = $index + $index2;
		    if ( $new_id ) {
			$authors{$id} = \%name_data;
			print STDERR "INDEX: ", $curr_name, " = ", $authors{$id}{'index'}, "\n";
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

		for ( my $j=0; $j < scalar(@deletables); $j++ ) {
		    my $curr_key = $deletables[$j];
		    delete $foo{$curr_key};
		}

		# Handle, delete or complain about unused (undeleted) keys:
		my @keys = sort keys %foo;
		if ( scalar(@keys) > 0 ) {
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
			    # We try to use 'yhtye' here as an indicator
			    # of non-humanness... Didn't work out as humans
			    # can have it as well...
			    # Remove this here and in
			    # educated_guess_is_person($)??
			    if ( $val eq 'yhtye' ) {
				$authors{$id}{'yhtye'} = 1;
			    }
			    elsif ( $val eq 'johtaja' || $val eq 'kuoronjohtaja' || $val eq 'orkesterinjohtaja' ) {
				$authors{$id}{'johtaja'} = $val;
			    }
			    elsif ( $val eq 'ym' ) {
				# ignorable shit
			    }
			    elsif ( $debug ) {
# Can we use these for something?
#				if ( !defined($authors{$id}{'instruments'}) ) {
#				    $authors{$id}{'instruments'} = $val;
#				}
#				else {
#				    $authors{$id}{'instruments'} .= "\t".$val;
#				}

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

    johtaja_hack(\%authors);
    
    return %authors;
}


sub get_functions($) {
    my $author_ref = shift();
    my %author = %{$author_ref};

    my @e_array = ();
    
    # Go thru X00$e fields from best to worst. Add hits.
    # This way the top-priority function comes first.
    for ( my $i=0; $i < scalar(@X00e_scorelist); $i++ ) {
	my $curr_funk = $X00e_scorelist[$i];
	if ( defined($author{$curr_funk}) ) {
	    $e_array[scalar(@e_array)] = $curr_funk;
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
	    main::add_marc_field($marc_recordP, '500', $content);
	    delete ${$authorsP}{$key};
	}
    }
}


sub score_author($$$) {
    my ( $author_ref, $is_classical_music, $is_host ) = @_;
    my %author = %{$author_ref};
    if ( 1 || $is_classical_music || !$is_host ) {
	for ( my $i=0; $i < scalar(@X00_scorelist); $i++ ) {

	    my $curr_funk = $X00_scorelist[$i];
	    if ( defined($author{$curr_funk}) ) {

		my $score = $X00_score{$curr_funk};
		print STDERR "SCORE: ", $author{name}, "/$curr_funk=$score\n";
		return $score;
	    }
	}
    }
    else {
	# Fono took the first 190 field, but what if counterpair for Fono-190...
	die();
    }
    return 0;
}




sub function2ids($$) {
    my ( $authors_ref, $function ) = @_;
    my %authors = %{$authors_ref};
    
    my @all_auth_ids = sort { $authors{$a}{'index'} <=> $authors{$b}{'index'} } keys %authors;

    my @esittaja_auth_ids = ();
    foreach my $auth_id ( @all_auth_ids ) {
	if ( defined($authors{$auth_id}->{$function}) ) {
	    $esittaja_auth_ids[scalar(@esittaja_auth_ids)] = $auth_id;
	}
    }


    return @esittaja_auth_ids;
}	


sub get_best_author($$$) {
    my ( $authors_ref, $is_classical_music, $is_host ) = @_;
    my %authors = %{$authors_ref};
    # Unlike

    my @auth_ids = sort { $authors{$b}{'index'} <=> $authors{$a}{'index'} } keys %authors; # TODO: How about getting 'em in some priority order?

    # If there's only one author in the record, make it 1XX:
    if ( scalar(@auth_ids) == 1 ) {
	return $auth_ids[0];
    }

    # Debugging crap
    if ( 0 ) {
	foreach my $auth_id ( @auth_ids ) {
	    my $var = $authors{$auth_id};
	    my %hash = %{$var};
	    foreach my $key ( sort keys %hash ) {
		print STDERR "GBA$is_classical_music $key: '", $hash{$key}, "'\n";
	    }
	    print STDERR "\n";
	}
    }


    # Comp: use first composer (or nothing):
    if ( !$is_host ) {
	my @composer_ids = function2ids($authors_ref, 'säveltäjä');
	if ( scalar(@composer_ids) > 0 ) {
	    return $composer_ids[0];
	}
	return undef;
    }
    
    # Hosts
    if ( $is_classical_music ) {
	# TM: "Ohje on, että taidemusiikkiemossa 1XX:ään tulee ainoa pääesittäjä, jos julkaisun teoksilla ei ole yhtä yhteistä säveltäjää (tämä olisi kai ilmoitettu Tempo-emossakin)."	
	my @composer_ids = function2ids($authors_ref, 'säveltäjä');
	if ( scalar(@composer_ids) == 1 ) {
	    return $composer_ids[0];
	}
    }

    # Use main performer. Note that we no longer have distinction between main
    # and other performers! (= Fono fields 190 and 191).
    # Tempo lumps them all together...
    my @performer_ids = function2ids($authors_ref, 'esittäjä');

    # If there's one performer use him/her/them:
    if ( scalar(@performer_ids) == 1 ) {
	return $performer_ids[0];
    }
    return undef;
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

    #read_minified_fin11(); }
 
    if ( scalar(@{$cand_records_ref}) == 0 ) {
	return undef;
    }
    if ( scalar(@{$cand_records_ref}) == 1 ) {
	# Can we be sure, that the match is correct?
	# If Tempo person has no birth nor death year,
	# We don't dare to use this for adding $0.

	my $f100 = ${$cand_records_ref}[0]->get_first_matching_field('100');
	if ( $f100 ) {
	    # However, we dare to use the Asteri 100 name...
	    my $f100a = $f100->get_first_matching_subfield('a');
	    $f100a =~ s/,$//;
	    if ( $f100a ne ${$author_ref}{'name'} ) {
		print STDERR "RENAME '", ${$author_ref}{'name'}, "' as '$f100a'\n";
		${$author_ref}{'name'} = $f100a;
	    }
	    
	    if ( !defined(${$author_ref}{'birth_year'}) &&
		 !defined(${$author_ref}{'death_year'}) ) {
		if ( $debug ) {
		    print STDERR "NB\tDon't map ", ${$author_ref}{'name'}, " to Asteri, since we don't have a birth/death year in Tempo data.\n";
		    #print STDERR Dumper($author_ref), "\n";
		}


		return undef;
	    }
	}
	return ${$cand_records_ref}[0];
    }
    print STDERR "Multiple candidates remains. Skip.\n";
    foreach my $record ( @{$cand_records_ref}) {
	my $tmp = $record->toString();
	$tmp =~ s/^/  /gm;
	print STDERR $tmp;
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

    # Matias Sassali had this defined, so we can not use this, can we...
    if ( 0 && defined($author{'yhtye'}) ) {
	return 0;
    }


    
    my $name = $author{'name'};

    if ( $name =~ / "$iso_kirjain$pikkukirjain+( $iso_kirjain$pikkukirjain+)?" / ) {
	# Kutsumanimi
	return 1;
    }
    
    if ( $name =~ /[0-9]/ ) {
	if ( defined($human_names{$name}) ) {
	    # NB! No need to list the ones with an authority record
	    return 1;
	}
	if ( $debug ) {
	    print STDERR "Educated X00/X10 guess for '$name': band (reason: digits)\n";
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

    if ( $name =~ /('s |choir|ensemble|kuoro|kvintett|orchester|orkester|yhtye)/i ||
	 $name =~ /((^| )(and|band|duo|ja|och|of|orchestra|project|the|trio)($| ))/i ||
	 # Too long to be noble 'von' particle:
	 $name =~ / ($pikkukirjain{7,})$/ ||
	 $name =~ /^(\S+ $pikkukirjain+)$/ || # "Suomen peli"
	 $name =~ /^($iso_kirjain{3,})/ ) {
	if ( $debug ) {
	    print STDERR "Educated X00/X10 guess for '$name': band (reason: '$1')\n";
	}
	return 0;
    }
    
    if ( $debug ) {
	print STDERR "Educated X00/X10 guess for name '$name': person (reason: default)\n";
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

    #read_minified_fin11();
    
    # Pseudonym as per Tempo:
    if ( defined(${$author_ref}{'pseudonym'}) ) { # Tempo
	return 1;
    }
    return 0;
}

sub X00_ind1_and_subfield_a($) {
    my ( $name ) = @_;
    if ( $name =~ /,/ ) {
	return "1 \x1Fa$name";
    }

    # "Jay Who?"
    if ( $name =~ /^(DJ|MJ|VJ|Mr\.) / ||
	 $name =~ /(\?|\!)$/ ) { 
	return "0 \x1Fa$name";
    }
    # Change IND1 and name from "Etunimi Sukunimi" => "Sukunimi, Etunimi".
    if ( $name =~ s/^($etunimi_regexp(?: $etunimi_regexp| $nimikirjain\.)?(?: af| de| de la| le| ten| van| van de[mnr]?| von| von und zu)?) ($iso_kirjain$sukunimen_loppu)$/$2, $1/ ||
	 # $nimikirjain.$nimikirjain since "Eli Anne K.G Eira", FFS.
	 # $nimikirjain\. since "Roy C Bennett"
	 # P-K Keränen
	 $name =~ s/^((?:$etunimi_regexp|$nimikirjain\.|JP|OP|P-K)(?: $etunimi_regexp| $nimikirjain\.?| $nimikirjain\.$nimikirjain| '$etunimi_regexp'| $nimikirjain\-$nimikirjain)*) ($sukunimi_regexp)$/$2, $1/ ) {
	return "1 \x1Fa$name";
    }

    # Single name: default to forename
    if ( $name !~ /\s/ ) {
	if ( $name =~ /(heimo|la|lä|nen|salo|ström)$/ ) { die($name); }
	return "1 \x1Fa$name";
    }

    if ( $name =~ /^$etunimi_regexp $iso_kirjain$/ ) {
	# Jannika B etc
	return "0 \x1Fa$name";
    }
    if ( $name =~ /^$etunimi_regexp $iso_kirjain\.?$/ ||
	# Sorry hacks:
	 $name =~ /^(Ramses II)$/ ) {
	if ( !$robust && $name !~ /^(Joel L\.|Ramses II)$/ ) {
	    die($name);
	}
	return "0 \x1Fa$name";
    }

    if ( $debug ) {
	print STDERR "Unhandled name order: $name\n";
    }
    
    if ( $name =~ s/^(.*) (\S+)/$2, $1/ && $debug ) {
	print STDERR "Rotated: $name\n";
    }


    # Fallback
    return "1 \x1Fa$name";
}

sub tempo_author_to_marc_field($$$) {
    my ( $author_ref, $marc_record_ref, $hundred ) = @_;
    my %author = %{$author_ref};

    my $name = $author{'name'};

    my @cand_records = &name2auth_records($name);
    my @alt_cand_records = &alt_name2auth_records($name);
    my $n_cands = scalar(@cand_records);
    if ( $debug ) {
	print STDERR "author ($name) => asteri: $n_cands cand(s) and ", scalar(@alt_cand_records), " alt cand(s) found.\n";
	foreach my $cand_record ( @cand_records ) {
	    my $id = $cand_record->get_first_matching_field('001');
	    print STDERR "  ID: ", $id->{content}, "\n";
	}
    }
    #if ( scalar(@cand_records) > 0 ) { die(); } # test: found something


    if ( $name =~ /ja\/tai/ ) { die(); } # Fono crap. Sanity check: do we see this also in Tempo...
    
    my $must_be_human = tempo_is_definitely_human($author_ref);
    if ( $must_be_human ) {
	# TODO: remove non-humans from @records;
	@cand_records = grep { $_->get_first_matching_field('100') } @cand_records;
	@cand_records = remove_birth_and_death_mismatches($author_ref, \@cand_records);

	@alt_cand_records = grep { $_->get_first_matching_field('100') } @alt_cand_records;
	@alt_cand_records = remove_birth_and_death_mismatches($author_ref, \@alt_cand_records);
    }

    if ( $n_cands != scalar(@cand_records) ) {
	if ( $debug ) {
	    print STDERR "  after filtering", scalar(@cand_records), " cand(s) found.\n";
	}
	$n_cands = scalar(@cand_records);
    }

    
    
    my $asteri_record = tempo_author2asteri_record($author_ref, \@cand_records);


    my $records4tens_ref = ( scalar(@cand_records) > 0 ? \@cand_records : \@alt_cand_records);
    
    my $ten = get_tens($author_ref, $asteri_record, $records4tens_ref);

    print STDERR "A2M $name BAND? X${ten}0, ASTERI: ", ($asteri_record ? 'Y':'N'), ", $n_cands\n";
    my ( $content, $sf0 ) = &asteri_record2content($asteri_record); # IND1, IND2 & $abcd0

    if ( !$content ) {
	if ( $ten ) { # is band
	    # Add tarke such as "(yhtye)" after band's name etc.
	    # We just hope that $name refers to the FIN11 record...
	    my $tarke = name2tarke($name);
	    if ( defined($tarke) ) {
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

	    $content = "2 \x1Fa$name";
	}
	else {
	    # Not using Asteri record:
	    $content = X00_ind1_and_subfield_a($name);
	    
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
    if ( scalar(@authors_functions) > 0 ) {
	my $authors_functionstr = join(",\x1Fe", @authors_functions);
	$content .= ','; # NB! TODO "$d 1999-" -> omit ','
	$content .= "\x1Fe".$authors_functionstr;
    }
    $content .= "."; # NB! TODO "$d 1999-" -> omit '.'
    if ( defined($sf0) ) {
	$content .= "\x1F0".$sf0;
    }

    if ( 0 && $debug ) { # For debugging X00 order
	my $index = $author{'index'};
	$content .= "\x1F9INDEX=$index";
    }
    
    main::add_marc_field($marc_record_ref, $hundred.$ten.'0', $content);
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


    my $rulers_score = $ruler{score}; # score_author(\%ruler, $is_classical_music, $is_host);
    my $pretenders_score = $pretender{score}; # score_author(\%pretender, $is_classical_music, $is_host);
    
    if ( $debug ) {
	print STDERR "COMPARE ", $ruler{'name'}, " ($rulers_score) vs ", $pretender{'name'}, " ($pretenders_score)\n";
    }
    
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

#    # NB! We might need to rethink this for non-classic hosts...
#    if ( 1 || $is_classical_music || !$is_host ) {
#	for ( my $i=0; $i < scalar(@X00_scorelist); $i++ ) {
#	    my $curr_funk = $X00_scorelist[$i];
#	    if ( defined($ruler{$curr_funk}) ) {
#		if ( !defined($pretender{$curr_funk}) ) {
#		    if ( 0 && $debug ) {
#			print STDERR " ", $ruler{'name'}, " is $curr_funk, and thus precedes ", $pretender{'name'}, "\n";
#		    }
#		    return $ruler_id;
#		}
#
#	    }
#	    elsif ( defined($pretender{$curr_funk}) ) {
#		if ( 0 && $debug ) {
#		    print STDERR " ", $pretender{'name'}, " is $curr_funk, and thus precedes ", $ruler{'name'}, "\n";
#		}
#		return $pretender_id;
#	    }
#	}
#    }
#    else {
#	# Fono took the first 190 field, but what if counterpair for Fono-190...
#	die();
#    }
#    return $ruler_id;
}


sub get_best_remaining_author($$$) {
    my ( $is_classical_music, $is_host, $authors_ref ) = @_;
    my %authors = %{$authors_ref};
    my @author_ids = sort { $authors{$a}{'index'} <=> $authors{$b}{'index'} } keys %authors;
    my $id = undef;
    for ( my $i=0; $i < scalar(@author_ids); $i++ ) {
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
	for ( my $i=0; $i < scalar(@X00e_scorelist) && !$hits ; $i++ ) {
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
