use nvolk_marc21;
use kk_marc21_field;
use strict;
use LWP::Simple;

# yso-all: yso + yso-paikat + yso-aika
sub normalize_yso_lexicon_name($) {
    my ( $lex ) = @_;
    # yso-paikat/fin => yso-fin and yso-paikat => yso
    if ( defined($lex) ) {
	$lex =~ s/^yso-(aika|paikat|all)\/(fin|swe|eng)/yso\/yso-$2/ ||
	    $lex =~ s/^yso-(aika|paikat|all)$/yso/;
    }
    return $lex;
}

our $paikkakunta_regexp = "(?:Alavieska|Espoo|Etelä-Pohjanmaa|Gotlanti|Hailuoto|Haukipudas|Helsinki|Ii|Joensuu|Jomala|Jyväskylä|Kaarina|Kainuu|Kajaani|Kalajoki|Karjala|Karkku|Kempele|Kiiminki|Kollaa|Kumlinge|Kuopio|Kuusamo|Lahti|Laitila|Lappi|Liminka|Linnanmaa|Lontoo|Luhanka|Maakalla|Merijärvi|Muhos|Naantali|Nivala|Oulainen|Oulu|Oulunsalo|Paanajärvi|Parainen|Pattijoki|Petroskoi|Petsamo|Pietari|Piippola|Pulkkila|Pohjanmaa|Raahe|Rantsila|Rooma|Salla|Salo|Sastamala|Seinäjoki|Sottunga|Sund|Suomussalmi|Tampere|Turku|Tolvajärvi|Tyrnävä|Tyrvää|Vaasa|Vammala|Vehmaa|Vihanti|Venetsia|Ylihärmä|Zürich)";

our $maa_regexp = "(?:Alankomaat|Egypti|Eesti|Englanti|Espanja|Hollanti|Intia|Irak|Iran|Irlanti|Islanti|Iso-Britannia|Italia|Itävalta|Japani|Kanada|Kiina|Kreikka|Latvia|Liettua|Meksiko|Neuvostoliitto|Norja|Pohjoismaat|Puola|Ranska|Ruotsi|Saksa|Suomi|Sveitsi|Tanska|Tsekki|Tsekkoslovakia|Unkari|Venäjä|Vietnam|Viro|Yhdysvallat)";

# Saaret, mantereet yms.
our $muut_paikat_regexp = "(?:Eurooppa|Levi)";
our $ort_regexp = "(?:Asien|Finland|Kaskö|Närpes|Sydamerika)";

our $finto_debug = 0;
sub get_maa_regexp() { return $maa_regexp; }
sub get_muut_paikat_regexp() { return $muut_paikat_regexp; }
sub get_ort_regexp() { return $ort_regexp; }
sub get_paikkakunta_regexp() { return $paikkakunta_regexp; }

our %loaded_lexicons;

our %lexica;

# New, generic, version

my @supported_lexica = ( 'mts', 'seko', 'slm', 'soto', 'yso', 'yso-aika', 'yso-paikat' );

my %supported_labels;
my @pref_alt = ( 'pref', 'alt' );
$supported_labels{'kauno'} = [@pref_alt];
$supported_labels{'kaunokki'} = [@pref_alt];
$supported_labels{'mts'} = [@pref_alt];
$supported_labels{'seko'} = [@pref_alt];
$supported_labels{'slm'} = [@pref_alt];
$supported_labels{'soto'} = [@pref_alt];
$supported_labels{'yso'} = [@pref_alt];
$supported_labels{'yso-aika'} = [@pref_alt];
$supported_labels{'yso-paikat'} = [@pref_alt];

my %supported_languages;
my @fin_swe = ( 'fin', 'swe' );
$supported_languages{'kauno'} = [@fin_swe];
$supported_languages{'kaunokki'} = [@fin_swe];
$supported_languages{'mts'} = [@fin_swe];
$supported_languages{'slm'} = [@fin_swe];
$supported_languages{'seko'} = [('fin')];
$supported_languages{'soto'} = [('fin')];
$supported_languages{'yso'} = [@fin_swe];
$supported_languages{'yso-aika'} = [@fin_swe];
$supported_languages{'yso-paikat'} = [@fin_swe];

my %url_base;
$url_base{'kauno'} = 'http://www.yso.fi/onto/kauno/p';
# kaunokki omitted on purpose
$url_base{'mts'} = 'http://urn.fi/URN:NBN:fi:au:mts:m';
$url_base{'slm'} = 'http://urn.fi/URN:NBN:fi:au:slm:s';

$url_base{'soto'} = 'http://www.yso.fi/onto/soto/p';
$url_base{'yso'} = 'http://www.yso.fi/onto/yso/p';
$url_base{'yso-aika'} = 'http://www.yso.fi/onto/yso/p';
$url_base{'yso-paikat'} = 'http://www.yso.fi/onto/yso/p';

sub get_url_base($) {
    my $lex = shift;
    if ( defined($url_base{$lex}) ) {
	return $url_base{$lex};
    }
    return undef;
}

# Init generic lexicon:
foreach my $curr_lex ( @supported_lexica ) {
    $lexica{$curr_lex} = ();
    $lexica{$curr_lex}{'yso'} = (); # used currently only by soto
    # Skos contains alt/pref first and then lang in it...
    # Thus we do this here a bit counterintuitively
    foreach my $curr_label ( @{$supported_labels{$curr_lex}} ) {
	$lexica{$curr_lex}{$curr_label} = ();
	#print STDERR "ADD $curr_lex/$curr_label...\n";
	foreach my $curr_lang ( @{$supported_languages{$curr_lex}} ) {
	    #print STDERR "ADD $curr_lex/$curr_label/$curr_lang\n";
	    $lexica{$curr_lex}{$curr_label}{$curr_lang} = ();
	    $lexica{$curr_lex}{$curr_label}{$curr_lang}{'term2id'} = ();
	    $lexica{$curr_lex}{$curr_label}{$curr_lang}{'id2term'} = ();
	}
    }
}

sub lang2_to_lang3($) {
    my $lang2 = shift;
    if ( $lang2 eq 'en' ) { return 'eng'; }
    if ( $lang2 eq 'fi' ) { return 'fin'; }
    if ( $lang2 eq 'sv' ) { return 'swe'; }
    return undef;
}


# // lexicon_terms{lexicon_name}{language}{pref}{alt}{term}

# TODO: 'kala'

# TODO:  rm -fv tmp/* ;  ./melinda_fixer.perl update-test tmp pe_ilta_ids.txt 2>&1 | tee tmp8.txt

# TODO: Fennica (hackit mukaan?)
#
# TILASTO TODO: baletit

# Ajettiinko 'oppaat (teokset)' 655:n kanssa jo?

# TODO: lukemistot (655 mukaan)... (NB! myös uusi sääntö)
#
# TODO: "kur "
# maine osavaltio? 
# kemi allars kemia vs Kemi

# systematiikka => "systematiikka (biologia)"?

# Tuplien poisto.
# Tiettyjen osajonojen poisto
# Nimien siivoamista 650- ja 653-kentistä, jos 600-kentässä on sama nimi
# -- TODO: 610, 630?
# -- 653 -> 650, jos ketju ok (ysa, allärs)

# ysa -> allärs, allärs -> ysa
# -- jos ketju väittää olevansa Allärsiä, mutta ei ole ja on laillista Ysaa,
#    niin muutetaan $2 ysaksi
# -- sama toisin päin
# -- myös altLAbel sallitaan
# -- vain osa korjattu, tarkistettu esim. tapauket, joissa ysa-ketjussa on å-kirjain tai kaksi samaa vokaalia peräkkäinen Allärs.
#
#
# Jos muutoksia, niin samalla korjataan tietueen ääkköset...
# 
# ysa->allärs gi#, gd...


# TODO: /tmp/bad_terms.txt
use constant {
    SKIP_ALT => 0,
    USE_ALT => 1 };


# NB! 
my %lexicon_name2download_url = (
    'allars' =>     'http://api.finto.fi/download/allars/allars-skos.ttl',
    'kauno' =>      'https://finto.fi/rest/v1/kauno/data?format=text/turtle',
    'kaunokki' =>   'https://finto.fi/rest/v1/kaunokki/data?format=text/turtle',
    'mts' =>        'https://finto.fi/rest/v1/mts/data?format=text/turtle',
    'seko' =>       'http://api.finto.fi/download/seko/seko-skos.ttl',
    'slm' =>        'https://finto.fi/rest/v1/slm/data?format=text/turtle',
    'soto' =>       'https://finto.fi/rest/v1/soto/data?format=text/turtle',
    'yso' =>        "http://api.finto.fi/download/yso/yso-skos.ttl",
    'yso-aika' =>   "http://api.finto.fi/download/yso-aika/yso-aika-skos.ttl",
    'yso-paikat' => 'http://api.finto.fi/download/yso-paikat/yso-paikat-skos.ttl'
    );


sub use_finnish_lexicon_name($) {
    my ( $lexicon_name ) = @_;

    if ( $lexicon_name eq 'bella' ) { $lexicon_name = 'kaunokki'; }
    if ( $lexicon_name eq 'cilla' ) { $lexicon_name = 'musa'; }

    return $lexicon_name;
}

sub lexicon_name2download_url($) {
    my ( $lexicon_name ) = @_;

    $lexicon_name = use_finnish_lexicon_name($lexicon_name);

    if ( !defined($lexicon_name2download_url{$lexicon_name}) ) { die($lexicon_name); }
    return $lexicon_name2download_url{$lexicon_name};
}

my %lexicon_name2filename = (
    'kauno' => 'kauno-skos.ttl',
    'kaunokki' => 'kaunokki-skos.ttl',
    'mts' => 'metatietosanasto-skos.ttl',
    'slm' => 'slm-skos.ttl',
    'soto' => 'soto-skos.ttl',
    'yso' => 'yso-skos.ttl',
    'yso-aika' => 'yso-aika-skos.ttl',
    'yso-paikat' => 'yso-paikat-skos.ttl'
    );

sub lexicon_name2filename($) {
    my ( $lexicon_name ) = @_;

    $lexicon_name = use_finnish_lexicon_name($lexicon_name);

    if ( !defined($lexicon_name2filename{$lexicon_name}) ) { die($lexicon_name); }
    return $lexicon_name2filename{$lexicon_name};
}

# TODO: fix $ykl


our %asteri110;
our $asteri_loaded = 0;

sub asteri110content_to_610($) {
    my $content = shift();
    my $ind1 = substr($content, 0, 1);
    my $sf_a = marc21_field_get_subfield($content, 'a');
    if ( $content =~ /\x1Fb/ ) { die(); }
    my $sf_0 = marc21_field_get_subfield($content, '0');
    unless ( $sf_a =~ /\.$/ ) {
        $sf_a .= ".";
    }
    return $ind1."4\x1Fa".$sf_a."\x1F0".$sf_0;
}


sub is_asteri110code($) {
    my $term = shift();
    if ( !$asteri_loaded ) {
        print STDERR "Loading 110 data from Asteri. Please wait.\n";
        $asteri_loaded = 1;
        my $text = &_read_file("/dev/shm/index/asteri/fin11.seq");
        my @lines = split(/\n/, $text);
        my $hits = 0;
        for ( my $i=0; $i <= $#lines; $i++ ) {
            my $curr_line = $lines[$i];
            if ( $curr_line =~ /^\d+ 110(.. L \$\$a([^\$]+)\$\$0\(FIN11\)[0-9]{9})$/ ) {
                $hits++;
                my $data = $1;
                my $name = $2;
                $data =~ s/ L //;
                $data =~ s/\$\$/\x1F/g;

                if ( defined($asteri110{$name}) ) {
                    die();
                }
                else {
                    $asteri110{$name} = $data;
                }
            }
        }
        print STDERR "Number of 110 fields loaded from Asteri: $hits\n";
    }
    # Huoh-hacks...
    if ( $term eq 'Tampereen yliopisto' ) {

        $term = 'Tampereen yliopisto (1966-2018)';
        print STDERR "Rename to '$term' as per Asteri.\n";
    }
    if ( defined($asteri110{$term}) ) {
        my $tmp = $asteri110{$term};
        print STDERR "Asteri: $term matches 110 '$tmp'\n";
        return $tmp;
    }
    return undef;
}

sub finto_composition($) {
    my $keyword = shift();
    # lexicons use compound versions of various chars
    $keyword =~ s/á/á/g;
    $keyword =~ s/ā/ā/g;
    $keyword =~ s/é/é/g;
    $keyword =~ s/ė/ė/g;
    $keyword =~ s/ī/ī/g;
    $keyword =~ s/õ/õ/g;
    $keyword =~ s/š/š/g;
    $keyword =~ s/ū/ū/g;
    $keyword =~ s/\&/\%26/g;

    return $keyword;
}

sub finto_decomposition($) {
    my $keyword = shift();
    # lexicons use compound versions of various chars
    $keyword =~ s/á/á/g;
    $keyword =~ s/ā/ā/g;
    $keyword =~ s/é/é/g;
    $keyword =~ s/ė/ė/g;
    $keyword =~ s/ī/ī/g;
    $keyword =~ s/õ/õ/g;
    $keyword =~ s/š/š/g;
    $keyword =~ s/ū/ū/g;

    return $keyword;
}


sub _get_single_entry2($$) {
    my ( $keywordP, $entry ) = @_;

    if ( $$keywordP =~ s/$entry +(\"[^\"]+\"\@[a-z]+|[a-z]\S+),\s+/$entry /s ) {
        return $1;
    }

    if ( $$keywordP =~ s/$entry +(<http:\S+>|[a-z]\S+), +/$entry / ) {
        return $1;
    }
    
    if ( $$keywordP =~ s/ *$entry +("[^\"]+"\@[a-z]+|[a-z]\S+) ;// ) {
        return $1;
    }
    if ( $$keywordP =~ s/;\s+$entry +(\"[^\"]+\"\@[a-z]+) *\././s ) {
        #die($1.",\n",$$keywordP);
        return $1;
    }

    
    if ( $$keywordP =~ /$entry/ ) {
        print STDERR "OOPS ($entry):\n", $$keywordP, "\n\n";
    }
    return '';
}

sub _get_single_entry($$) {
    my ( $keywordP, $entry ) = @_;
    my $val = _get_single_entry2($keywordP, $entry);
    $val = finto_decomposition($val);
    return $val;
}

sub _strip_path($) {
    my $basename = $_[0];
    $basename =~ s/^.*\///;
    if ( $basename =~ /=/ ) { die($basename); }
    return $basename;
}

sub _download_url_if_needed($$) {
    my ( $url, $filename ) = @_;

    # my $basename = &_strip_path($url);

    if ( -e $filename ) {
	my $n_days = 1;
        if ( -s $filename && -M $filename < $n_days ) {
            print STDERR "Our version of '$filename' is less than $n_days day(s) old. Not updating it!\n";
            return;
        }
        # musa ei enää päivity, joten sitä on turha ladatakaan
        if ( $filename =~ /^(cilla|musa|ysa)/ ) {
            return;
        }
    }

    print STDERR " About to download $url...\n";
    my $content = LWP::Simple::get($url);

    print STDERR " Done...\n";
    if ( !defined($content) ) {
        print STDERR "OOPS NO DATA WHILE GETTING $url!\n";
    }
    else {
        $content = "".$content;

        print STDERR " Write content to $filename\n";
        my $FH;
        open($FH, ">:encoding(UTF-8)", $filename) or die($!);
        print $FH $content;
        close($FH);
    }
}

sub _read_file($) {
    my $filename = $_[0];
    my $FH;
    my $tmp = $/;
    undef $/;
    print STDERR "READING FILE '$filename'\n";
    open ($FH, "$filename") or die($!);
    my $data = <$FH>;
    close($FH);
    $/ = $tmp;
    return $data;
}


sub load_lexicon_entries($$) {
    my ( $url, $lexicon_name ) = @_;

    my $filename = defined($lexicon_name) ? &lexicon_name2filename($lexicon_name) : &_strip_path($url);
    
    &_download_url_if_needed($url, $filename); # saves it as file

    my $text = &_read_file($filename);
    my @entries = split(/\n\n/, $text);
    print STDERR "$url: $#entries entries loaded\n";
    return @entries;
}

sub pref_hack($) {
    # Olis varmaan tehokkaamp
    my ($pref2idP) = @_;
    my %pref2id = %{$pref2idP};
    my %suspicious;
    foreach my $key ( sort keys %pref2id ) {
        my $id = $pref2id{$key};
        if ( $key =~ s/ \(.*\)$// ) {
            if ( !defined($suspicious{$key}) ) {
                $suspicious{$key} = $id;
            }
            elsif ( $suspicious{$key} !~ /(^|\t)$id($|\t)/ ) {
                $suspicious{$key} .= "\t".$id;
            }
        }
    }
    return %suspicious;
}


sub lexicon2char($) {
    my ( $lexicon_name ) = @_;
    # char can be found in turtle file:
    # mts:m0 a skos:Concept
    #     ^
    $lexicon_name = use_finnish_lexicon_name($lexicon_name); # bella => kaunokki
     
    if ( $lexicon_name eq 'kauno' ) { return 'p'; } # No char!
    if ( $lexicon_name eq 'kaunokki' ) { return ''; } # No char!
    if ( $lexicon_name eq 'mts' ) { return 'm'; }
    if ( $lexicon_name eq 'slm' ) { return 's'; }
    if ( $lexicon_name eq 'soto' ) { return 'p'; }
    if ( $lexicon_name eq 'yso' ) { return 'p'; }
    if ( $lexicon_name eq 'yso-aika' ) { return 'p'; }
    if ( $lexicon_name eq 'yso-paikat' ) { return 'p'; }
    die($lexicon_name);
}


sub concept2skos_id($$) {
    my ($lexicon_name, $concept) = @_;

    if ( $lexicon_name eq 'allars' || $lexicon_name eq 'ysa' ) {
	die(); # $pref_label =~ /^ysa:(Y\d+)$/ ) { # allars
        # if ( $concept =~ /^:(Y\d+) a skos/ ) { # ysa
    }
    
    if ( $lexicon_name eq 'kauno' ) {
	# Don't read yso terms!
	if ( $concept =~ /^kauno:(p\d+) a skos:Concept,\s*kauno-?meta:Concept ;/s ) {
	    return 1;
	}
	return 0;
    }
    if ( $lexicon_name eq 'kaunokki' ) {
	if ( $concept =~ /^kaunokki:(\d+) a owl:Class,\s+skos:Concept,\s+kaunokkimeta:Concept ;/s ) {
	    return $1;
	}
	return 0;
    }

    if ( $lexicon_name eq 'seko' ) {
        # if ( $concept =~ /^<(http:\S+:seko:\d+)> a skos/ ) {    
	die();
    }
    
    if ( $lexicon_name eq 'soto' ) {
	#if ( $concept =~ /^(?:soto|yso):(p\d+) a skos:Concept(,\s*(yso-|soto)meta:(Concept|Individual))? ;/s ) {
	# NB! We are only interested in soto proper terms

	if ( index($concept, ":Concept") == -1 ) { return 0; }
	#die($concept); # Breakpoint. Reason: Untested after refactoring. 
	if ( $concept =~ /^soto:(p\d+) a skos:Concept(,\s*(yso-|soto)meta:(Concept))? ;/s ) {
	    #die(); # Breakpoint. Reason: Untested after refactoring. 

	    return $1;
	}
	
	return 0;
    }
    
    if ( $lexicon_name eq 'yso' ) {
	if ( $concept =~ /^yso:(p\d+) a skos:Concept,\s*yso-meta:(Concept|Hierarchy|Individual) ;/s ) {
	    return $1;
	}
	return 0;
    }
    if ( $lexicon_name eq 'yso-aika' ) {
	if ( $concept =~ /^yso:(p\d+) a skos:Concept,\s*yso-meta:(Century|Decade|Millenium) ;/s ) {
	    return $1;
	}
	return 0;
    }


    
    ## Generic version:    
    my $c = &lexicon2char($lexicon_name);

    # with some name normalization hacks:
    my $normalized_lexicon_name = &normalize_yso_lexicon_name($lexicon_name);

    if ( $concept =~ /^$normalized_lexicon_name:($c\d+) a skos:Concept/ ) {
	my $id = $1;
	#if ( $normalized_lexicon_name eq 'yso' ) { die("$id\n$concept"); }
	return $id;
    }

    # print STDERR "FAILED CONCEPT:\n$concept\n\n";

    return 0;
}

sub read_lexicon2($) {
    my ( $lexicon_name ) = @_;
    if ( defined($loaded_lexicons{$lexicon_name}) ) { return; }
    $loaded_lexicons{$lexicon_name} = 1;

    my $url = lexicon_name2download_url($lexicon_name);

    my @lex = &load_lexicon_entries($url, $lexicon_name);

    my %ignored_languages;
    print STDERR "GEN-Tutkitaan ", ($#lex+1), " $lexicon_name-entryä...\n";

    #my $c = &lexicon2char($lexicon_name);
    for ( my $i=0; $i <= $#lex; $i++ ) {
        my $concept = $lex[$i];
        $concept = unicode_fixes2($concept, $finto_debug);


	
	my $skos_id;
        if ( $skos_id = concept2skos_id($lexicon_name, $concept) ) {
	    # print STDERR "$lexicon_name ID $skos_id\n";

	    if ( $lexicon_name eq 'soto' ) {
                my $tmp = $concept;
                while ( my $yso_pair = _get_single_entry(\$tmp, "skos:exactMatch") ) {
		    if ( $yso_pair =~ s/^yso:(p\d+)$/$1/ ) {
			$lexica{$lexicon_name}{'yso'}{$skos_id} = $yso_pair;
		    }
		}
	    }
	    
	    foreach my $label_type ( keys %{$lexica{$lexicon_name}} ) {
                my $tmp = $concept;
                while ( my $label = _get_single_entry(\$tmp, "skos:${label_type}Label") ) {
		    my $local_debug = 0;
		    if ( $skos_id eq 'p105087' && $lexicon_name eq 'yso-paikat' ) { $local_debug = 1; }

		    
                    if ( $label =~ /^\"(.*)\"\@([a-z]{2})$/ ) {
			my $term = $1;
			my $lang2 = $2;
			my $lang3 = lang2_to_lang3($lang2);
			# Skip unsupported languages:
			if ( !defined($lang3) || !defined($lexica{$lexicon_name}{$label_type}{$lang3}) ) {
			    next;
			}

			# TERM => ID
			if ( defined($lexica{$lexicon_name}{$label_type}{$lang3}{'term2id'}{$term}) ) {
			    
			    $lexica{$lexicon_name}{$label_type}{$lang3}{'term2id'}{$term} .= "\t".$skos_id;
			    if ( $label_type eq 'pref' ) {
				# TODO: Add complaints/debug messages
				if ( 0 && $finto_debug ) {
				    print STDERR "Multiple definitions for $lexicon_name/$label_type/$lang3/term2id/$term:\t", $lexica{$lexicon_name}{$label_type}{$lang3}{'term2id'}{$term}, "\n";
				}
				if ( $lexicon_name eq 'mts' || $lexicon_name eq 'soto' ) {

				}
				else {
				    die("$term/$lang3");
				}
			    }
			}
			else {
			    $lexica{$lexicon_name}{$label_type}{$lang3}{'term2id'}{$term} = $skos_id;
			}

			# ID => TERM
			if ( defined($lexica{$lexicon_name}{$label_type}{$lang3}{'id2term'}{$skos_id}) ) {
			    
			    $lexica{$lexicon_name}{$label_type}{$lang3}{'id2term'}{$skos_id} .= "\t".$term;
			    if ( $label_type eq 'pref' ) {
				# TODO: Add complaints/debug messages
				print STDERR "Multiple definitions for $lexicon_name/$label_type/$lang3/id2term/$skos_id:\t", $lexica{$lexicon_name}{$label_type}{$lang3}{'id2term'}{$skos_id}, "\n";
				die();
			    }
			}
			else {
			    $lexica{$lexicon_name}{$label_type}{$lang3}{'id2term'}{$skos_id} = $term;
			}

			if ( $local_debug ) {
			    print STDERR "Added $lexicon_name/$label_type/$lang3/term2id/$term:\t", $lexica{$lexicon_name}{$label_type}{$lang3}{'term2id'}{$term}, "\n";
			    print STDERR "Added $lexicon_name/$label_type/$lang3/id2term/$skos_id:\t", $lexica{$lexicon_name}{$label_type}{$lang3}{'id2term'}{$skos_id}, "\n";
			}
		    }
		}
            }
        }
    }
    print STDERR "Finished reading $lexicon_name terms\n";
#    my %whatever = $lexica{$lexicon_name}{'pref'}{'fin'}{'id2term'};
#    my @keys = keys %whatever;
#    print STDERR ( $#keys+1 ), " pref fin ids.\n";
	
}

sub read_lexicon($) {
    my ( $lexicon_name ) = @_;
    if ( $lexicon_name eq 'yso-kaikki' ) {
	read_lexicon2('yso');
	read_lexicon2('yso-aika');
	read_lexicon2('yso-paikat');
	return;
    }
    read_lexicon2($lexicon_name);    
}


sub new_id2pref_label($$$) {
    my ( $id, $lex, $lang ) = @_;
    &read_lexicon($lex);
    if ( defined($lexica{$lex}{'pref'}{$lang}{'id2term'}{$id}) ) {
	#print STDERR "NEW TEST $lex/pref/$lang/id2term/$id: ", $lexica{$lex}{'pref'}{$lang}{'id2term'}{$id}, "\n";
    }
    else {
	print STDERR "NEW TEST $lex/pref/$lang/id2term/$id: undef!\n";
    }
    return $lexica{$lex}{'pref'}{$lang}{'id2term'}{$id};
}

sub new_id2unambiguous_pref_label($$$) {
    my ( $id, $lex, $lang ) = @_;
    my $result = new_id2pref_label($id, $lex, $lang);
    if ( !defined($result) ) {
	return undef;
    }
    if ( $result =~ /\t/ ) {
	print STDERR " Pref label for $lex-$id $lang is not unambiguous!\n";
	return undef;
    }
    #print STDERR "RES '$result'\n";
    return $result;
}


sub term_is_in_slm_or_seko($) {
    my $term = shift();
    if ( defined(new_pref_label2ids($term, 'slm', 'fin')) ||
	 defined(new_pref_label2ids($term, 'seko', 'fin')) ) {
        return 1;
    }
    if ( $term =~ s/ \(.*\)$// ) {
        if ( defined(new_pref_label2ids($term, 'slm', 'fin')) ||
             defined(new_pref_label2ids($term, 'seko', 'fin')) ) {
            return 1;
        }
    }
    return 0;
}

sub has_slm_or_seko($) {
    my $field = shift();
    while ( $field =~ s/\x1F[ax]([^\x1F]+)// ) {
        my $term = $1;
        if ( term_is_in_slm_or_seko($term) ) {
            return 1;
        }
    }
    return 0;
}

sub add_sf2($$) {
    my ( $content, $lex ) = @_;
    if ( $content =~ /\x1F2$lex($|\x1F)/ ) {
        return $content;
    }
    if ( $content =~ /\x1F2/ ) {
        die();
    }
    if ( $content =~ s/(\x1F[059])/\x1F2$lex$1/ ) {
        return $content;
    }
    return $content . "\x1F2$lex";
}


sub valid_location($$) {
    my ( $loc, $lex ) = @_;
    die();
    if ( !defined($loc) ||
         # Tälle on varmaan poikkeuksia, mutta ihmetellään ne sitten joskus...
         $loc !~ /^([A-Z]|Å|Ä|Ö)/ ) {
        return 0;
    }
    
    if ( $lex eq 'fast' ) { return 0; }
    my $id = pref_label2id($loc, $lex);
    if ( $id ) {
	if ( $lex eq 'yso-paikat/fin' || $lex eq 'yso-paikat/swe' ) {
	    return 1;
	}
    }
    return 0;
}

sub valid_year($$) {
    my ( $year, $lex ) = @_;
    if ( $year =~ /^(1[0-9][0-9][0-9]|20[0-2][0-9])$/ ) {
        return 1;
    }
    if ( $year =~ /^(1[0-9][0-9][0-9]|20[0-2][0-9])\-(1[0-9][0-9][0-9]|20[0-2][0-9])$/ &&
         $1 < $2 ) {
        return 1;
    }

    if ( defined($lex) ) {
        if ( $lex =~ /^(kaunokki|musa|ysa)$/ ) {
            if ( $year =~ /^(1[0-9][0-9]|20[012])0-luku$/ ||
                 $year =~ /^[1-9]00-luku$/ ) {
                return 1;
            }
            if ( $year =~ /^(1[0-9][0-9]0|20[012]0)-(1[0-9][0-9]0|20[012]0)-luku$/ &&
                 $1 < $2 ) {
                return 1;
            }
        }
        if ( $lex =~ /^(allars)$/ ) {
            if ( $year =~ /^(1[0-9][0-9]|20[012])0-talet$/ ||
                 $year =~ /^[1-9]00-talet$/ ) {
                return 1;
            }
            if ( $year =~ /^(1[0-9][0-9]0|20[012]0)-(1[0-9][0-9]0|20[012]0)-talet$/ &&
                 $1 < $2 ) {
                return 1;
            }
        }
    }
    if ( $year =~ /\d/ ) {
        print STDERR "valid_year($year, ", ( defined($lex) ? $lex : 'N/A' ), ") fails on '$year'\n";
    }
    return 0;
}



sub subfields_are_valid($$$$) {
    # Check legality of subfields, but don't check existence requirements...
    my ( $content, $tag, $lexlang, $alt_policy ) = @_;
    die();
    if ( $tag !~ /^(650|651|655)$/ ) {
	return 0;
    }
    my ( $lex, $lang ) = lexlang2lex_and_lang($lexlang);
    if ( !defined($lex) ) {
	# Indicator-based recognition?
	die();
    }
    my $short_lex = normalize_yso_lexicon_name($lex);

    if ( $content =~ /\x1F2/ && $content !~ /\x1F2\Q${short_lex}\E($|\x1F)/ ) {
	return 0;
    }
    
    my @subfields = split(/\x1F/, $content);

    #print STDERR "subfields_are_valid('$content', $tag, $lex)? WP1\n";
    # $subfields[0] contains indicators, so we are not interested in them here.
    for ( my $i = 1; $i <= $#subfields; $i++ ) {
        my $data = $subfields[$i];
        
        
        my $sf_code;
        if ( $data =~ s/^([a-z0-9])// ) {
            $sf_code = $1;
        }
        else {
            print STDERR "Invalid subfield code in '$content'\n";
            return 0;
        }

        # Jos ei ole asiasana, ja löytyy yksiselitteinen ohjaustermi,
        # niin vaihda asiasana muuttujaan $data:
        if ( $alt_policy == USE_ALT && !pref_label2id($data, $lex) ) {
            my $alt_id = alt_label2id($data, $lex);
            if ( defined($alt_id) && $alt_id !~ /\t/ ) {
                my $tmp = id2unambiguous_pref_label($alt_id, $lex);
                if ( defined($tmp) ) {
                    $data = $tmp;
                }
            }
        }

	# unless ( $sf_code =~ /^[05689]$/ ) { print STDERR " subfields_are_valid($tag, ", ( defined($lex) ? $lex : 'N/A' ) , "): \$$sf_code $data?\n"; }

        if ( $sf_code eq 'a' ) {
            if ( valid_year($data, $lex) ) {
                if ( $tag ne '648' ) {
                    return 0;
                }
            }
            elsif ( valid_location($data, $lex) ) {
                if ( $tag ne '651' ) {
                    return 0;
                }
            }
            # altLabel on muutettu prefLabeliksi aiemmin, jos on...
            elsif ( !pref_label2id($data, $lex) ) {
                return 0;
            }
            else { # osui tavis-asiasanaan...
                if ( $tag ne '650' && $tag ne '655' ) {
                    return 0;
                }
            }
        }
        elsif ( $sf_code eq 'x' && $lex !~ /^(slm|yso)/ ) {
            if ( !pref_label2id($data, $lex) ) {
                if ( $alt_policy == SKIP_ALT ) {
                    return 0;
                }
                # implicitly specified USE_ALT
                if ( !alt_label2id($data, $lex) ) {
                    return 0;
                }
            }
        }
        elsif ( $sf_code eq 'y' && $lex !~ /^(slm|yso)/ ) {
            if ( !valid_year($data, $lex) ) { return 0; }
        }
        elsif ( $sf_code eq 'z' && $lex !~ /^(slm|yso)/ ) {
            if ( !valid_location($data, $lex) ) { return 0; }
        }
        elsif ( $sf_code eq '2' ) {
            if ( !defined($lex) || $short_lex ne $data ) { return 0; }
        }
        elsif ( $sf_code =~ /^[05689]$/ ) {
            # do nothing; these are ok
        }
        else {
            #print STDERR "subfields_are_valid(): failure, sf code: '$sf_code'\n";
            return 0;
        }
        
    }
    #print STDERR "subfields_are_valid('$content', $tag, $lex): OK\n";
    return 1;
}

sub generic_alt2pref_field($$$) {
    my ( $field, $sf_code, $lex ) = @_;
    die();
    if ( $field =~ /\x1F2.*\x1F2/ ) {
	return $field 
    }

    if ( $sf_code eq 'a' && $field =~ /^..\x1Fa([^\x1F]+)\x1F2\Q$lex\E\x1F0([^\x1F]+)(\x1F[59][^\x1F]+)*$/ ) {
	my $term = $1;
	my $sf0 = $2;
	
	my $term_id = pref_label2id($term, $lex);
	if ( !defined($term_id) ) {
	    if ( $lex eq 'yso/fin' ) {
		$term_id = pref_label2id($term, 'yso-paikat/fin') || pref_label2id($term, 'yso-aika/fin');
	    }
	    elsif ( $lex eq 'yso/swe' ) {
		$term_id = pref_label2id($term, 'yso-paikat/swe') || pref_label2id($term, 'yso-aika/swe');
	    }
	}

	
	if ( defined($term_id) ) {
	    # Kaikki hyvin (teoriassa termi ja $0 voi olla eri paria,
	    # mutta se ei ole tämän funktion ongelma
	    return $field;
	}

	$term_id = alt_label2id($term, $lex);
	if ( !defined($term_id) ) {
	    if ( $lex eq 'yso/fin' ) {
		$term_id = alt_label2id($term, 'yso-paikat/fin') || alt_label2id($term, 'yso-aika/fin');
	    }
	    elsif ( $lex eq 'yso/swe' ) {
		$term_id = alt_label2id($term, 'yso-paikat/swe') || alt_label2id($term, 'yso-aika/swe');
	    }
	}
	
	if ( !defined($term_id) ) {
	    print STDERR "WARNING: '$term'/$lex does not map to subfield \$0 '$sf0' or is deprecated!\n";
	    #die();
	}
	elsif ( $term_id =~ /\t/ ) {
	    print STDERR "WARNING: '$term'/$lex is ambiguous!\n";
	}
	else {
	    my $pref_label = id2unambiguous_pref_label($term_id, $lex);
	    if ( !defined($pref_label) ) { die(); }
	    
	    if ( $sf0 =~ /\Q$term_id\E$/ ) {
		$field =~ s/\x1Fa[^\x1F]+/\x1Fa$pref_label/;
	    }
	    else {
		print STDERR "WARNING\tCan't fix '$field'\n";
	    }
	}
    }
    elsif ( $field =~ /\x1F2\Q${lex}\E($|\x1F)/ ) {
	my ( @cands ) = $field =~ /\x1F${sf_code}([^\x1F]+)/g;
	for ( my $j=0; $j <= $#cands; $j++ ) {
	    my $term =$cands[$j];
	    
	    #                    ## NB! Nyt vain " -- " ja sulkukama päällä...
	    #                    if ( $term =~ /^([A-Z]|Å|Ä|Ö)/ ) { next; }
	    #                    if ( $term =~ / -- / ||
	    #                         $term =~ /\(/ ) {
	    #                    }
	    #                    else {
	    #                        next;
	    #                    }

	    if ( !defined($term) || length($term) == 0 ) {
		if ( $sf_code eq 'a' ) {
		    print STDERR "Crappy XXX\$$sf_code field '$field'\n";
		}
	    }
	    # Ei löydy prefLabelina:
	    elsif ( !defined(pref_label2id($term, $lex)) ) {
		print STDERR " $lex-Huti. Löytyykö altLabel '$term'?\n";
		my $term_id = alt_label2unambiguous_id($term, $lex);
		if ( defined($term_id) ) {
		    my $pref_label = id2unambiguous_pref_label($term_id, $lex);
		    if ( defined($pref_label) ) {
			# Skippaa "Nya testamentet" => Bibeln...
			if ( $term =~ /^(kyrkor|minnen|teater|teatrar|teatteri|teatterit|vinster|äänet)$/ || $term =~ /testamentet/ ) {
			    print STDERR "SKIP OHJAUSTERMI ", ($j+1), "/", ($#cands+1), " '$term' -> '$pref_label' ($term_id)\n";
			}
			else {
			    print STDERR "FIX OHJAUSTERMI ", ($j+1), "/", ($#cands+1), " '$term' -> '$pref_label' ($term_id)\n";
			    $field =~ s/\x1F${sf_code}\Q$term\E($|\x1F)/\x1F${sf_code}$pref_label$1/;
			}
		    }
		    else {
			die();
		    }
		}
		else {
		    print STDERR "  XXX\$$sf_code\t'$term' ei ole sanaston $lex *yksiselitteinen* termi! '$field'\n";
		}
	    }
	}
    }
            
    return $field;
}

sub generic_alt2pref($$$) {
    my ( $id, $record, $lex ) = @_;

    # TODO: Should we support locations: USA -> Yhdysvallat ?
    # Hacky array: odd values are tags and even values are subfield codes.
    my @tags = ( '650', 'a',
                 '650', 'x',
                 #'650', 'y',
                 '651', 'a',
                 '651', 'x',
                 #'651', 'y',
                 '655', 'a',
        );

    if ( index($record, "\x1F2$lex") == -1 ) { return $record; }
    
    for ( my $nth_tag = 0; $nth_tag <= $#tags; $nth_tag+=2 ) {
        my $tag = $tags[$nth_tag];
        my $sf_code = $tags[$nth_tag+1];
        # Nämä haetaan tarkoituksella uudelleen (bleeding, feeding)...
        my @fields = marc21_record_get_fields($record, $tag, undef);

        for ( my $i=0; $i <= $#fields; $i++ ) {
            my $field = $fields[$i];
	    $field = generic_alt2pref_field($field, $sf_code, $lex);

            if ( $field ne $fields[$i] ) {
                print STDERR "$id\tFIX OHJAUSTERMI\n";
                print STDERR " $tag '", $fields[$i], "' =>\n";
                print STDERR " $tag '$field'\n";
		die(); # test after mods
                $record = marc21_record_replace_nth_field($record, $tag, $field, $i);
            }
        }
    }
    return $record;
}


sub lexlang2lex_and_lang($) {
    my ( $lexicon ) = @_;
    if ( $lexicon =~ /^(\S+)\/(eng|fin|swe)$/ ) {
	return ( $1, $2 );
    }

    # Finnish lexicons:
    if ( $lexicon eq 'eks' ||
	 $lexicon eq 'kaunokki' ||
	 $lexicon eq 'kta' ||
	 $lexicon eq 'mts' || # is multilingual, but default to fin
	 $lexicon eq 'musa' ||
	 $lexicon eq 'soto' ||
	 $lexicon eq 'ysa' ) {
	return ( $lexicon, 'fin' );
    }
    
    # Swedish lexicons:
    if ( $lexicon eq 'allars' || $lexicon eq 'bella' || $lexicon eq 'cilla' ) {
	return ( $lexicon, 'swe' );
    }

    if ( $lexicon ne 'local' ) {
	print STDERR "WARNING\tlexlang2lex_and_lang($lexicon) failed!\n";
    }
    return ( undef, undef );    
}

sub lexicon2lang($) {
    my $lexicon = shift;
    if ( $lexicon =~ /\/(eng|fin|swe)$/ ) {
	return $1;
    }
    if ( $lexicon eq 'allars' || $lexicon eq 'bella' || $lexicon eq 'cilla' ) {
	return 'swe';
    }
    # NB! 'soto' has english, but swedish
    if ( # $lexicon eq 'kaunokki' || 
	 $lexicon eq 'musa' || $lexicon eq 'soto' || $lexicon eq 'ysa' ) {
	return 'fin';
    }
    die($lexicon);
    return undef;
}

sub new_label2ids($$$$) {
    my ( $term, $lexicon, $lang, $label ) = @_;

    #print STDERR "new_label2ids($term, $lexicon, $lang, $label)\n";
    if ( !defined($lexicon) ) {
        return undef;
    }
    $lexicon = use_finnish_lexicon_name($lexicon);
    
    &read_lexicon($lexicon);

    if ( !defined($lexica{$lexicon}) ) {
        print STDERR "\tnew_label2ids(): lex('$term', '$lexicon') is not supported yet!\n";
	die($lexicon);
	return undef;
    }

    if ( defined($lexica{$lexicon}{$label}) &&
	 defined($lexica{$lexicon}{$label}{$lang}) ) {
	return $lexica{$lexicon}{$label}{$lang}{'term2id'}{$term};
    }
    return undef;
}

sub new_pref_label2ids($$$) {# rename as pref_lavel pref_label2ids() ?!?
    my ( $term, $lexicon, $lang ) = @_;
    return new_label2ids($term, $lexicon, $lang, 'pref');
}


sub new_alt_label2ids($$$) {# rename as pref_lavel pref_label2ids() ?!?
    my ( $term, $lexicon, $lang ) = @_;
    return new_label2ids($term, $lexicon, $lang, 'alt');
}

sub new_alt_label2unambiguous_id($$$) {# rename as pref_lavel pref_label2ids() ?!?
    my ( $term, $lexicon, $lang ) = @_;
    my $ids = new_label2ids($term, $lexicon, $lang, 'pref');
    if ( defined($ids) && $ids !~ /\s/ ) {
	return $ids;
    }
    return undef;
}

sub new_any_label2ids($$$) {
    my ( $term, $lexicon, $lang ) = @_;
    my $pref = new_label2ids($term, $lexicon, $lang, 'pref');
    my $alt = new_label2ids($term, $lexicon, $lang, 'alt');

    if ( !defined($pref) ) { return $alt; }
    if ( !defined($alt) ) { return $pref; }
    my @idarr = split(/\s+/, $pref.' '.$alt);
    my @unique = do { my %seen; grep { !$seen{$_}++ } @idarr };
    return join("\t", @unique);
}

sub new_any_label2unambiguous_id($$$) {
    my ( $term, $lexicon, $lang ) = @_;
    my $ids = new_any_label2ids($term, $lexicon, $lang);
    if ( !defined($ids) || index($ids, "\t") > -1 ) {
	return undef;
    }
    return $ids;
}

sub label2ids($$) {
    my ( $term, $lexicon ) = @_;
    die();
    my $ids1 = pref_label2id($term, $lexicon);
    my $ids2 = alt_label2id($term, $lexicon);
    if ( !$ids2 ) { return $ids1; }
    if ( !$ids1 ) { return $ids2; }
    my @idarr = split(/\s+/, $ids1.' '.$ids2);
    my @unique = do { my %seen; grep { !$seen{$_}++ } @idarr };
    return join(' ', @unique);
}


sub new_pref_label2unambiguous_id($$$) {
    my ( $term, $lexicon, $lang ) = @_;
    #print STDERR "new_pref_label2unambiguous_id($term, $lexicon, $lang)\n";
    my $id = new_pref_label2ids($term, $lexicon, $lang);
    if ( defined($id) && $id =~ /\t/ ) {
        print STDERR "$lexicon/$lang: prefLabel '$term' is ambiguous: $id\n";
        return undef;
    }
    return $id;
}

sub new_label2unambiguous_id($$$) {
    my ( $term, $lexicon, $lang ) = @_;
    print STDERR "new_pref_label2unambiguous_id($term, $lexicon, $lang)\n";
    my $id = new_pref_label2ids($term, $lexicon, $lang);
    if ( defined($id) ) {
	if ( $id =~ /\t/ ) {
	    print STDERR "$lexicon/$lang: prefLabel '$term' is ambiguous: $id\n";
	    return undef;
	}
	return $id;
    }
    die();
    return $id;
}


sub uppercase_first($) {
    my $word = shift;
    # meidän perlin versio ei välttämättä klaaraa utf-8-merkkejä:
    $word = "\u$word";
    $word =~ s/^å/Å/;
    $word =~ s/^ä/Ä/;
    $word =~ s/^ö/Ö/;
    return $word;
}

sub uppercase_initials($) {
    my $word = shift;
    # meidän perlin versio ei välttämättä klaaraa utf-8-merkkejä:
    $word =~ s/(^| )(.)/$1\u$2/g;
    $word =~ s/(^| )å/${1}Å/g;
    $word =~ s/(^| )ä/${1}Ä/g;
    $word =~ s/(^| )ö/${1}Ö/g;
    return $word;
}


my %tekijat100;
my %tekijat110;
my %tekijat400;
my %tekijat410;

sub process_seq_author($) {
    my $record = shift();
    my $nimi = undef;
    if ( $record =~ /^\d+ (1[01]0)(..) L \$\$a([^\$]+)\$\$0(\(FIN11\)\d+)$/m ) {
        my $tag = $1;
        $nimi = $3;
        my $field = $2."\x1Fa".$3."\x1F0".$4;
        if ( $tag eq '100' ) {
            #print STDERR "AUKTORIT\t100\t$nimi\t$field\n";
            if ( !defined($tekijat100{$nimi}) ) {
                $tekijat100{$nimi} = $field;
            }
            else {
                $tekijat100{$nimi} .= "\t".$field;
            }
        }
        elsif ( $tag eq '110' ) {
            #print STDERR "AUKTORIT\t110\t$nimi\t$field\n";
            if ( !defined($tekijat110{$nimi}) ) {
                $tekijat110{$nimi} = $field;
            }
            else {
                $tekijat110{$nimi} .= "\t".$field;
            }
        }
    }
    if ( defined($nimi) ) {
        my @f400 = $record =~ /^\d+ 400.. L \$\$a([^\$]+)$/mg;
        for ( my $i=0; $i <= $#f400; $i++ ) {
            my $alt_name = $f400[$i];
            if ( !defined($tekijat400{$alt_name}) ) {
                $tekijat400{$alt_name} = $nimi;
            }
            else {
                $tekijat400{$alt_name} .= "\t" . $nimi;
            }
        }
        my @f410 = $record =~ /^\d+ 410.. L \$\$a([^\$]+)$/mg;
        for ( my $i=0; $i <= $#f410; $i++ ) {
            my $alt_name = $f410[$i];
            # print STDERR "ADDING ALT 410 NAME $alt_name FOR $nimin";
            if ( !defined($tekijat410{$alt_name}) ) {
                $tekijat410{$alt_name} = $nimi;
            }
            else {
                $tekijat410{$alt_name} .= "\t" . $nimi;
            }
        }
    }
}

sub lue_tekijat() {
    if ( keys %tekijat100 > 0 ) { return; }
    my $file = "/ram/index/asteri/fin11.seq";
    print STDERR "Lue auktorit tiedostosta $file...\n";
    my $FH = undef;
    open($FH, "<$file") or die($!);
    my $record = '';
    my $old_id = 0;
    while ( $_ = <$FH> ) {
        /^(\d+) (.*)$/;
        my $curr_id = $1;
        if ( $curr_id eq $old_id ) {
            $record .= $_;
        }
        else {
            if ( $old_id ne '' ) {
                process_seq_author($record);
            }
            $record = $_;
            $old_id = $curr_id;
        }
    }
    if ( $record ) {
        process_seq_author($record);
    }
    close($FH);

}


sub alt_auth_names($$) {
    my ( $nimi, $kentta ) = @_;
    lue_tekijat();
    my %alt;
    if ( $kentta eq '100' ) {
        foreach my $key ( keys %tekijat400 ) {
            if ( $tekijat400{$key} eq $nimi ||
                 $tekijat400{$key} =~ /(^|\t)\Q$nimi\E($|\t)/ ) {
                $alt{$key} = $nimi;
            }
        }
    }
    if ( $kentta eq '110' ) {
        foreach my $key ( keys %tekijat410 ) {
            if ( $tekijat410{$key} eq $nimi ||
                 $tekijat410{$key} =~ /(^|\t)\Q$nimi\E($|\t)/ ) {
                $alt{$key} = $nimi;

            }
        }
    }
    return %alt;
}

sub hae_tekija($$) {
    my ( $nimi, $kentta ) = @_;
    lue_tekijat();
    if ( $kentta eq '100' ) {
        if ( !defined($tekijat100{$nimi}) ) {
            if ( defined($tekijat400{$nimi}) &&
                 $tekijat400{$nimi} !~ /\t/ ) {
                print STDERR "AUTH rename $nimi => ", $tekijat400{$nimi}, "\n";
                $nimi = $tekijat400{$nimi};

            }
        }
        if ( defined($tekijat100{$nimi}) ) {
            if ( $tekijat100{$nimi} =~ /\t/ ) {
                print STDERR "Warning: $nimi on moniselitteinen...\n";
            }
            return $tekijat100{$nimi};
        }
        return undef;
    }
    if ( $kentta eq '110' ) {
        if ( defined($tekijat110{$nimi}) ) {
            if ( $tekijat110{$nimi} =~ /\t/ ) {
                print STDERR "Warning: $nimi on moniselitteinen...\n";
            }
            return $tekijat110{$nimi};
        }
        return undef;
    }

    return undef;
}

sub generic_no_debugger($$$$$$) {
    my ( $id, $record, $content, $lexicon, $term, $must_NOT_have_func_ref ) = @_;
    if ( $content =~ /\x1F[ax]\Q$term\E\x1F/ && $content =~ /\x1F[ax]$lexicon/ ) {
        my $must_NOT_have = &{$must_NOT_have_func_ref}($id, $record);
        if ( defined($must_NOT_have) ) {
            print STDERR "$id\t$term: TODO NB FIX '$must_NOT_have' implies a bug!\n";
        }
    }
    return $content;
}
sub generic_yes_no_fixer($$$$$$$$) {
    my ( $id, $record, $content, $lexicon, $from, $to, $must_have_func_ref, $must_NOT_have_func_ref ) = @_;
    #if ( $content =~ /\x1F[ax]\Q$from\E\x1F/ && $content =~ /\x1F2$lexicon/ ) {
    if ( $content =~ /\x1Fa\Q$from\E\x1F2$lexicon/ ) {
        
        my $must_have = ( defined($must_have_func_ref ) ? &{$must_have_func_ref}($id, $record) : "NONE REQUIRED" );
        my $must_NOT_have = ( defined($must_NOT_have_func_ref) ? &{$must_NOT_have_func_ref}($id, $record) : undef );
        if ( defined($must_have) ) {
            if ( defined($must_NOT_have) ) {
                print STDERR "$id\t$from: '$must_have' triggers '$to', but '$must_NOT_have' blocks it.\n";
                return $content;
            }
            print STDERR "$id\t$from: '$must_have' triggers '$to'\n";

            $content =~ s/(\x1F[ax])\Q$from\E\x1F/$1$to\x1F/;

            return $content;
        }
        elsif ( defined($must_NOT_have) ) {
            print STDERR "$id\t$from: '$must_NOT_have' would have triggered DON'T convert to '$to'\n";
        }
        elsif ( !defined($must_NOT_have_func_ref) ) {
            print STDERR "$id\t$from: NB no match, no blocker rule\n";
        }
        else {
            print STDERR "$id\t$from: NB neither positive nor negative rule matches (target: '$to')\n";
        }
    }
    return $content;
}


sub field_content_has_term($$$) {
    my ( $content, $term_regexp, $lexicon ) = @_;

    # Check lexicon:
    if ( defined($lexicon) ) {
	# Some long forgotten indicator sanity check:
	if ( $lexicon eq 'LCSH' ) {
	    if ( $content !~ /^.0/ ) {
		return undef;
	    }
	}
	if ( $content !~ /\x1F2\Q$lexicon\E/ ) {
	    return undef;
	}
    }
    
    if ( $content =~ /\x1F[ax]($term_regexp)($|\x1F)/ ) {
        return $1;
    }

    return undef;
}



sub record_has_term($$$$) {
    my ( $id, $record, $term, $lexicon ) = @_;
    my @contents = marc21_record_get_fields($record, '650', undef);

    for ( my $i=0; $i <= $#contents; $i++ ) {
        my $content = field_content_has_term($contents[$i], $term, $lexicon);
        if ( defined($content) ) {
            return $content;
        }
    }
    return undef;
}

sub has_place($$$$) {
    my ( $id, $record, $term, $lexicon ) = @_;
    my @contents = marc21_record_get_fields($record, '650', undef);
    for ( my $i=0; $i <= $#contents; $i++ ) {
        my $content = $contents[$i];
        if ( $content =~ /\x1F[z]($term)($|\x1F)/ ) {
            return $term;
        }
    }

    @contents = marc21_record_get_fields($record, '651', undef);

    for ( my $i=0; $i <= $#contents; $i++ ) {
        my $content = $contents[$i];
        if ( $content =~ /\x1F[az]($term)($|\x1F)/ ) {
            return $term;
        }
    }
    return undef;
}


sub switch_lexicon_get_ids($$$);
sub switch_lexicon_get_ids($$$) {
    my ( $term, $from, $to ) = @_;

    my ( $lex, $lang ) = lexlang2lex_and_lang($to);
    my $new_ids = new_pref_label2unambiguous_id($term, $lex, $lang) || 0;
    print STDERR "SLGI: '$term' ", ( $new_ids ? $new_ids : 'no match' ), "\n";

    if ( $new_ids ) { return $new_ids; }

    # Remove punctuation and try again:
    my $alt_term = $term;
    if ( $alt_term =~ s/(.)\.$/$1/ ) {
	$new_ids = switch_lexicon_get_ids($alt_term, $from, $to) || 0;
	if ( $new_ids ) { # remove punc from $a:
	    return $new_ids;
	}
    }

    return $new_ids;
}

sub switch_lexicon_get_unambiguous_id($$$) {
    my ( $term, $from, $to ) = @_;
    my $ids = switch_lexicon_get_ids($term, $from, $to);
    if ( $ids =~ /\t/ ) { return 0; }
    return $ids;
}




sub yso_id_is_actually_ysopaikat_id($$) {
    die();
    my ( $id ) = @_;

    if ( id2pref_label($id, 'yso/fin') ) {
	return 0;
    }
    if ( id2pref_label($id, 'yso-paikat/fin') ) {
	return 1;
    }
    return 0;
}
    

sub switch_lexicon($$$$) {
    my ( $tag, $content, $from, $to ) = @_;


    if ( $content !~ /\x1F2$from($|\x1F)/ ) { return $content; }

    if ( $to =~ /^(allars|soto|slm\/fin|slm\/swe|yso\/fin|yso\/swe|yso\/eng|yso-aika\/fin|yso-aika\/swe|yso|yso-paikat\/fin|yso-paikat\/swe|yso-paikat\/eng)$/ ) {
	if ( $content =~ /^.7\x1Fa([^\x1F]+)\x1F2\Q$from\E(\x1F[059][^\x1F]+)*$/ ) {
	    my $term = $1;
	    my $new_id = switch_lexicon_get_unambiguous_id($term, $from, $to);
	    print STDERR "SL: '$term' $from => $to?\n";
	    if ( !$new_id ) {
		return $content;
	    }
	    # Hack. We really don't want to make yso/eng terms:
	    if ( $from eq 'pha' ) {
		if ( $to eq 'yso/eng' ) {
		    $to = 'yso/fin';
		}
		if ( $to eq 'yso-paikat/eng' ) {
		    $to = 'yso-paikat/fin';
		    $tag = '651'; # just to make lex_add_sf0() work...
		}
	    }

	    my ( $to_lex, $to_lang ) = lexlang2lex_and_lang($to);
	    
	    my $new_term = new_id2unambiguous_pref_label($new_id, $to_lex, $to_lang);
	    
	    if ( defined($new_term) ) {
		$content =~ s/\x1Fa[^\x1F]+/\x1Fa$new_term/;
		$to = normalize_yso_lexicon_name($to); 
		$content =~ s/\x1F2[^\x1F]+/\x1F2$to/;
		
		$content =~ s/\x1F0[^\x1F]+//; # remove $0 (should replace this though)
		$content = lex_add_sf0($content, $tag);
		if ( $content =~ /\x1F2yso-/ ) {
		    die($content);
		}
	    }
	}
    }
    else {
	die("Unsupported '$to'");
    }
    return $content;
}


sub lex_add_sf0($$) {
    my ( $content, $tag ) = @_;

    # No need to add -optimization:
    if ( index($content, "\x1F0") > -1 ) { return $content; }

    #die($tag.": ".kk_marc21_field::fieldToString($content));

    # NB! Hard-coded $a!!!
    if ( $tag =~ /^(257|370|380|388|648|65[015])$/ &&
	 # lex/lang
	 ( $content =~ /^..(?:\x1F8[^\x1F]+)*\x1Fa([^\x1F]+)\x1F2(mts|slm|yso)\/(fin|swe)(\x1F9[A-Z]+<(DROP|KEEP)>)*$/ ||
	   # lex only
	   $content =~ /^..(?:\x1F8[^\x1F]+)*\x1Fa([^\x1F]+)\x1F2(soto)()(\x1F9[A-Z]+<(DROP|KEEP)>)*$/ ) ) { # TODO: support $5 and $9, entäs alku-$8:t?
	print STDERR "lex_add_sf0('$content', $tag)\n";
        my $cand_term = $1;
        my $cand_lex = $2;
	my $cand_lang = $3;
	if ( $cand_lex eq 'soto' ) {
	    $cand_lang = 'fin';
	}
	
	#die(kk_marc21_field::fieldToString($content));
	my $tmp_lex = $cand_lex;
        if ( $tag eq '257' ||$tag eq '370' || $tag eq '651' ) { # 651: yso -> yso-paikat
            $tmp_lex =~ s/^yso/yso-paikat/;
	}
	elsif ( $tag eq '388' || $tag eq '648' ) {
	    $tmp_lex =~ s/^yso/yso-aika/;
	}
	
	my $cand_id = new_pref_label2unambiguous_id($cand_term, $tmp_lex, $cand_lang);
	
	# If miss, try without ending-'.'
	if ( !defined($cand_id) && $cand_term =~ s/(.)\.$/$1/ ) {
	    $cand_id = new_pref_label2unambiguous_id($cand_term, $tmp_lex, $cand_lang);
	    if ( $cand_id ) {
		$content =~ s/\x1Fa[^\x1F]+/\x1Fa$cand_term/;
	    }
	}

	if ( !defined($cand_id) || !$cand_id ) {
	    print STDERR "WARNING: lex_add_sf0: no id found for '$cand_term'\n";
	    return $content;
	}	

	print STDERR "FOUND: '$cand_id'...\n";

	my $url_base = get_url_base($cand_lex);
	if ( !defined($url_base{$cand_lex}) ) {
	    print STDERR "WARNING: no url found for $tag '$content'\n";
	    return $content;
	}
	$cand_id =~ s/^\D+//;
	my $url = $url_base{$cand_lex} . $cand_id;

	
	$content =~ s/(\x1F2[^\x1F]+)/$1\x1F0$url/ or die();
    }
    # Periaatteessa varmaan replikointisuojaukset olis kivoja fenni- ja
    # violakeepeille, mutta tämä kun on oma fiksi, niin en ole vielä
    # implementoinut...

    return $content;
}      



sub sf2_lex_add_missing_language_suffix($) {
    my ( $content ) = @_;
    
    my $baselex = get_lex($content);
    # NB! Kauno is not currently supported (out of laziness at least)
    if ( !defined($baselex) || $baselex !~ /^(mts|slm|yso)$/ ) {
	return $content;
    }
    print STDERR "CHECKING '$content' vs $baselex\n";

    # Allow $a $x* $2 $0? $9?
    if ( $content =~ /^..\x1Fa([^\x1F]+)\x1F2[^\x1F]+(\x1F[059][^\x1F]+)*$/ ) {
	my $cand_term = $1;
	my @arr = split(/\x1F/, $content);
	my @langlist = ( 'fin', 'swe' );
	for ( my $j=0; $j <= $#langlist; $j++ ) {
	    my $cand_lang = $langlist[$j];

	    my $ok = 0;

	    
	    if ( defined(new_any_label2ids($cand_term, $baselex, $cand_lang)) ) {
		$ok = 1;
	    }
	    # Support yso-paikat:
	    if ( !$ok && $baselex eq 'yso' ) {
		if ( defined(new_any_label2ids($cand_term, 'yso-aika', $cand_lang)) ||
		     defined(new_any_label2ids($cand_term, 'yso-paikat', $cand_lang))) {
		    $ok = 1;
		}
	    }

	    if ( $ok ) {
		print STDERR "FIX CONTENT '", kk_marc21_field::fieldToString($content), "', ADD LANG $cand_lang\n";
		$content =~ s/(\x1F2[^\x1F]+)/$1\/$cand_lang/;
		return $content;
	    }
	}
    }
    return $content;
}



sub lex_and_id2url($$) {
    my ( $lex, $id ) = @_;

    if ( $lex eq 'yso/fin' || $lex eq 'yso/swe' ) {
	if ( $id =~ /^\d+$/ ) { $id = "p$id"; }
	if ( $id !~ /^p\d+$/ ) { return undef; }
	return "http://www.yso.fi/onto/yso/".$id;
    }
    if ( $lex eq 'slm/fin' || $lex eq 'slm/swe' ) {
	if ( $id =~ /^\d+$/ ) { $id = "s$id"; }
	if ( $id !~ /^s\d+$/ ) { return undef; }
	return "https:\/\/urn.fi\/URN:NBN:fi:au:slm:$id";
    }
    print STDERR "lex_and_id2url($lex, $id) failed!\n";
    return undef;
}


sub map_sf0_to_lex($) {
    # Argument can be either whole field or subfield 0's value
    my $sf = shift();
    if ( $sf =~ /\x1F0([^\x1F]+)/ ) { # map field to subfield
        $sf = $1;
    }

    if ( $sf =~ /^https?:\/\/www\.yso\.fi\/onto\/yso\/p\d+$/ ) {
        return 'yso';
    }

    #if ( $sf =~ /^https?:\/\/urn.fi\/URN:NBN:fi:au:(kaunokki|mts|slm):[a-z]?\d+$/ ) {
    if ( $sf =~ /^https?:\/\/urn.fi\/URN:NBN:fi:au:(mts|slm):[a-z]?\d+$/ ) {
        return $1;
    }

    print STDERR "Unable to map $sf to a lexicon!\n";
    return undef;
}



sub sfa_and_sf2_match($) {
    my $content = shift();
    my $sf2 = get_lex($content);
    die($content);
    #if ( defined($sf2) && $sf2 =~ /^(kaunokki|slm\/fin|slm\/swe|yso\/fin|yso\/swe)$/ ) {
    if ( defined($sf2) && $sf2 =~ /^(slm\/fin|slm\/swe|yso\/fin|yso\/swe)$/ ) {
	if ( $content =~ /\x1Fa([^\x1F]+)/ ) {
	    my $sfa = $1;
	    print STDERR "TEST SFA IS '$sfa'\n";
	    if ( $content =~ /\x1Fa.*\x1Fa/ ) {
		print STDERR "WARNING: Multiple \$a fields: '$content'\n";
		return 0;
	    }

	    #my $id = pref_label2id($sfa, $sf2) || alt_label2id($sfa, $sf2) || 0;
	    my $id = pref_label2id($sfa, $sf2) || 0;
	    print STDERR "\$a $sfa \$2 $sf2 = $id\n";
	    if ( $id ) { return $id; }
	    
	    if ( $sf2 =~ /^yso/ ) {
		my $tmp = $sf2;
		$tmp =~ s/^yso/yso-paikat/;
		#$id = pref_label2id($sfa, $tmp) || alt_label2id($sfa, $tmp) || 0;
		$id = pref_label2id($sfa, $tmp) || 0;
		if ( $id ) { return $id; }

		$tmp = $sf2;
		$tmp =~ s/^yso/yso-aika/;
		$id = pref_label2id($sfa, $tmp) || 0;
		if ( $id ) { return $id; }
	    }
	}
    }
    return 0;
}


sub sf0_and_sf2_match($) {
    my $content = shift();
    if ( $content =~ /\x1F0([^\x1F]+)/ ) {
	my $sf0 = $1;

	if ( $content =~ /\x1F0.*\x1F0/ ) {
	    die();
	    return 0;
	}
	if ( $content =~ /\x1F2([^\x1F]+)/ ) {
	    my $sf2 = $1;
	    if ( $content =~ /\x1F2.*\x1F2/ ) {
		die();
		return 0;
	    }
	    my $sf0lex = map_sf0_to_lex($sf0);
	    if ( !defined($sf0lex) ) {
		return 0;
	    }
	    if ( $sf0lex eq 'slm' && ( $sf2 eq 'slm/fin' || $sf2 eq 'slm/swe' )  ) {
		return 1;
	    }
	    if ( $sf0lex eq 'yso' && ( $sf2 eq 'yso/fin' || $sf2 eq 'yso/swe' )  ) {
		return 1;
	    }

	    if ( $sf0lex eq $sf2 ) {
		print STDERR "sf0_and_sf2_match(): warning '$sf2' not supported by this function!\n";
	    }
	}
    }
    return 0;
}



sub sfa_and_sf2_to_link($) {
    my $content = shift();
    print STDERR "2LINK...\n";
    my $id = sfa_and_sf2_match($content);
    if ( !defined($id) || $id eq "0" || $id =~ /\t/ ) { return undef; }

    if ( 0 && $content =~ /\x1F2kaunokki($|\x1F)/ ) {
	return "http://urn.fi/URN:NBN:fi:au:kaunokki:".$id;
    }
    if ( $content =~ /\x1F2slm\/(fin|swe)($|\x1F)/ ) {
	return "http://urn.fi/URN:NBN:fi:au:slm:s".$id;
    }
    if ( $content =~ /\x1F2yso\/(fin|swe)($|\x1F)/ ) {
	return "http://www.yso.fi/onto/yso/".$id;
    }

    return undef;    
}    
    
sub den_andra_inhemska($) {
    my $lex = shift;
    if ( $lex =~ s/\/fin$/\/swe/ || $lex =~ s/\/swe$/\/fin/ ) {
        return $lex;
    }
    if ( $lex eq 'bella' ) { return 'kaunokki'; }
    if ( $lex eq 'kaunokki' ) { return 'bella'; }
    return undef;
}


sub is_valid_a20($) {
    my $content = shift;

    print STDERR "IS VALID a20?\n";
    my $id = sfa_and_sf2_match($content);
    if ( !$id ) { return 0; }

    $content =~ s/\x1F2([^\x1F]+)//;
    my $lex = $1;
    if ( !defined($lex) ) { return 0; }
    #die("ID: $id LEX: $lex");
    my $url = lex_and_id2url($lex, $id);
    if ( !defined($url) ) { return 0; }
    #die("ID: $id LEX: $lex URL: $url");
    $content =~ s/\x1F0([^\x1F]+)//;
    my $identifier = $1;
    if ( !defined($identifier) ) { return 0; }

    if ( $identifier eq $url ) { return 1; }
    
    return 0;
}

sub fix_650_yso_swe_amnen_p3403($$) {
    my ( $marc_record_ref, $content ) = @_;
    if ( $content =~ /\x1Faämnen\x1F2yso\/swe\x1F0[^\x1F]+p3403($|\x1F)/ ) {
	#die($content);
	my @fields = ${$marc_record_ref}->get_all_matching_fields('650');
	foreach my $field ( @fields ) {
	    # Finnish version would translate to this nowadays:
	    if ( $field->{content} =~ /\x1Faaiheet\x1F2yso\/fin\x1F0[^\x1F]+p3403($|\x1F)/ ) {
		$content =~ s/\x1Faämnen\x1F/\x1Faämnen (områden)\x1F/;
		return $content;
	    }
	}
    }
    return $content;
}

sub fix_650_yso_swe_dopning2dopning_idrott_p5674($$) {
    my ( $marc_record_ref, $content ) = @_;
    if ( $content =~ /\x1Fadopning\x1F2yso\/swe\x1F0[^\x1F]+p5674($|\x1F)/ ) {
	#die($content);
	my @fields = ${$marc_record_ref}->get_all_matching_fields('650');
	foreach my $field ( @fields ) {
	    # Finnish version would translate to this nowadays:
	    if ( $field->{content} =~ /\x1Fadoping\x1F2yso\/fin\x1F0[^\x1F]+p5674($|\x1F)/ ) {
		$content =~ s/\x1Fadopning\x1F/\x1Fadopning (idrott)\x1F/;
		return $content;
	    }
	}
    }
    return $content;
}

sub lexicon_id2yso_id($$) {
    my ( $lexicon_name, $skos_id ) = @_;    
    read_lexicon($lexicon_name);
    return $lexica{$lexicon_name}{'yso'}{$skos_id};
}

# TODO:
# "kielet" & "opetusmenetelmät" => "kieltenopetus"
# jos "koulut" ja "kiusaaminen" niin lisää "koulukiusaaminen"...
#
1;

