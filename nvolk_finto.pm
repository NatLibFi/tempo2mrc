use nvolk_marc21;
use strict;
use LWP::Simple;

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


# $2 vs indikaattori 2 ei ole 7:
# Esim. jos $2 ysa ja sisältö on ysaa, niin indikaattori vaihdetaan
#
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

# TODO: fix $ykl

my %keyword_cache;

our $skip_suspicious_alt_labels = 1;
our $allars_loaded = 0;
our $musa_loaded = 0;
our $kauno_loaded = 0;
our $kaunokki_loaded = 0;
our $seko_loaded = 0;
our $slm_loaded = 0;
our $soto_loaded = 0;
our $ysa_loaded = 0;
our $yso_loaded = 0;
our $yso_aika_loaded = 0;
our $yso_paikat_loaded = 0;

our %musa_ylakasite;

our %allars_id2allars_pref_label;
our %kauno_id2kaunofin_pref_label;
our %kauno_id2kaunoswe_pref_label;
our %kaunokki_id2kaunokki_pref_label;
our %kaunokki_id2bella_pref_label;
our %musa_id2musa_pref_label;
our %musa_id2cilla_pref_label;
our %soto_id2sotofin_pref_label;
our %ysa_id2ysa_pref_label;
our %yso_id2ysoeng_pref_label;
our %yso_id2ysofin_pref_label;
our %yso_id2ysoswe_pref_label;
our %ysoaika_id2ysoaikaeng_pref_label;
our %ysoaika_id2ysoaikafin_pref_label;
our %ysoaika_id2ysoaikaswe_pref_label;
our %ysopaikat_id2ysopaikateng_pref_label;
our %ysopaikat_id2ysopaikatfin_pref_label;
our %ysopaikat_id2ysopaikatswe_pref_label;


our %allars_pref_label2allars_id;
our %bella_pref_label2kaunokki_id;
our %cilla_pref_label2musa_id;
our %kaunofin_pref_label2kauno_id;
our %kaunoswe_pref_label2kauno_id;
our %kaunokki_pref_label2kaunokki_id;
our %musa_pref_label2musa_id;
our %sotofin_pref_label2soto_id;
our %ysa_pref_label2ysa_id;
our %ysoeng_pref_label2yso_id;
our %ysofin_pref_label2yso_id;
our %ysoswe_pref_label2yso_id;
our %ysoaikaeng_pref_label2ysoaika_id;
our %ysoaikafin_pref_label2ysoaika_id;
our %ysoaikaswe_pref_label2ysoaika_id;
our %ysopaikateng_pref_label2ysopaikat_id;
our %ysopaikatfin_pref_label2ysopaikat_id;
our %ysopaikatswe_pref_label2ysopaikat_id;

our %allars_alt_label2allars_id;
our %bella_alt_label2kaunokki_id;
our %cilla_alt_label2musa_id;
our %kaunofin_alt_label2kauno_id;
our %kaunoswe_alt_label2kauno_id;
our %kaunokki_alt_label2kaunokki_id;
our %musa_alt_label2musa_id;
our %sotofin_alt_label2soto_id;
our %ysa_alt_label2ysa_id;
our %ysoeng_alt_label2yso_id;
our %ysofin_alt_label2yso_id;
our %ysoswe_alt_label2yso_id;
our %ysoaikaeng_alt_label2ysoaika_id;
our %ysoaikafin_alt_label2ysoaika_id;
our %ysoaikaswe_alt_label2ysoaika_id;
our %ysopaikateng_alt_label2ysopaikat_id;
our %ysopaikatfin_alt_label2ysopaikat_id;
our %ysopaikatswe_alt_label2ysopaikat_id;

our %musa_id2ysa_id;
#our %ysa_id2musa_id;

our %ysa_id2allars_id;
our %allars_id2ysa_id;

our %allars_id2geographical_concept;
our %ysa_id2geographical_concept;

our %slm_id2slm_pref_label_fi;
our %slm_id2slm_pref_label_sv;
our %slm_pref_label_fi2slm_id;
our %slm_pref_label_sv2slm_id;
our %slmfin_alt_label2slm_id;
our %slmswe_alt_label2slm_id;

our %seko_id2seko_pref_label;
our %seko_pref_label2seko_id;

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

sub remove_term($$$$) {
    my ( $record, $tag, $term, $lexicon) = @_;
    my $id = marc21_record_get_field($record, '001', undef);
    my @contents = marc21_record_get_fields($record, $tag, undef);
    for ( my $i=$#contents; $i >= 0; $i-- ) {
        my $content = $contents[$i];
        if ( field_has_term($content, $term, $lexicon ) ) {
            if ( $content =~ /^..\x1Fa\Q$term\E\x1F2/ ) {
                # pois
                print STDERR "$id\tDELETE $tag FIELD '$content'\n";
                print STDERR "$id $tag  '$content' => NULL\n";
                $record = marc21_record_remove_nth_field($record, $tag, undef, $i);
            }
            elsif ( $content =~ s/^(..\x1F)a\Q$term\E\x1F([xyz])/$1$2/ ||
                    $content =~ s/\x1Fx\Q$term\E\x1F/\x1F/ ) {
                print STDERR "$id\tREMOVE TERM '$term' from $tag FIELD\n";
                print STDERR "$id $tag  '$contents[$i]' => '$content'\n";
                $record = marc21_record_replace_nth_field($record, $tag, $content, $i);
            }
            else {
                print STDERR "$id\tFAILED TO REMOVE TERM '$term' from '$content'\n";
            }
        }
    }
    return $record;
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

sub is_finto_keyword($$) {
    my ( $keyword, $lex ) = @_;
    $keyword =~ s/^(.+) \(\d+\)$/$1/; # poista jäsenmäärä lopusta
    my $dkeyword = finto_composition($keyword);
    
    # keyword encoded/decoded fixes

    if ( defined($keyword_cache{"$keyword\t$lex"}) ) {
        return $keyword_cache{"$keyword\t$lex"};
    }

    my $orig_lex = $lex;

    my $lang = 'fi';
    if ( $lex eq 'cilla' || $lex eq 'allars' ) {
        $lang = 'sv';
    }

    if ( $lex eq 'cilla' ) {
        $lex = 'musa';
    }

    my $url = "http://api.finto.fi/rest/v1/search?vocab=$lex&query=$dkeyword&lang=$lang";

    my $search = get($url);
    my $result = 0;
    if ( !defined($search) ) {
        print STDERR "URL $url failed! KEYWORD: '$keyword'\n";
    } else {
        $result = ( $search =~ /,"results":\[\]/ ? 0 : 1 );
    }
    print STDERR "FINTO\t$orig_lex\t$keyword\t$result\n";
    $keyword_cache{"$keyword\t$orig_lex"} = $result;
    return $result;
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

sub _download_url($) {
    my $url = $_[0];

    my $basename = &_strip_path($url);

    if ( -e $basename ) {
	my $n_days = 1;
        if ( -s $basename && -M $basename < $n_days ) {
            print STDERR "Our version of '$basename' is less than $n_days day(s) old. Not updating it!\n";
            return;
        }
        # musa ei enää päivity, joten sitä on turha ladatakaan
        if ( $basename =~ /musa/ ) {
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

        print STDERR " Write content to $basename\n";
        my $FH;
        open($FH, ">:encoding(UTF-8)", $basename) or die($!);
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







sub musa_id2ysa_id($) {
    my $musa_id = shift();
    &read_musa_and_cilla();
    return $musa_id2ysa_id{$musa_id};
}


sub load_lexicon_entries($) {
    my $url = shift();
    &_download_url($url); # saves it as file
    my $file_name = &_strip_path($url);
    my $text = &_read_file($file_name);
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

sub read_allars() {
    if ( $allars_loaded ) {
        return;
    }
    $allars_loaded = 1;

    my $lex_url = "http://api.finto.fi/download/allars/allars-skos.ttl";
    my @allars = &load_lexicon_entries($lex_url);

    print STDERR "Tutkitaan ", ($#allars+1), " Allärsin entrtyä...\n";

    for ( my $i=0; $i <= $#allars; $i++ ) {
        my $concept = $allars[$i];
        if ( $concept =~ /^:(Y\d+) a skos/ ) {
            my $allars_id = $1;
            #print STDERR "Allärs ID $allars_id\n";
            # Hae YSA-Allärs-parit:
            my $ysa_id = 0;

            while ( my $pref_label = _get_single_entry(\$concept, 'skos:exactMatch' ) ) {
                if ( $pref_label =~ /^ysa:(Y\d+)$/ ) {
                    $ysa_id = $1;
                    if ( !defined($ysa_id2allars_id{$ysa_id}) ) {
                        $ysa_id2allars_id{$ysa_id} = $allars_id;
                    }
                    else {
                        die();
                    }
                    if ( !defined($allars_id2ysa_id{$allars_id}) ) {
                        $allars_id2ysa_id{$allars_id} = $ysa_id;
                    }
                    else {
                        die();
                    }
                }
            }

            # print STDERR " MAPPED Allars $allars_id and Ysa $ysa_id\n";


            #if ( defined($allars_id2allars_pref_label{$allars_id}) ) {
            while ( my $pref_label = _get_single_entry(\$concept, 'skos:prefLabel' ) ) {
                #print STDERR " read allärs '$pref_label'\n";
                if ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                    my $allars_term = $1;
                    if ( defined($allars_id2allars_pref_label{$allars_id}) ) {
                        die();
                    }
                    else {
                        $allars_id2allars_pref_label{$allars_id} = $allars_term;
                    }

                    if ( !defined($allars_pref_label2allars_id{$allars_term}) ) {
                        $allars_pref_label2allars_id{$allars_term} = $allars_id;
                    }
                    else {
                        # Huom. Allärsissa on kaksi katalysatorer-termiä
                        print STDERR "ALLARS\t$pref_label redefined\t", $allars_id, "\n";
                        $allars_pref_label2allars_id{$allars_term} .= "\t" . $allars_id;
                    }
                }
                else {
                    print STDERR "SKIP prefLabel '$pref_label'\n";
                }
            }
            if ( $concept =~ /GeographicalConcept/ ) {
                $allars_id2geographical_concept{$allars_id} = 1;
            }

            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel' ) ) {
                    if ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($allars_alt_label2allars_id{$term}) ) {
                            $allars_alt_label2allars_id{$term} .= "\t".$allars_id;
                            # print STDERR "CRAP: '$term' is an alternative for many Allärs terms...", $allars_alt_label2allars_id{$term}, "\n";

                        }
                        else {
                            $allars_alt_label2allars_id{$term} = $allars_id;
                            if ( 0 && $term =~ /--/ ) {
                                my $real = $allars_id2allars_pref_label{$allars_id};
                                print STDERR "ALLÄRS MULTIPART ALT\t$term\t$real\n";
                            }
                        }
                    }
                }
            }
        }
    }

    if ( $skip_suspicious_alt_labels ) {
        # Sulkutiedoista johdetaan lisää moniselitteisyyttä

        my %suspicious = pref_hack(\%allars_pref_label2allars_id);
        foreach my $key ( sort keys %suspicious ) {
            my $ids = $suspicious{$key};
            print STDERR "Allärs: checking suspicious $key\n";

            if ( !defined($allars_alt_label2allars_id{$key}) ) {
                # ÄLÄ TEE UUSIA!
                #print STDERR " ALT LABEL: polysemy hack #2 implemented for '$key': $ids\n";
                # Musa->Yso -kokous ei tykkää tästä... (koska menuetti vs menuetit...)
                # $allars_alt_label2allars_id{$key} = $ids;
            }
            else {
                print STDERR " ALLÄRS: Checking suspicious $key: $ids\n";
                my @id_stack = split(/\t/, $ids);
                for ( my $j=0; $j <= $#id_stack; $j++ ) {
                    my $cand_id = $id_stack[$j];
                    print STDERR "  ALLÄRS: Checking suspicious $key: $cand_id\n";

                    if ( $allars_alt_label2allars_id{$key} !~ /(^|\t)$cand_id($|\t)/ ) {
                        if ( $allars_alt_label2allars_id{$key} !~ /\t/ ) {
                            print STDERR " ALT LABEL: polysemy hack implemented for '$key'\n";
                        }
                        $allars_alt_label2allars_id{$key} .= "\t".$cand_id;
                    }
                }
            }
        }
    }

}

sub read_musa_and_cilla() {
    if ( $musa_loaded ) {
        return;
    }
    $musa_loaded = 1;

    my $musa_url = "http://api.finto.fi/download/musa/musa-skos.ttl";
    my @musa = &load_lexicon_entries($musa_url);

    for ( my $i=0; $i <= $#musa; $i++ ) {
        my $concept = $musa[$i];
        if ( $concept =~ /^musa:(p\d+) a skos:Concept ;/ ) {
            my $musa_id = $1;

            if ( $concept =~ /dct:broader musa:(p\d+) ;/ ) { # yläkäsite
                my $ylakasite = $1;
                if ( defined($musa_ylakasite{$musa_id}) ) { die(); }
                $musa_ylakasite{$musa_id} = $ylakasite;
            }
            elsif ( $concept =~ /dct:broader / ) { die(); }

            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($musa_alt_label2musa_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/musa is an alternative for many terms...", $musa_alt_label2musa_id{$term}, "\n";
                            $musa_alt_label2musa_id{$term} .= "\t".$musa_id;
                        }
                        else {
                            $musa_alt_label2musa_id{$term} = $musa_id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($cilla_alt_label2musa_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $cilla_alt_label2musa_id{$term} .= "\t".$musa_id;
                        }
                        else {
                            $cilla_alt_label2musa_id{$term} = $musa_id;
                        }
                    }
                }
            }

            my $continue = 0;
            if ( $concept =~ /dct:isReplacedBy ysa:(Y\d+) ;/ ) {
                my $target_ysa = $1;
                #print STDERR " Trying to map MUSA ID $musa_id to YSA ID $target_ysa\n";
                $musa_id2ysa_id{$musa_id} = $target_ysa;
                #$ysa_id2musa_id{$target_ysa} = $musa_id;
                $continue = 1;
            }
            elsif ( $concept =~ /dct:isReplacedBy ysa:(Y\d+),\s+ysa:(Y\d+) ;/ ) {
                my $target_ysa = $1 . "\t" . $2;
                #print STDERR " Trying to map MUSA ID $musa_id to YSA ID $target_ysa\n";
                $musa_id2ysa_id{$musa_id} = $target_ysa;
                #$ysa_id2musa_id{$target_ysa} = $musa_id;
                $continue = 1;
            }
            elsif ( $concept !~ /dct:isReplacedBy/ ) {
                $continue = 1;
            }
            
            if ( $continue ) {
                my $pref_label;
                #my $key = 'skos:prefLabel';
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                    # print STDERR "  $pref_label\n";
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($musa_id2musa_pref_label{$musa_id}) ) {
                            $musa_id2musa_pref_label{$musa_id} = $keyword;
                            # print STDERR "  MUSA ID $musa_id PREF LABEL $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$musa_id} .= "\t".$keyword;
                            #print STDERR "MUSA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($musa_pref_label2musa_id{$keyword}) ) {
                            $musa_pref_label2musa_id{$keyword} = $musa_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "MUSA\t$pref_label redefined\t", $musa_id, "\n";
                            die();
                        }
                    }
                    elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $keyword = $1;
                        if ( !defined($musa_id2cilla_pref_label{$musa_id}) ) {
                            $musa_id2cilla_pref_label{$musa_id} = $keyword;
                            #print STDERR "  MUSA/CILLA ID $musa_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$musa_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($cilla_pref_label2musa_id{$keyword}) ) {
                            $cilla_pref_label2musa_id{$keyword} = $musa_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "CILLA\t$pref_label redefined\t", $musa_id, "\n";
                            die();
                        }
                    }
                    else {
                        print STDERR "TODO: prefLabel '$pref_label'\n";
                    }
                }
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    print STDERR "Read complete: musa\&cilla\n";
}

sub read_kaunokki_and_bella() {
    if ( $kaunokki_loaded ) {
        return;
    }

    $kaunokki_loaded = 1;

    #my $kaunokki_url = "finto.fi/rest/v1/kaunokki/data?format=text/turtle";

    my $kaunokki_url = "http://api.finto.fi/download/kaunokki/kaunokki-skos.ttl";



    print STDERR "Loading kaunokki via $kaunokki_url...\n";
    
    my @kaunokki = &load_lexicon_entries($kaunokki_url);

    for ( my $i=0; $i <= $#kaunokki; $i++ ) {
        my $concept = $kaunokki[$i];
        if ( $concept =~ /^<http:\/\/urn\.fi\/.*:kaunokki:(\d+)> a owl:Class,\s*skos:Concept,/s || # old, stopped working at some point
	     $concept =~ /^kaunokki:(\d+) a owl:Class,\s+skos:Concept,\s+kaunokkimeta:Concept ;/ ) {
            my $kaunokki_id = $1;
	    
            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($kaunokki_alt_label2kaunokki_id{$term}) ) {
                            print STDERR "CRAP: '$term'/kaunokki is an alternative for many terms...", $kaunokki_alt_label2kaunokki_id{$term}, "\n";
                            $kaunokki_alt_label2kaunokki_id{$term} .= "\t".$kaunokki_id;
                        }
                        else {
                            $kaunokki_alt_label2kaunokki_id{$term} = $kaunokki_id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($bella_alt_label2kaunokki_id{$term}) ) {
                            print STDERR "CRAP: '$term'/bella is an alternative for many terms...", $bella_alt_label2kaunokki_id{$term}, "\n";
                            $bella_alt_label2kaunokki_id{$term} .= "\t".$kaunokki_id;
                        }
                        else {
                            $bella_alt_label2kaunokki_id{$term} = $kaunokki_id;
                        }
                    }
                }
            }


            if ( 1 ) { # perl pabel
                my $pref_label;
                #my $key = 'skos:prefLabel';
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                    # print STDERR "  $pref_label\n";
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($kaunokki_id2kaunokki_pref_label{$kaunokki_id}) ) {
                            $kaunokki_id2kaunokki_pref_label{$kaunokki_id} = $keyword;
                            # print STDERR "  KAUNOKKI ID $kaunokki_id PREF LABEL $keyword\n";
                        }
                        else {
                            $kaunokki_id2kaunokki_pref_label{$kaunokki_id} .= "\t".$keyword;
                            print STDERR "KAUNOKKI\t$kaunokki_id redefined\t", $kaunokki_id, "\n";
                            die();

                        }
                        if ( !defined($kaunokki_pref_label2kaunokki_id{$keyword}) ) {
                            $kaunokki_pref_label2kaunokki_id{$keyword} = $kaunokki_id;
                            # print STDERR "  KAUNOKKI ID $kaunokki_id $keyword\n";
                        }
                        else {
                            # print STDERR "KAUNOKKI\t$pref_label redefined\t", $kaunokki_id, "\n";
			    $kaunokki_pref_label2kaunokki_id{$keyword} .= "\t".$kaunokki_id;
                            # die(); # toisto
                        }
                    }
                    elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $keyword = $1;
                        if ( !defined($kaunokki_id2bella_pref_label{$kaunokki_id}) ) {
                            $kaunokki_id2bella_pref_label{$kaunokki_id} = $keyword;
                            # print STDERR "  KAUNOKKI/BELLA ID $kaunokki_id $keyword\n";
                        }
                        else {
                            $kaunokki_id2bella_pref_label{$kaunokki_id} .= "\t".$keyword;
                            # print STDERR "KAUNOKKI/BELLA\t$kaunokki_id redefined\t", $kaunokki_id, "\n";
                            die();

                        }
                        if ( !defined($bella_pref_label2kaunokki_id{$keyword}) ) {
                            $bella_pref_label2kaunokki_id{$keyword} = $kaunokki_id;
                            # print STDERR "  KAUNOKKI ID $kaunokki_id $keyword\n";
                        }
                        else {
                            # print STDERR "BELLA\t$pref_label redefined\t", $kaunokki_id, "\n";
			    $bella_pref_label2kaunokki_id{$keyword} .= "\t".$kaunokki_id;
                            #die(); # rivalitet...
                        }
                    }
                    else {
                        print STDERR "TODO: prefLabel '$pref_label'\n";
                    }
                }
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    print STDERR "Read complete: kaunokki\&bella\n";
}

sub read_seko() {
    if ( $seko_loaded ) { return; }
    $seko_loaded = 1;

    my $url = "http://api.finto.fi/download/seko/seko-skos.ttl";
    my @lex = &load_lexicon_entries($url);

    print STDERR "Tutkitaan ", ($#lex+1), " Seko-entryä...\n";

    for ( my $i=0; $i <= $#lex; $i++ ) {
        my $concept = $lex[$i];
        if ( $concept =~ /^<(http:\S+:seko:\d+)> a skos/ ) {
            my $id = $1;
            print STDERR "SEKO ID $id\n";
            # Otetaanko closeMatch-ysa-kama
            my $ysa_id = 0;
            #while ( my $pref_label = _get_single_entry(\$concept, 'skos:closeMatch' ) ) { }

            my $key = 'skos:prefLabel';
            while ( my $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                print STDERR " read seko '$pref_label'\n";
                if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                    my $term = $1;
                    if ( defined($seko_id2seko_pref_label{$id}) ) {
                        die();
                    }
                    else {
                        $seko_id2seko_pref_label{$id} = $term;
                    }

                    if ( defined($seko_pref_label2seko_id{$term}) ) {
                        die();
                    }
                    else {
                        $seko_pref_label2seko_id{$term} = $id;
                    }

                }
                else {
                    die();
                }
            }
        }
    }
}

sub read_slm() {
    if ( $slm_loaded ) { return; }
    $slm_loaded = 1;
    my $url = "http://api.finto.fi/download/slm/slm-skos.ttl";
    my @lex = &load_lexicon_entries($url);

    print STDERR "Tutkitaan ", ($#lex+1), " SLM-entryä...\n";

    for ( my $i=0; $i <= $#lex; $i++ ) {
        my $concept = $lex[$i];
        if ( $concept =~ /^slm:(s\d+) a skos/ ) {
            my $id = $1;
            #print STDERR "SLM ID $id\n";
            # Otetaanko closeMatch-ysa-kama

            #while ( my $pref_label = _get_single_entry(\$concept, 'skos:closeMatch' ) ) { }

            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($slmfin_alt_label2slm_id{$term}) ) {
                            $slmfin_alt_label2slm_id{$term} .= "\t".$id;
                        }
                        else {
                            $slmfin_alt_label2slm_id{$term} = $id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($slmswe_alt_label2slm_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $slmswe_alt_label2slm_id{$term} .= "\t".$id;
                        }
                        else {
                            $slmswe_alt_label2slm_id{$term} = $id;
                        }
                    }
                }
            }
            
            while ( my $pref_label = _get_single_entry(\$concept, 'skos:prefLabel' ) ) {

                if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                    my $term = $1;
                    #print STDERR " read slm term '$term' (fi)\n";
                    if ( defined($slm_id2slm_pref_label_fi{$id}) ) {
                        die();
                    }
                    else {
                        $slm_id2slm_pref_label_fi{$id} = $term;
                    }

                    if ( defined($slm_pref_label_fi2slm_id{$term}) ) {
                        die();
                    }
                    else {
                        $slm_pref_label_fi2slm_id{$term} = $id;
                    }

                }
                elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                    my $term = $1;

                    #print STDERR " read slm term '$term' (sv)\n";
                    if ( defined($slm_id2slm_pref_label_sv{$id}) ) {
                        die();
                    }
                    else {
                        $slm_id2slm_pref_label_sv{$id} = $term;
                    }
                    if ( defined($slm_pref_label_sv2slm_id{$term}) ) {
                        die();
                    }
                    else {
                        $slm_pref_label_sv2slm_id{$term} = $id;
                    }
                }
                else {
                    die();
                }
            }

            
        }
    }
}

sub read_ysa() {
    if ( $ysa_loaded ) {
        return;
    }
    $ysa_loaded = 1;

    my $ysa_url = "http://api.finto.fi/download/ysa/ysa-skos.ttl";
    my @ysa = &load_lexicon_entries($ysa_url);

    for ( my $i=0; $i <= $#ysa; $i++ ) {
        my $concept = $ysa[$i];
        if ( $concept =~ /^:(Y\d+) a skos/ ) {
            my $id = $1;
            # print STDERR " Got YSA ID $id\n";
            #my $key = 'skos:prefLabel';
            while ( my $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                # print STDERR " read ysa '$pref_label'\n";
                if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                    my $ysa_term = $1;
                    if ( defined($ysa_id2ysa_pref_label{$id}) ) {
                        die();
                        $ysa_id2ysa_pref_label{$id} .= "\t".$ysa_term;
                    }
                    else {
                        $ysa_id2ysa_pref_label{$id} = $ysa_term;
                    }
                    if ( !defined($ysa_pref_label2ysa_id{$ysa_term}) ) {
                        $ysa_pref_label2ysa_id{$ysa_term} = $id;
                        #print STDERR "  YSA ID $id $ysa_term\n";
                    }
                    else {
                        print STDERR "YSA\t$pref_label redefined\t", $id, "\n";
                        if ( $pref_label !~ /Galitsia/ ) {
                            die();
                        }
                    }
                }
                else {
                    print STDERR "SKIP prefLabel '$pref_label'\n";
                }
            }

            if ( $concept =~ /GeographicalConcept/ ) {
                $ysa_id2geographical_concept{$id} = 1;
            }

            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel' ) ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($ysa_alt_label2ysa_id{$term}) ) {
                            $ysa_alt_label2ysa_id{$term} .= "\t".$id;
                            #print STDERR "CRAP: '$term' is an alternative for many YSA terms...", $ysa_alt_label2ysa_id{$term}, "\n";

                        }
                        else {
                            $ysa_alt_label2ysa_id{$term} = $id;

                            if ( $term =~ /--/ ) {
                                my $real = $ysa_id2ysa_pref_label{$id};
                                # print STDERR "YSA MULTIPART ALT\t$term\t$real\n";
                            }
                        }
                    }
                }
            }
        }
    }


    if ( $skip_suspicious_alt_labels ) {
        # Add polysemy
        my %suspicious = pref_hack(\%ysa_pref_label2ysa_id);
        foreach my $key ( sort keys %suspicious ) {
            my $ids = $suspicious{$key};
            print STDERR "YSA: checking suspicious $key\n";

            if ( !defined($ysa_alt_label2ysa_id{$key}) ) {
                # ÄLÄ LISÄÄ YKSISELITTEISIÄ!
                # Ei uskalleta tehdä tätä. Esim. musassa menuetit on jakautuneet
                # kahtia "menuetti (foo)" ja "menuetit (bar)", joka bugaisi
                # print STDERR " ALT LABEL: polysemy hack #2 implemented for '$key': $ids\n";
                #$ysa_alt_label2ysa_id{$key} = $ids;
            }
            else {
                print STDERR " YSA: Checking suspicious $key: $ids\n";
                my @id_stack = split(/\t/, $ids);
                for ( my $j=0; $j <= $#id_stack; $j++ ) {
                    my $cand_id = $id_stack[$j];
                    print STDERR "  YSA: Checking suspicious $key: $cand_id\n";

                    if ( $ysa_alt_label2ysa_id{$key} !~ /(^|\t)$cand_id($|\t)/ ) {
                        if ( $ysa_alt_label2ysa_id{$key} !~ /\t/ ) {
                            print STDERR " ALT LABEL: polysemy hack implemented for '$key'\n";
                        }
                        $ysa_alt_label2ysa_id{$key} .= "\t".$cand_id;
                    }
                }
            }
        }
    }
}

sub read_soto() {
    if ( $soto_loaded ) {
        return;
    }
    $soto_loaded = 1;

    my $url = "http://api.finto.fi/download/soto/soto-skos.ttl";
    my @lexicon_or_onthology = &load_lexicon_entries($url);
    
    for ( my $i=0; $i <= $#lexicon_or_onthology; $i++ ) {
        my $concept = $lexicon_or_onthology[$i];
        $concept = unicode_fixes2($concept, $finto_debug);
	# LOL: soto seems to be a subset of yso...
        if ( $concept =~ /^((soto|yso):(p\d+)) a skos:Concept(,\s*(yso-|soto)meta:(Concept|Individual))? ;/s ) {
            my $concept_id = $1;
            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;

                        if ( defined($sotofin_alt_label2soto_id{$term}) ) {
			    # Prefer soto over yso #1:
			    if ( $sotofin_alt_label2soto_id{$term} =~ /^yso:p\d+(\tyso:p\d+)*$/ && $concept_id =~ /^soto:p\d+$/ ) {
				$sotofin_alt_label2soto_id{$term} = $concept_id;
			    }
			    # Prefer soto over yso #2:
			    elsif ( $sotofin_alt_label2soto_id{$term} =~ /^soto:p\d+$/ && $concept_id =~ /^yso:p\d+$/ ) {
				# do nothing
			    }
			    else {
				$sotofin_alt_label2soto_id{$term} .= "\t".$concept_id;
				#die("$term vs $concept_id vs ".$sotofin_alt_label2soto_id{$term});

				print STDERR "SOTO ALT $term vs $concept_id vs ", $sotofin_alt_label2soto_id{$term}, "\n";
			    }
			}
                        else {
                            $sotofin_alt_label2soto_id{$term} = $concept_id;
                        }
                    }
		    # Only Finnish is relevant for my purposes
                }
            }

            if ( 1 ) {
                my $pref_label;
                #my $key = 'skos:prefLabel';
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                    # print STDERR "  $pref_label\n";
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($soto_id2sotofin_pref_label{$concept_id}) ) {
                            $soto_id2sotofin_pref_label{$concept_id} = $keyword;
                            # print STDERR "  MUSA ID $musa_id PREF LABEL $keyword\n";
                        }
                        else {
                            die();
                        }
                        if ( !defined($sotofin_pref_label2soto_id{$keyword}) ) {
                            $sotofin_pref_label2soto_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
			elsif ( $sotofin_pref_label2soto_id{$keyword} =~ /^yso:p\d+$/ && $concept_id =~ /^soto:p\d+$/ ) {
			    $sotofin_pref_label2soto_id{$keyword} = $concept_id;
			}
			elsif ( $sotofin_pref_label2soto_id{$keyword} =~ /^soto:p\d+$/ && $concept_id =~ /^yso:p\d+$/ ) {
			    # do nothing, soto overrides yses
			}
			elsif ( $sotofin_pref_label2soto_id{$keyword} =~ /^soto:p\d+$/ && $concept_id =~ /^soto:p\d+$/ ) {
			    print STDERR "NB! SOTO HAS MULTIPLE DEFS OF '$keyword'!\n";
			    $sotofin_pref_label2soto_id{$keyword} .= "\t$concept_id";

			}
                        else {
                            print STDERR "SOTO\t$pref_label redefined\t", $concept_id, " vs ", $sotofin_pref_label2soto_id{$keyword}, "\n";
                            die();
                        }
                    }
		    else {
                        if ( $pref_label !~ /\@(en|sv)$/ ) {
                            print STDERR "TODO: prefLabel '$pref_label'\n";
                        }
                    }
                }
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    print STDERR "Read complete: SOTO\n";
}

sub read_yso() {
    if ( $yso_loaded ) {
        return;
    }
    $yso_loaded = 1;

    my $yso_url = "http://api.finto.fi/download/yso/yso-skos.ttl";
    my @yso = &load_lexicon_entries($yso_url);
    
    for ( my $i=0; $i <= $#yso; $i++ ) {
        my $concept = $yso[$i];
        $concept = unicode_fixes2($concept, $finto_debug);
        if ( $concept =~ /^yso:(p\d+) a skos:Concept,\s*yso-meta:(Concept|Hierarchy|Individual) ;/s ) {
            my $yso_id = $1;
	    
            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($ysofin_alt_label2yso_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/yso is an alternative for many terms...", $musa_alt_label2musa_id{$term}, "\n";
                            $ysofin_alt_label2yso_id{$term} .= "\t".$yso_id;
                        }
                        else {
                            $ysofin_alt_label2yso_id{$term} = $yso_id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($ysoswe_alt_label2yso_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $ysoswe_alt_label2yso_id{$term} .= "\t".$yso_id;
                        }
                        else {
                            $ysoswe_alt_label2yso_id{$term} = $yso_id;
                        }
                    }
		    elsif ( $alt_label =~ /^\"(.*)\"\@en$/ ) {
                        my $term = $1;
                        if ( defined($ysoeng_alt_label2yso_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $ysoeng_alt_label2yso_id{$term} .= "\t".$yso_id;
                        }
                        else {
                            $ysoeng_alt_label2yso_id{$term} = $yso_id;
                        }
                    }
                }
            }

            if ( 1 ) {
                my $pref_label;
                #my $key = 'skos:prefLabel';
		my $breakpoint = 0;
		if ( $concept =~ /\"(arkkitehtuuri|keskinäinen toiminta|suomenruotsalaiset)\"/ ) {
		    $breakpoint = 1;
		}
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
		    if ( $breakpoint ) {
			print STDERR "  PREF LABEL: $pref_label\n";
		    }
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($yso_id2ysofin_pref_label{$yso_id}) ) {
                            $yso_id2ysofin_pref_label{$yso_id} = $keyword;
			    if ( $breakpoint ) {
				print STDERR "  YSO FIN ID $yso_id PREF LABEL $keyword\n";
			    }
                        }
                        else {
                            die();
                            #$yso_id2ysofin_pref_label{$yso_id} .= "\t".$keyword;
                            #print STDERR "YSO\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($ysofin_pref_label2yso_id{$keyword}) ) {
                            $ysofin_pref_label2yso_id{$keyword} = $yso_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "YSO\t$pref_label redefined\t", $yso_id, "\n";
                            die();
                        }
                    }
                    elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $keyword = $1;
                        if ( !defined($yso_id2ysoswe_pref_label{$yso_id}) ) {
                            $yso_id2ysoswe_pref_label{$yso_id} = $keyword;
                            #print STDERR "  MUSA/CILLA ID $musa_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$musa_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($ysoswe_pref_label2yso_id{$keyword}) ||
			     
			     # hack: ignore polysemous basaar
			     $yso_id eq 'p39308' ) {
                            $ysoswe_pref_label2yso_id{$keyword} = $yso_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "YSO/SWE\t$pref_label redefined\t", $yso_id, "\n";
                            $ysoswe_pref_label2yso_id{$keyword} .= "\t$yso_id";
                        }
                    }
		    elsif ( $pref_label =~ /^\"(.*)\"\@en$/ ) {
                        my $keyword = $1;
                        if ( !defined($yso_id2ysoeng_pref_label{$yso_id}) ) {
                            $yso_id2ysoeng_pref_label{$yso_id} = $keyword;
                            #print STDERR "  MUSA/CILLA ID $musa_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$musa_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($ysoeng_pref_label2yso_id{$keyword}) ||
			     
			     # hack: ignore polysemous basaar
			     $yso_id eq 'p39308' ) {
                            $ysoeng_pref_label2yso_id{$keyword} = $yso_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "YSO/ENG\t$pref_label redefined\t", $yso_id, "\n";
			    # English pref label has no uniqueness requirement
                            $ysoeng_pref_label2yso_id{$keyword} .= "\t$yso_id";

                        }
                    }
		    elsif ( $pref_label =~ /^\"(.*)\"\@sm?e$/ ) {
			# ignore saame for now, list to avoid complaints
		    }
                    else {
			print STDERR "TODO: prefLabel '$pref_label'\n";
                    }
                }

		if ( $breakpoint ) {
		    #die($concept);
		}
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    my @keys = keys %ysofin_pref_label2yso_id;
    print STDERR "Read complete: YSO. ", ($#keys+1), " keys read\n";

    
}

sub read_kauno() {
    if ( $kauno_loaded ) {
        return;
    }
    $kauno_loaded = 1;
    #print STDERR "LOAD KAUNO...\n";
    my $lex_url = "http://api.finto.fi/download/kauno/kauno-skos.ttl";
    my @lex = &load_lexicon_entries($lex_url);

    for ( my $i=0; $i <= $#lex; $i++ ) {
        my $concept = $lex[$i];
	# 2021-01-18: "kauno-meta" has changed to "kaunometa" at some point.
        if ( $concept =~ /^kauno:(p\d+) a skos:Concept,\s*kauno-?meta:Concept ;/s ) {
            my $lex_id = $1;

            if ( 0 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($kaunofin_alt_label2kauno_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/musa is an alternative for many terms...", $musa_alt_label2musa_id{$term}, "\n";
                            $kaunofin_alt_label2kauno_id{$term} .= "\t".$lex_id;
                        }
                        else {
                            $kaunofin_alt_label2kauno_id{$term} = $lex_id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($kaunoswe_alt_label2kauno_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $kaunoswe_alt_label2kauno_id{$term} .= "\t".$lex_id;
                        }
                        else {
                            $kaunoswe_alt_label2kauno_id{$term} = $lex_id;
                        }
                    }
                }
            }

            if ( 1 ) {
                my $pref_label;
                #my $key = 'skos:prefLabel';
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                    #print STDERR "  $pref_label\n";
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($kauno_id2kaunofin_pref_label{$lex_id}) ) {
                            $kauno_id2kaunofin_pref_label{$lex_id} = $keyword;
                            # print STDERR "  MUSA ID $musa_id PREF LABEL $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$musa_id} .= "\t".$keyword;
                            #print STDERR "MUSA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($kaunofin_pref_label2kauno_id{$keyword}) ) {
                            $kaunofin_pref_label2kauno_id{$keyword} = $lex_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "KAUNO\tERROR? PREF LABEL $pref_label redefined\t", $lex_id, "\n";
                            #die();
                        }
                    }
                    elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $keyword = $1;
                        if ( !defined($kauno_id2kaunoswe_pref_label{$lex_id}) ) {
                            $kauno_id2kaunoswe_pref_label{$lex_id} = $keyword;
                            #print STDERR "  MUSA/CILLA ID $musa_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$musa_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($kaunoswe_pref_label2kauno_id{$keyword}) ) {
                            $kaunoswe_pref_label2kauno_id{$keyword} = $lex_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "KAUNO/SWE\t$pref_label redefined\t", $lex_id, "\n";
                            #die();
                        }
                    }
                    else {
                        print STDERR "TODO: prefLabel '$pref_label'\n";
                    }
                }
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    print STDERR "Read complete: KAUNO\n";
}


sub read_yso_aika() {
    if ( $yso_aika_loaded ) {
        return;
    }

    $yso_aika_loaded = 1;

	#my $url = "https://finto.fi/rest/v1/yso-aika/data?format=text/turtle"; # http://api.finto.fi/download/yso-aika/yso-aika-skos.ttl";
	my $url = "http://api.finto.fi/download/yso-aika/yso-aika-skos.ttl";
    my @yso_aika = &load_lexicon_entries($url);

	
    for ( my $i=0; $i <= $#yso_aika; $i++ ) {
        my $concept = $yso_aika[$i];

	if ( $concept =~ /^yso:(p\d+) a skos:Concept,\s*yso-meta:(Century|Decade|Milllennium) ;/s ) {
            my $concept_id = $1;
            #$concept = unicode_fixes2($concept, $finto_debug);
            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($ysoaikafin_alt_label2ysoaika_id{$term}) ) {
                            $ysoaikafin_alt_label2ysoaika_id{$term} .= "\t".$concept_id;
                        }
                        else {
                            $ysoaikafin_alt_label2ysoaika_id{$term} = $concept_id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($ysoaikaswe_alt_label2ysoaika_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $ysoaikaswe_alt_label2ysoaika_id{$term} .= "\t".$concept_id;
                        }
                        else {
                            $ysoaikaswe_alt_label2ysoaika_id{$term} = $concept_id;
                        }
                    }
		    elsif ( $alt_label =~ /^\"(.*)\"\@en$/ ) {
			my $term = $1;
                        if ( defined($ysoaikaeng_alt_label2ysoaika_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $ysoaikaeng_alt_label2ysoaika_id{$term} .= "\t".$concept_id;
                        }
                        else {
                            $ysoaikaeng_alt_label2ysoaika_id{$term} = $concept_id;
                        }
                    }
                }
            }

            if ( 1 ) {
                my $pref_label;
                #my $key = 'skos:prefLabel';
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                    # print STDERR "  $pref_label\n";
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($ysoaika_id2ysoaikafin_pref_label{$concept_id}) ) {
                            $ysoaika_id2ysoaikafin_pref_label{$concept_id} = $keyword;
                            # print STDERR "  MUSA ID $musa_id PREF LABEL $keyword\n";
                        }
                        else {
                            die();
                            #print STDERR "MUSA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($ysoaikafin_pref_label2ysoaika_id{$keyword}) ) {
                            $ysoaikafin_pref_label2ysoaika_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "ERROR\tYSO-AIKA\t$pref_label redefined\t", $concept_id, "\n";
                            #die();
                        }
                    }
                    elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $keyword = $1;
                        if ( !defined($ysoaika_id2ysoaikaswe_pref_label{$concept_id}) ) {
                            $ysoaika_id2ysoaikaswe_pref_label{$concept_id} = $keyword;
                            #print STDERR "  YSO-AIKA/SWE ID $concept_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$concept_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$concept_id redefined\t", $concept_id, "\n";
                        }
                        if ( !defined($ysoaikaswe_pref_label2ysoaika_id{$keyword}) ) {
                            $ysoaikaswe_pref_label2ysoaika_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "ERROR\tYSO-AIKA/SWE\t$pref_label redefined\t", $concept_id, "\n";
                            #die();
                        }
                    }
		    elsif ( $pref_label =~ /^\"(.*)\"\@en$/ ) {
                        my $keyword = $1;
                        if ( !defined($ysoaika_id2ysoaikaeng_pref_label{$concept_id}) ) {
                            $ysoaika_id2ysoaikaeng_pref_label{$concept_id} = $keyword;
                            #print STDERR "  YSO-AIKA/SWE ID $concept_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$concept_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$concept_id redefined\t", $concept_id, "\n";
                        }
                        if ( !defined($ysoaikaeng_pref_label2ysoaika_id{$keyword}) ) {
                            $ysoaikaeng_pref_label2ysoaika_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "ERROR\tYSO-AIKA/ENG\t$pref_label redefined\t", $concept_id, "\n";
                            #die();
                        }
                    }
                    else {
			if ( $pref_label !~ /\@en$/ ) {
			    print STDERR "TODO: prefLabel '$pref_label'\n";
			}
                    }
                }
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    print STDERR "Read complete: YSO-AIKA\n";
}


sub read_yso_paikat() {
    if ( $yso_paikat_loaded ) {
        return;
    }
    $yso_paikat_loaded = 1;

    my $url = "http://api.finto.fi/download/yso-paikat/yso-paikat-skos.ttl";
    my @yso_paikat = &load_lexicon_entries($url);

    for ( my $i=0; $i <= $#yso_paikat; $i++ ) {
        my $concept = $yso_paikat[$i];
        if ( $concept =~ /^yso:(p\d+) a skos:Concept ;/s ) {
            my $concept_id = $1;
            $concept = unicode_fixes2($concept, $finto_debug);
            if ( 1 ) { # altLabel
                my $tmp = $concept;
                while ( my $alt_label = _get_single_entry(\$tmp, 'skos:altLabel') ) {
                    if ( $alt_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $term = $1;
                        if ( defined($ysopaikatfin_alt_label2ysopaikat_id{$term}) ) {
                            $ysopaikatfin_alt_label2ysopaikat_id{$term} .= "\t".$concept_id;
                        }
                        else {
                            $ysopaikatfin_alt_label2ysopaikat_id{$term} = $concept_id;
                        }
                    }
                    elsif ( $alt_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $term = $1;
                        if ( defined($ysopaikatswe_alt_label2ysopaikat_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $ysopaikatswe_alt_label2ysopaikat_id{$term} .= "\t".$concept_id;
                        }
                        else {
                            $ysopaikatswe_alt_label2ysopaikat_id{$term} = $concept_id;
                        }
                    }
		    elsif ( $alt_label =~ /^\"(.*)\"\@en$/ ) {
			my $term = $1;
                        if ( defined($ysopaikateng_alt_label2ysopaikat_id{$term}) ) {
                            #print STDERR "CRAP: '$term'/cilla is an alternative for many terms...", $cilla_alt_label2musa_id{$term}, "\n";
                            $ysopaikateng_alt_label2ysopaikat_id{$term} .= "\t".$concept_id;
                        }
                        else {
                            $ysopaikateng_alt_label2ysopaikat_id{$term} = $concept_id;
                        }
                    }
                }
            }

            if ( 1 ) {
                my $pref_label;
                #my $key = 'skos:prefLabel';
                while ( $pref_label = _get_single_entry(\$concept, 'skos:prefLabel') ) {
                    # print STDERR "  $pref_label\n";
                    if ( $pref_label =~ /^\"(.*)\"\@fi$/ ) {
                        my $keyword = $1;
                        if ( !defined($ysopaikat_id2ysopaikatfin_pref_label{$concept_id}) ) {
                            $ysopaikat_id2ysopaikatfin_pref_label{$concept_id} = $keyword;
                            # print STDERR "  MUSA ID $musa_id PREF LABEL $keyword\n";
                        }
                        else {
                            die();
                            #print STDERR "MUSA\t$musa_id redefined\t", $musa_id, "\n";
                        }
                        if ( !defined($ysopaikatfin_pref_label2ysopaikat_id{$keyword}) ) {
                            $ysopaikatfin_pref_label2ysopaikat_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "ERROR\tYSO-PAIKAT\t$pref_label redefined\t", $concept_id, "\n";
                            #die();
                        }
                    }
                    elsif ( $pref_label =~ /^\"(.*)\"\@sv$/ ) {
                        my $keyword = $1;
                        if ( !defined($ysopaikat_id2ysopaikatswe_pref_label{$concept_id}) ) {
                            $ysopaikat_id2ysopaikatswe_pref_label{$concept_id} = $keyword;
                            #print STDERR "  YSO-PAIKAT/SWE ID $concept_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$concept_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$concept_id redefined\t", $concept_id, "\n";
                        }
                        if ( !defined($ysopaikatswe_pref_label2ysopaikat_id{$keyword}) ) {
                            $ysopaikatswe_pref_label2ysopaikat_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "ERROR\tYSO-PAIKAT/SWE\t$pref_label redefined\t", $concept_id, "\n";
                            #die();
                        }
                    }
		    elsif ( $pref_label =~ /^\"(.*)\"\@en$/ ) {
                        my $keyword = $1;
                        if ( !defined($ysopaikat_id2ysopaikateng_pref_label{$concept_id}) ) {
                            $ysopaikat_id2ysopaikateng_pref_label{$concept_id} = $keyword;
                            #print STDERR "  YSO-PAIKAT/SWE ID $concept_id $keyword\n";
                        }
                        else {
                            die();
                            #$musa_id2musa_pref_label{$concept_id} .= "\t".$keyword;
                            #print STDERR "MUSA/CILLA\t$concept_id redefined\t", $concept_id, "\n";
                        }
                        if ( !defined($ysopaikateng_pref_label2ysopaikat_id{$keyword}) ) {
                            $ysopaikateng_pref_label2ysopaikat_id{$keyword} = $concept_id;
                            #print STDERR "  MUSA ID $musa_id $keyword\n";
                        }
                        else {
                            print STDERR "ERROR\tYSO-PAIKAT/ENG\t$pref_label redefined\t", $concept_id, "\n";
                            #die();
                        }
                    }
                    else {
			if ( $pref_label !~ /\@en$/ ) {
			    print STDERR "TODO: prefLabel '$pref_label'\n";
			}
                    }
                }
            }
            else { # Näitä ei klaarattu...
                die();
            }
        }
    }
    print STDERR "Read complete: YSO-PAIKAT\n";
}


# Group: type *_alt_label2*_id
sub allars_alt_label2allars_id($) {
    my $term = shift();
    &read_musa_and_cilla(); # init if necessary
    return $allars_alt_label2allars_id{$term};
}

sub cilla_alt_label2musa_id($) {
    my $term = shift();
    &read_musa_and_cilla(); # init if necessary
    return $cilla_alt_label2musa_id{$term};
}


sub kaunofin_alt_label2kauno_id($) {
    my $term = shift();
    &read_kauno(); # init if necessary
    return $kaunofin_alt_label2kauno_id{$term};
}

sub kaunoswe_alt_label2kauno_id($) {
    my $term = shift();
    &read_kauno(); # init if necessary
    return $kaunoswe_alt_label2kauno_id{$term};
}

sub kaunokki_alt_label2kaunokki_id($) {
    my $term = shift();
    &read_kaunokki_and_bella(); # init if necessary
    return $kaunokki_alt_label2kaunokki_id{$term};
}

sub bella_alt_label2kaunokki_id($) {
    my $term = shift();
    &read_kaunokki_and_bella(); # init if necessary
    return $bella_alt_label2kaunokki_id{$term};
}

sub musa_alt_label2musa_id($) {
    my $term = shift();
    &read_musa_and_cilla(); # init if necessary
    return $musa_alt_label2musa_id{$term};
}

sub sotofin_alt_label2soto_id($) {
    my $term = shift();
    &read_soto(); # init if necessary
    return $sotofin_alt_label2soto_id{$term};
}

sub ysa_alt_label2ysa_id($) {
    my $term = shift();
    &read_ysa(); # init if necessary
    return $ysa_alt_label2ysa_id{$term};
}

sub ysoeng_alt_label2yso_id($) {
    my $term = shift();
    &read_yso(); # init if necessary
    return $ysoeng_alt_label2yso_id{$term};
}

sub ysofin_alt_label2yso_id($) {
    my $term = shift();
    &read_yso(); # init if necessary
    return $ysofin_alt_label2yso_id{$term};
}

sub ysoswe_alt_label2yso_id($) {
    my $term = shift();
    &read_yso(); # init if necessary
    return $ysoswe_alt_label2yso_id{$term};
}

sub ysoaikaeng_alt_label2ysoaika_id($) {
    my $term = shift();
    &read_yso_aika(); # init if necessary
    return $ysoaikaeng_alt_label2ysoaika_id{$term};
}

sub ysopaikateng_alt_label2ysopaikat_id($) {
    my $term = shift();
    &read_yso_paikat(); # init if necessary
    return $ysopaikateng_alt_label2ysopaikat_id{$term};
}

sub ysoaikafin_alt_label2ysoaika_id($) {
    my $term = shift();
    &read_yso_aika(); # init if necessary
    return $ysoaikafin_alt_label2ysoaika_id{$term};
}

sub ysopaikatfin_alt_label2ysopaikat_id($) {
    my $term = shift();
    &read_yso_paikat(); # init if necessary
    return $ysopaikatfin_alt_label2ysopaikat_id{$term};
}



sub ysoaikaswe_alt_label2ysoaika_id($) {
    my $term = shift();
    &read_yso_aika(); # init if necessary
    return $ysoaikaswe_alt_label2ysoaika_id{$term};
}

sub ysopaikatswe_alt_label2ysopaikat_id($) {
    my $term = shift();
    &read_yso_paikat(); # init if necessary
    return $ysopaikatswe_alt_label2ysopaikat_id{$term};
}

# group: *_id2geographic_concept

sub allars_id2geographical_concept($) {
    my $id = shift();
    &read_allars(); # init if necessary
    if ( defined($allars_id2geographical_concept{$id}) ) {
        return 1;
    }
    return 0;
}

sub ysa_id2geographical_concept($) {
    my $id = shift();
    &read_ysa(); # init if necessary
    if ( defined($ysa_id2geographical_concept{$id}) ) {
        #die(ysa_id2ysa_pref_label($id));
        return 1;
    }
    return 0;
}

# Group: *_id2*_pref_label

sub allars_id2allars_pref_label($) {
    my $id = shift();
    &read_allars(); # init if necessary
    return $allars_id2allars_pref_label{$id};
}

sub musa_id2cilla_pref_label($) {
    my $id = shift();
    &read_musa_and_cilla(); # init if necessary
    return $musa_id2cilla_pref_label{$id};
}

sub kaunokki_id2kaunokki_pref_label($) {
    my $id = shift();
    &read_kaunokki_and_bella(); # init if necessary
    return $kaunokki_id2kaunokki_pref_label{$id};
}

sub kaunokki_id2bella_pref_label($) {
    my $id = shift();
    &read_kaunokki_and_bella(); # init if necessary
    return $kaunokki_id2bella_pref_label{$id};
}


sub musa_id2musa_pref_label($) {
    my $id = shift();
    &read_musa_and_cilla(); # init if necessary
    return $musa_id2musa_pref_label{$id};
}


sub seko_id2seko_pref_label($) {
    my $id = shift();
    &read_seko();
    return $seko_id2seko_pref_label{$id};
}

sub slm_id2slm_pref_label_fi($) {
    my $id = shift();
    &read_slm();
    return $slm_id2slm_pref_label_fi{$id};
}

sub slm_id2slm_pref_label_sv($) {
    my $id = shift();
    &read_slm();
    return $slm_id2slm_pref_label_sv{$id};
}

sub soto_id2soto_pref_label($) {
    my $id = shift();
    &read_soto(); # init if necessaary
    return $soto_id2sotofin_pref_label{$id};
}

sub ysa_id2ysa_pref_label($) {
    my $id = shift();
    &read_ysa(); # init if necessaary
    return $ysa_id2ysa_pref_label{$id};
}

sub yso_id2ysoeng_pref_label($) {
    my $id = shift();
    &read_yso(); # init if necessaary
    return $yso_id2ysoeng_pref_label{$id};
}

sub yso_id2ysofin_pref_label($) {
    my $id = shift();
    &read_yso(); # init if necessaary
    return $yso_id2ysofin_pref_label{$id};
}

sub yso_id2ysoswe_pref_label($) {
    my $id = shift();
    &read_yso(); # init if necessaary
    return $yso_id2ysoswe_pref_label{$id};
}

sub ysoaika_id2ysoaikaeng_pref_label($) {
    my $id = shift();
    &read_yso_aika(); # init if necessaary
    return $ysoaika_id2ysoaikaeng_pref_label{$id};
}

sub ysoaika_id2ysoaikafin_pref_label($) {
    my $id = shift();
    &read_yso_aika(); # init if necessaary
    return $ysoaika_id2ysoaikafin_pref_label{$id};
}

sub ysoaika_id2ysoaikaswe_pref_label($) {
    my $id = shift();
    &read_yso_aika(); # init if necessaary
    return $ysoaika_id2ysoaikaswe_pref_label{$id};
}

sub ysopaikat_id2ysopaikateng_pref_label($) {
    my $id = shift();
    &read_yso_paikat(); # init if necessaary
    return $ysopaikat_id2ysopaikateng_pref_label{$id};
}

sub ysopaikat_id2ysopaikatfin_pref_label($) {
    my $id = shift();
    &read_yso_paikat(); # init if necessaary
    return $ysopaikat_id2ysopaikatfin_pref_label{$id};
}

sub ysopaikat_id2ysopaikatswe_pref_label($) {
    my $id = shift();
    &read_yso_paikat(); # init if necessaary
    return $ysopaikat_id2ysopaikatswe_pref_label{$id};
}

# Group: *_pref_label2*_id
##########################
sub allars_pref_label2allars_id($) {
    my $term = shift();
    &read_allars(); # init if necessary
    return $allars_pref_label2allars_id{$term};
}

sub cilla_pref_label2musa_id($) {
    my $term = shift();
    &read_musa_and_cilla(); # init if necessary
    return $cilla_pref_label2musa_id{$term};
}


sub kaunofin_pref_label2kauno_id($) {
    my $term = shift();
    &read_kauno(); # init if necessary
    return $kaunofin_pref_label2kauno_id{$term};
}

sub kaunoswe_pref_label2kauno_id($) {
    my $term = shift();
    &read_kauno(); # init if necessary
    return $kaunoswe_pref_label2kauno_id{$term};
}

sub kaunokki_pref_label2kaunokki_id($) {
    my $term = shift();
    &read_kaunokki_and_bella(); # init if necessary
    return $kaunokki_pref_label2kaunokki_id{$term};
}

sub bella_pref_label2kaunokki_id($) {
    my $term = shift();
    &read_kaunokki_and_bella(); # init if necessary
    return $bella_pref_label2kaunokki_id{$term};
}

sub musa_pref_label2musa_id($) {
    my $term = shift();
    &read_musa_and_cilla(); # init if necessary
    return $musa_pref_label2musa_id{$term};
}

sub seko_pref_label2seko_id($) {
    my $term = shift();
    &read_seko(); # init if necessary
    return $seko_pref_label2seko_id{$term};
}

sub slmfin_alt_label2slm_id($) {
    my $term = shift();
    &read_slm(); # init if necessary
    return $slmfin_alt_label2slm_id{$term};
}

sub slmswe_alt_label2slm_id($) {
    my $term = shift();
    &read_slm(); # init if necessary
    return $slmswe_alt_label2slm_id{$term};
}

sub slm_pref_label_fi2slm_id($) {
    my $term = shift();
    &read_slm(); # init if necessary
    return $slm_pref_label_fi2slm_id{$term};
}

sub slm_pref_label_sv2slm_id($) {
    my $term = shift();
    &read_slm(); # init if necessary
    return $slm_pref_label_sv2slm_id{$term};
}

sub sotofin_pref_label2soto_id($) {
    my $term = shift();
    &read_soto(); # init if necessary
    return $sotofin_pref_label2soto_id{$term};
}

sub ysa_pref_label2ysa_id($) {
    my $term = shift();
    &read_ysa(); # init if necessary
    return $ysa_pref_label2ysa_id{$term};
}

sub ysoeng_pref_label2yso_id($) {
    my $term = shift();
    &read_yso(); # init if necessary
    return $ysoeng_pref_label2yso_id{$term};
}

sub ysofin_pref_label2yso_id($) {
    my $term = shift();
    &read_yso(); # init if necessary
    return $ysofin_pref_label2yso_id{$term};
}

sub ysoswe_pref_label2yso_id($) {
    my $term = shift();
    &read_yso(); # init if necessary
    return $ysoswe_pref_label2yso_id{$term};
}


sub ysoaikaeng_pref_label2ysoaika_id($) {
    my $term = shift();
    &read_yso_aika(); # init if necessary
    return $ysoaikaeng_pref_label2ysoaika_id{$term};
}

sub ysoaikafin_pref_label2ysoaika_id($) {
    my $term = shift();
    &read_yso_aika(); # init if necessary
    return $ysoaikafin_pref_label2ysoaika_id{$term};
}

sub ysoaikaswe_pref_label2ysoaika_id($) {
    my $term = shift();
    &read_yso_aika(); # init if necessary
    return $ysoaikaswe_pref_label2ysoaika_id{$term};
}


sub ysopaikateng_pref_label2ysopaikat_id($) {
    my $term = shift();
    &read_yso_paikat(); # init if necessary
    return $ysopaikateng_pref_label2ysopaikat_id{$term};
}

sub ysopaikatfin_pref_label2ysopaikat_id($) {
    my $term = shift();
    &read_yso_paikat(); # init if necessary
    return $ysopaikatfin_pref_label2ysopaikat_id{$term};
}

sub ysopaikatswe_pref_label2ysopaikat_id($) {
    my $term = shift();
    &read_yso_paikat(); # init if necessary
    return $ysopaikatswe_pref_label2ysopaikat_id{$term};
}










sub map_musa_id2ysa_id($) {
    my ( $musa_id ) = @_;

    if ( $musa_id =~ /\t/ ) {
        print STDERR "Musa ID $musa_id has many values in Musa! Skip...\n";
        return undef;
    }

    my $ysa_id = &musa_id2ysa_id($musa_id);

    if ( !defined($ysa_id) ) {
        print STDERR "Musa ID $musa_id does not map to YSA! Skip...\n";
        return undef;
    }

    if ( $ysa_id =~ /\t/ ) {
        print STDERR "Musa ID $musa_id maps to many values in YSA! Skip...\n";
        die();
        return undef;
    }

    return $ysa_id;
}

sub map_musa_term2ysa_id($$$$) {
    my ( $id, $tag, $sf_code, $sf_data ) = @_;

    my $musa_id = &musa_pref_label2musa_id($sf_data);

    if ( !defined($musa_id) ) {
        print STDERR "BIB-$id\tTerm '$sf_data' not found in Musa! Skip...\n";
        return undef;
    }

    my $ysa_id = map_musa_id2ysa_id($musa_id);

    return $ysa_id;
    # The rest is legacy code. Check whether we want to use it somewhere...
    #NV#  my $ysa_term = $ysa_id2ysa_pref_label{$ysa_id};
    #NV#  if ( $ysa_term =~ /\t/ ) {
    #NV#    print STDERR "Musa term '$sf_data'/$musa_id maps to many terms in YSA '$ysa_term'! Skip...\n";
    #NV#    die();
    #NV#    return undef;
    #NV#  }
    #NV#
    #NV#  # We are checking whether the term exists in slm or seko!
    #NV#  # NB! We are using the MUSA term as such, not the correspoding ysa term!
    #NV#  if ( !($tag == '650' && $db_name eq 'violadb') ) {
    #NV#    my $slm_id = &slm_pref_label_fi2slm_id($sf_code);
    #NV#    my $seko_id = &seko_pref_label2seko_id($sf_code);
    #NV#
    #NV#    if ( defined($slm_id) && defined($seko_id) ) {
    #NV#      print STDERR "$id\t$sf_code\tkuuluu myös SLM:ään ja Sekoon\n";
    #NV#      return undef;
    #NV#    }
    #NV#    elsif ( defined($slm_id) ) {
    #NV#      print STDERR "$id\t$sf_code\tkuuluu myös SLM:ään\n";
    #NV#      return undef;
    #NV#    }
    #NV#    elsif ( defined($seko_id) ) {
    #NV#      print STDERR "$id\t$sf_code\tkuuluu myös Sekoon\n";
    #NV#      return undef;
    #NV#    }
    #NV#  }
    #NV#  return $ysa_id;
}


sub map_cilla_term2allars_id($$$$) {
    my ( $id, $tag, $sf_code, $sf_data ) = @_;


    if ( !defined($cilla_pref_label2musa_id{$sf_data}) ) {
        print STDERR "BIB-$id\tTerm '$sf_data' not found in Cilla! Skip...\n";
        return undef;
    }

    my $musa_id = $cilla_pref_label2musa_id{$sf_data};

    my $ysa_id = map_musa_id2ysa_id($musa_id);
    if ( !defined($ysa_id) ) {
        return undef;
    }

    if ( !defined($ysa_id2allars_id{$ysa_id}) ) {
        print STDERR "BIB-$id\tTerm '$sf_data' no ysa->allars mapping! Skip...\n";
    }
    my $allars_id = $ysa_id2allars_id{$ysa_id};

    if ( $allars_id =~ /\t/ ) {
        print STDERR "Term '$sf_data' maps to many ids in Allärs! Skip...\n";
        return undef;
    }

    return $allars_id;
}


sub term_is_in_slm_or_seko($) {
    my $term = shift();
    if ( defined(slm_pref_label_fi2slm_id($term)) ||
         defined(seko_pref_label2seko_id($term)) ) {
        return 1;
    }
    if ( $term =~ s/ \(.*\)$// ) {
        if ( defined(slm_pref_label_fi2slm_id($term)) ||
             defined(seko_pref_label2seko_id($term)) ) {
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

sub term_goes_to_subfield($$) {
    my ( $term, $lexicon ) = @_;


    if ( valid_location($term, $lexicon) ) {
        return 'z';
    }
    if ( valid_year($term, $lexicon) ) {
        return 'y';
    }
    my $id = &pref_label2id($term, $lexicon);
    if ( defined($id) ) { return 'x'; } # vai 'a'
    return undef;
}





sub valid_location($$) {
    my ( $loc, $lex ) = @_;
    if ( !defined($loc) ||
         # Tälle on varmaan poikkeuksia, mutta ihmetellään ne sitten joskus...
         $loc !~ /^([A-Z]|Å|Ä|Ö)/ ) {
        return 0;
    }

    if ( $lex eq 'musa' ) { $lex = 'ysa'; }
    if ( $lex eq 'cilla' ) { $lex = 'allars'; }
    
    if ( $lex eq 'fast' ) { return 0; }
    my $id = pref_label2id($loc, $lex);
    if ( $id ) {
	if ( $lex eq 'yso-paikat/fin' || $lex eq 'yso-paikat/swe' ) {
	    return 1;
	}
        if ( $lex eq 'allars' ) {
            if ( allars_id2geographical_concept($id) ) {
                return 1;
            }
        }
        elsif ( $lex eq 'ysa' ) {
            if ( ysa_id2geographical_concept($id) ) {
                return 1;
            }
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
        if ( $lex =~ /^(allars|cilla)$/ ) {
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
    my ( $content, $tag, $lex, $alt_policy ) = @_;

    if ( $tag !~ /^(650|651|655)$/ ) {
	return 0;
    }
    
    if ( !defined($lex) ) {
	# Indicator-based recognition?
	die();
    }
    my $short_lex = $lex;
    $short_lex =~ s/^yso-(aika|paikat)/yso/;
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

sub cilla_alt2pref($$) {
    my ( $id, $record ) = @_;
    return &generic_alt2pref($id, $record, 'cilla');
}

sub musa_alt2pref($$) {
    my ( $id, $record ) = @_;
    return &generic_alt2pref($id, $record, 'musa');
}

sub ysa_alt2pref($$) {
    my ( $id, $record ) = @_;
    return &generic_alt2pref($id, $record, 'ysa');
}



sub alt_label2id($$) {
    my ( $term, $lexicon ) = @_;
    if ( $lexicon eq 'allars' ) {
        return allars_alt_label2allars_id($term);
    }
    if ( $lexicon eq 'bella' ) {
        return bella_alt_label2kaunokki_id($term);
    }  
    if ( $lexicon eq 'cilla' ) {
        return cilla_alt_label2musa_id($term);
    }
    if ( $lexicon eq 'kauno/fin' ) {
        return kaunofin_alt_label2kauno_id($term);
    }
    if ( $lexicon eq 'kauno/swe' ) {
        return kaunoswe_alt_label2kauno_id($term);
    }
    if ( $lexicon eq 'kaunokki' ) {
        return kaunokki_alt_label2kaunokki_id($term);
    }
    if ( $lexicon eq 'musa' ) {
        return musa_alt_label2musa_id($term);
    }
    if ( $lexicon eq 'slm/fin' ) {
        return slmfin_alt_label2slm_id($term);
    }
    if ( $lexicon eq 'slm/swe' ) {
        return slmswe_alt_label2slm_id($term);
    }

    if ( $lexicon eq 'soto' ) {
        return sotofin_alt_label2soto_id($term);
    }

    if ( $lexicon eq 'ysa' ) {
        return ysa_alt_label2ysa_id($term);
    }
    if ( $lexicon eq 'yso/eng' ) {
        return ysoeng_alt_label2yso_id($term);
    }
    if ( $lexicon eq 'yso/fin' ) {
        return ysofin_alt_label2yso_id($term);
    }
    if ( $lexicon eq 'yso/swe' ) {
        return ysoswe_alt_label2yso_id($term);
    }

    if ( $lexicon eq 'yso-aika/fin' ) {
        return ysoaikafin_alt_label2ysoaika_id($term);
    }
    if ( $lexicon eq 'yso-aika/swe' ) {
        return ysoaikaswe_alt_label2ysoaika_id($term);
    }
    if ( $lexicon eq 'yso-aika/eng' ) {
        return ysoaikaeng_alt_label2ysoaika_id($term);
    }

    if ( $lexicon eq 'yso-paikat/fin' ) {
        return ysopaikatfin_alt_label2ysopaikat_id($term);
    }
    if ( $lexicon eq 'yso-paikat/swe' ) {
        return ysopaikatswe_alt_label2ysopaikat_id($term);
    }
    if ( $lexicon eq 'yso-paikat/eng' ) {
        return ysopaikateng_alt_label2ysopaikat_id($term);
    }
    
    if ( $lexicon eq 'fast' || $lexicon eq 'local' ) {
        return undef;
    }

    die("Unexpected lex or typo: '$lexicon'");
}


sub alt_label2unambiguous_id($$) {
    my ( $term, $lexicon ) = @_;
    my $id = alt_label2id($term, $lexicon);
    if ( defined($id) && $id =~ /\t/ ) {
        print STDERR uc($lexicon), " alt label '$term' is ambiguous: $id\n";
        return undef;
    }
    return $id;
}

sub id2pref_label($$) {
    my ( $id, $lexicon ) = @_;
    if ( $lexicon eq 'allars' ) {
        return allars_id2allars_pref_label($id);
    }
    if ( $lexicon eq 'bella' ) {
        return kaunokki_id2bella_pref_label($id);
    }
    if ( $lexicon eq 'cilla' ) {
        return musa_id2cilla_pref_label($id);
    }

    if ( $lexicon eq 'kauno/fin' ) {
        return kauno_id2kaunofin_pref_label_fi($id);
    }
    if ( $lexicon eq 'kauno/swe' ) {
        return kauno_id2kaunoswe_pref_label_sv($id);
    }
    
    if ( $lexicon eq 'kaunokki' ) {
        return kaunokki_id2kaunokki_pref_label($id);
    }
    if ( $lexicon eq 'musa' ) {
        return musa_id2musa_pref_label($id);
    }
    if ( $lexicon eq 'slm/fin' ) {
        return slm_id2slm_pref_label_fi($id);
    }

    if ( $lexicon eq 'slm/swe' ) {
        return slm_id2slm_pref_label_sv($id);
    }

    if ( $lexicon eq 'soto' ) {
        return soto_id2soto_pref_label($id);
    }
    
    if ( $lexicon eq 'ysa' ) {
        return ysa_id2ysa_pref_label($id);
    }



    if ( $lexicon eq 'yso/eng' ) {
        return yso_id2ysoeng_pref_label($id);
    }
    if ( $lexicon eq 'yso/fin' ) {
        return yso_id2ysofin_pref_label($id) ||
	    ysoaika_id2ysoaikafin_pref_label($id) ||
	    ysopaikat_id2ysopaikatfin_pref_label($id);	    
    }
    if ( $lexicon eq 'yso/swe' ) {
        return yso_id2ysoswe_pref_label($id) ||
	    ysoaika_id2ysoaikaswe_pref_label($id) ||
	    ysopaikat_id2ysopaikatswe_pref_label($id);	    
    }

    if ( $lexicon eq 'yso-aika/eng' ) {
        return ysoaika_id2ysoaikaeng_pref_label($id);
    }
    if ( $lexicon eq 'yso-aika/fin' ) {
        return ysoaika_id2ysoaikafin_pref_label($id);
    }
    if ( $lexicon eq 'yso-aika/swe' ) {
        return ysoaika_id2ysoaikaswe_pref_label($id);
    }

    if ( $lexicon eq 'yso-paikat/eng' ) {
        return ysopaikat_id2ysopaikateng_pref_label($id);
    }
    if ( $lexicon eq 'yso-paikat/fin' ) {
        return ysopaikat_id2ysopaikatfin_pref_label($id);
    }
    if ( $lexicon eq 'yso-paikat/swe' ) {
        return ysopaikat_id2ysopaikatswe_pref_label($id);
    }

    die("Unsupported lexicon '$lexicon");
}

sub id2unambiguous_pref_label($$) {
    my ( $id, $lexicon ) = @_;
    my $term = id2pref_label($id, $lexicon);
    if ( defined($term) && $term =~ /\t/ ) {
        print STDERR uc($lexicon), " id2prefLabel $id is ambiguous: '$term'\n";
        return undef;
    }
    return $term;
}



sub pref_label2id($$) {# rename as pref_lavel pref_label2ids() ?!?
    my ( $term, $lexicon ) = @_;
    if ( !defined($lexicon) ) {
        return undef;
    }
    if ( $lexicon eq 'allars' ) {
        return allars_pref_label2allars_id($term);
    }
    if ( $lexicon eq 'bella' ) {
        return bella_pref_label2kaunokki_id($term);
    }
    if ( $lexicon eq 'cilla' ) {
        return cilla_pref_label2musa_id($term);
    }
    if ( $lexicon eq 'fast' ) {
        return undef;
    }

    if ( $lexicon eq 'kauno/fin' ) {
        return kaunofin_pref_label2kauno_id($term);
    }
    
    if ( $lexicon eq 'kauno/swe' ) {
        return kaunoswe_pref_label2kauno_id($term);
    }
    
    if ( $lexicon eq 'kaunokki' ) {
        # print STDERR "KAUNOKKI..\n"; die();
        
        return kaunokki_pref_label2kaunokki_id($term);
    }
    if ( $lexicon eq 'musa' ) {
        return musa_pref_label2musa_id($term);
    }

    if ( $lexicon eq 'slm/fin' ) {
        return slm_pref_label_fi2slm_id($term);
    }

    if ( $lexicon eq 'slm/swe' ) {
        return slm_pref_label_sv2slm_id($term);
    }
    if ( $lexicon eq 'soto' ) {
        return sotofin_pref_label2soto_id($term);
    }  

    if ( $lexicon eq 'ysa' ) {
        return ysa_pref_label2ysa_id($term);
    }
    if ( $lexicon eq 'yso/eng' ) {
        return ysoeng_pref_label2yso_id($term);
    }
    if ( $lexicon eq 'yso/fin' ) {
        return ysofin_pref_label2yso_id($term);
    }
    if ( $lexicon eq 'yso/swe' ) {
        return ysoswe_pref_label2yso_id($term);
    }

    if ( $lexicon eq 'yso-aika/eng' ) {
        return ysoaikaeng_pref_label2ysoaika_id($term);
    }
    if ( $lexicon eq 'yso-aika/fin' ) {
        return ysoaikafin_pref_label2ysoaika_id($term);
    }
    if ( $lexicon eq 'yso-aika/swe' ) {
        return ysoaikaswe_pref_label2ysoaika_id($term);
    }

    if ( $lexicon eq 'yso-paikat/eng' ) {
        return ysopaikateng_pref_label2ysopaikat_id($term);
    }
    if ( $lexicon eq 'yso-paikat/fin' ) {
        return ysopaikatfin_pref_label2ysopaikat_id($term);
    }
    if ( $lexicon eq 'yso-paikat/swe' ) {
        return ysopaikatswe_pref_label2ysopaikat_id($term);
    }

    if ( $lexicon ne 'local' ) {
        print STDERR "\tpref_label2id(): lex('$term', '$lexicon') is not supported yet!\n";
    }
    return undef;
}

sub label2ids($$) {
    my ( $term, $lexicon ) = @_;
    my $ids1 = pref_label2id($term, $lexicon);
    my $ids2 = alt_label2id($term, $lexicon);
    if ( !$ids2 ) { return $ids1; }
    if ( !$ids1 ) { return $ids2; }
    my @idarr = split(/ +/, $ids1.' '.$ids2);
    my @unique = do { my %seen; grep { !$seen{$_}++ } @idarr };
    return join(' ', @unique);
}

sub label2unambiguous_id($$) {
    my ( $term, $lexicon ) = @_;
    my $ids = label2ids($term, $lexicon);
    if ( defined($ids) && index($ids, ' ') == -1 ) {
	return $ids;
    }
    return undef;
}

sub pref_label2unambiguous_id($$) {
    my ( $term, $lexicon ) = @_;
    my $id = pref_label2id($term, $lexicon);
    if ( defined($id) && $id =~ /\t/ ) {
        print STDERR uc($lexicon), " prefLabel '$term' is ambiguous: $id\n";
        return undef;
    }
    return $id;
}




sub process_keyword($$$) {
    my ( $keyword, $lex, $lang ) = @_;
    $keyword =~ s/^(.+) \(\d+\)$/$1/; # poista jäsenmäärä lopusta

    # keyword encoded/decoded fixes


    if ( defined($keyword_cache{"$keyword\t$lex"}) ) {
        return $keyword_cache{"$keyword\t$lex"};
    }

    my $orig_lex = $lex;

    if ( $lex eq 'cilla' || $lex eq 'allars' ) {
        $lang = 'sv';
    }

    if ( $lex eq 'cilla' ) {
        $lex = 'musa';
    }

    my $dkeyword = $keyword;
    # lexicons use compound versions of various chars
    $dkeyword =~ s/á/á/g;
    $dkeyword =~ s/ā/ā/g;
    $dkeyword =~ s/é/é/g;
    $dkeyword =~ s/ė/ė/g;
    $dkeyword =~ s/ī/ī/g;
    $dkeyword =~ s/õ/õ/g;
    $dkeyword =~ s/š/š/g;
    $dkeyword =~ s/ū/ū/g;
    $dkeyword =~ s/\&/\%26/g;
    $dkeyword =~ s/ /\%20/g;

    
    my $url = "http://api.finto.fi/rest/v1/search?vocab=$lex&query=$dkeyword&lang=$lang";

    my $search = get($url);
    my $result = 0;
    if ( !defined($search) ) {
        print STDERR "URL $url failed! KEYWORD: '$keyword'\n";
    } else {
        $result = ( $search =~ /,"results":\[\]/ ? 0 : 1 );
    }
    print STDERR "FINTO\t$orig_lex\t$keyword\t$result\n";
    $keyword_cache{"$keyword\t$orig_lex"} = $result;
    return $result;
}

sub listaa_ladatut_ohjaustermit() {
    foreach my $term ( sort keys %allars_alt_label2allars_id ) {
        if ( $term =~ / \-\- / ) {
            print STDERR "ALLÄRS\tOHJAUSTERMI\t$term\n";
        }
    }

    foreach my $term ( sort keys %musa_alt_label2musa_id ) {
        if ( $term =~ / \-\- / ) {
            print STDERR "MUSA\tOHJAUSTERMI\t$term\n";
        }
    }
    foreach my $term ( sort keys %cilla_alt_label2musa_id ) {
        if ( $term =~ / \-\- / ) {
            print STDERR "CILLA\tOHJAUSTERMI\t$term\n";
        }
    }
    foreach my $term ( sort keys %ysa_alt_label2ysa_id ) {
        if ( $term =~ / \-\- / ) {
            print STDERR "YSA\tOHJAUSTERMI\t$term\n";
        }
    }
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

sub local_lc($) {
    my $word = shift();
    # meidän perlin versio ei välttämättä klaaraa utf-8-merkkejä:
    $word = lc($word);
    $word =~ s/Å/å/g;
    $word =~ s/Ä/ä/g;
    $word =~ s/Ö/ö/g;
    return $word;
}

sub term_get_cands($); # proto needed because of recursion
sub term_get_cands($) {
    my $word = shift();
    my $original_word = $word;
    if ( $word =~ s/( *[,:;])$// ) {
        print STDERR "Normalize '$word$1' => '$word'\n";
        return term_get_cands($word);
    }

    my @cands = ();
    $cands[0] = $word;

    if ( $word =~ /^(.*) -- (.*)$/ ) {
        $cands[$#cands+1] = "$1 ($2)";
    }

    # Fix corrupted characters
    if ( $word =~ /��/ ) {
        my $tmp = $word;
        $tmp =~ s/��/ä/;
        $cands[$#cands+1] = $tmp;

        $tmp = $word;
        $tmp =~ s/��/ö/;
        $cands[$#cands+1] = $tmp;

        $tmp = $word;
        $tmp =~ s/��/å/;
        $cands[$#cands+1] = $tmp;
    }


    # kokonaan pienellä kirjoitettu versio:
    my $lowercased_word = local_lc($word);
    if ( $lowercased_word ne $word ) {
        $cands[$#cands+1] = $lowercased_word;
    }

    my $word2 = $word;
    if ( $word2 =~ s/hstori/histori/ || # poimi ja aja
         $word2 =~ s/filsof/filosof/ || # poimi ja aja
         # Jostain syystä meillä on mystinen "lopussa roskakirjain"-bugi.
         # Tää oli kerta-ajo, jota ei kannattane jättää päälle...
         # ( $word2 !~ /hepatiitti/ && $word2 =~ s/ [^0-9A-Z]$// ) ||
         $word2 =~ s/aaa/aa/ ||
         $word2 =~ s/ailjat$/ailijat/ || # kirjailijat
         $word2 =~ s/^cd\-/CD-/ || # CD-levyt
         $word2 =~ s/eee/ee/ ||
         $word2 =~ s/iii/ii/ ||
         $word2 =~ s/kieil$/kieli/ ||
         $word2 =~ s/kkk/kk/ ||
         $word2 =~ s/lll/ll/ ||
         $word2 =~ s/mien$/minen/ ||
         $word2 =~ s/mmm/mm/ ||
         $word2 =~ s/nkieli$/n kieli/ ||
         $word2 =~ s/nnn/nn/ ||
         $word2 =~ s/ooo/oo/ ||
         $word2 =~ s/ppp/pp/ ||
         $word2 =~ s/rrr/rr/ ||
         $word2 =~ s/sss/ss/ ||
         $word2 =~ s/teide$/tiede/ ||
         $word2 =~ s/ttt/tt/ ||
         $word2 =~ s/tukimus$/tutkimus/ ||
         $word2 =~ s/uuu/uu/ ||
         $word2 =~ s/^www/WWW/ ||
         $word2 =~ s/yyy/yy/ ||
         $word2 =~ s/äää/ää/ ||
         $word2 =~ s/ööö/öö/ ) {
        my @more_cands = term_get_cands($word2);
        print STDERR "TRY $word2 for '$word'\n";
        push(@cands, @more_cands);
    }

    # eka kirjain isolla:
    my $pronoun = &uppercase_first($lowercased_word);
    # Äh, väärinkirjoitetut kielet muuttuisivat valtioksi
    # Eli 'suomi' => 'Suomi'... Siksi alkuperäisen ekan kirjaimen tarkistus...
    if ( $original_word =~ /^([A-Z]|Å|Ä|Ö)/ && $pronoun ne $word ) {
        $cands[$#cands+1] = $pronoun;
    }
    
    if ( $pronoun =~ /-/ ) { # Iso-Britannia
        $pronoun =~ s/\-([a-z])/-\u$1/g;
        $pronoun =~ s/\-å/-Å/g;
        $pronoun =~ s/\-ä/-Ä/g;
        $pronoun =~ s/\-ö/-Ö/g;
        $cands[$#cands+1] = $pronoun;
    }
    
    # jokainen sana alkaa isolla:
    if ( $word =~ / / ) {
        my $pronoun2 = &uppercase_initials($pronoun);
        if ( $pronoun2 ne $word ) {
            $cands[$#cands+1] = $pronoun;
        }
    }
    # Todo: Iso-Britannia...
    
    if ( $word =~ s/\.$// ) {
        my @cands2 = term_get_cands($word);
        push(@cands, @cands2);
    }
    return @cands;
}

# Siivoa loppupisteet, normalisoi kirjainkoot...
sub term_get_valid_form($$); # proto due to recursion
sub term_get_valid_form($$) {
    die(); # TODO: remove func
    my ( $keyword, $lex ) = @_;

    my @cand_lex;

    if ( defined($lex) && $lex eq 'local' && $keyword =~ s/( kirjallisuus| litteratur)\.$/$1/ ) {
        return $keyword;
    }
    # Legacy rules:
    if ( $keyword =~ /^(Kiiruna|Soul|Varkaus)$/ && $lex =~ /^(ysa|musa)$/ ) {
        return undef; # älä koske näihin
    }    
    
    if ( defined($lex) ) {
        $cand_lex[$#cand_lex+1] = $lex;
    }
    else {
        #$cand_lex[$#cand_lex+1] = 'ysa';
        #$cand_lex[$#cand_lex+1] = 'allars';
        $cand_lex[$#cand_lex+1] = 'yso/fin';
        $cand_lex[$#cand_lex+1] = 'yso/swe';
        if ( $keyword =~ /^[A-Z][a-z]+/ ) {
            $cand_lex[$#cand_lex+1] = 'yso-paikat/fin';
            $cand_lex[$#cand_lex+1] = 'yso-paikat/swe';
        }
        return undef;
    }
    
    # print STDERR "term_get_valid_form($keyword, $lex)\n";
    
    my @cands = term_get_cands($keyword); # get alternative spellings
    
    if ( $lex eq 'bella' ) { $cand_lex[$#cand_lex+1] = 'kaunokki'; }

    for ( my $j=0; $j <= $#cand_lex; $j++ ) {
        my $curr_lex = $cand_lex[$j];
        for ( my $i=0; $i <= $#cands; $i++ ) {
            my $curr_cand = $cands[$i];
            my $suffix = ( $curr_lex eq $lex ? '' : "( $lex => $curr_lex )" );
            # print STDERR "term_get_valid_form($keyword, $lex) try $curr_cand\n";
            if ( defined(pref_label2id($curr_cand, $curr_lex)) ) {
                if ( $curr_cand ne $keyword ) {
                    print STDERR "PREF FOUND $curr_cand $suffix\n";
                }
                if ( $keyword ne $curr_cand ) {
                    print STDERR "term_get_valid_form($keyword, $lex) ALT HIT $curr_cand\n";
                }
                return $curr_cand;
            }
            
            # 2018-02-21: support alt label normalization as well...
            if ( defined(alt_label2id($curr_cand, $curr_lex)) &&
                 defined($lex) &&
                 $lex !~ /^yso/ ) {
                if ( $curr_cand ne $keyword ) {
                    print STDERR "ALT FOUND $curr_cand $suffix\n";
                }
                print STDERR "term_get_valid_form($keyword, $lex) ALT HIT $curr_cand\n";
                return $curr_cand;
            }
            # CILLA->ALLÄRS, MUSA->YSA
        }
        
    }
    return undef;
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


sub field_has_term($$$) {
    my ( $content, $term, $lexicon ) = @_;

    if ( $lexicon eq 'LCSH' ) {
        if ( $content !~ /^.0/ ) {
            return undef;
        }
    }
    elsif ( $content !~ /\x1F2\Q$lexicon\E/ ) {
        return undef;
    }

    if ( $content =~ /\x1F[ax]($term)($|\x1F)/ ) {
        return $1;
    }

    return undef;
}



sub has_term($$$$) {
    my ( $id, $record, $term, $lexicon ) = @_;
    my @contents = marc21_record_get_fields($record, '650', undef);

    for ( my $i=0; $i <= $#contents; $i++ ) {
        my $content = field_has_term($contents[$i], $term, $lexicon);
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

sub add_missing_term($$$$) {
    # Tää ei klaaraa FENNI<KEEP>ejä eikä juuri muuta...
    my ( $record, $tag, $term, $lexicon ) = @_;
    my @contents = marc21_record_get_fields($record, $tag, undef);

    for ( my $i=0; $i <= $#contents; $i++ ) {
        my $content = field_has_term($contents[$i], $term, $lexicon);
        if ( defined($content) ) {
            return $record;
        }
    }
    # Ei löytynyt: lisätään:
    my $new_field = " 7\x1Fa".$term;
    if ( defined($lexicon) ) {
        $new_field .= "\x1F2".$lexicon;
    }
    my $id = marc21_record_get_field($record, '001', undef);
    print STDERR "$id\tAdded new $tag field '$new_field'\n";
    
    $record = marc21_record_add_field($record, $tag, $new_field);
    return $record;
}


sub helecon2yso_normalization($) {
    my $term = shift;
    # NB! Fixes only one at the time. Applied recursively.
    if ( $term =~ s/ization/isation/ ||
	 $term =~ s/^Province of // ||
	 $term =~ s/^Ä/ä/ ||
	 $term =~ s/^Ö/ö/ ||    
	 $term =~ s/^([A-Z])/\l$1/ ) {
	return $term;
    }
    return undef;
}

sub switch_lexicon_get_ids($$$);
sub switch_lexicon_get_ids($$$) {
    my ( $term, $from, $to ) = @_;

    my $new_ids = pref_label2id($term, $to) || 0;
    print STDERR "SLGI: '$term' ", ( $new_ids ? $new_ids : '' ), "\n";
    if ( $new_ids ) { return $new_ids; }

    # Helecon 
    if ( $from eq 'helecon' ) {
	$new_ids = alt_label2unambiguous_id($term, $to) || 0;
	if ( $new_ids && !label2ids($term, 'yso/eng') ) {
	    #die("$term  -  $new_ids");
	    return $new_ids;
	}

	if ( $to eq 'yso/fin' ) {
	    # Try plural/singular
	    my $alt_term = $term.'t';
	    # sananen => sanaset, yritykset->yritys, 
	    $alt_term =~ s/nent$/set/ ||
		$alt_term =~ s/ksett$/s/ ||
		$alt_term =~ s/nent$/set/ || # oppiminen->oppimiset
		$alt_term =~ s/eett$/e/ || # veneet -> vene
		$alt_term =~ s/ett$/i/ || # huolet->huoli
		$alt_term =~ s/suudett$/suus/ ||  # liikesalaisuudet -> salaisuus
		$alt_term =~ s/tuksett$/tus/ || # kuljetukset->kuljetus
		$alt_term =~ s/tt$//; # talot -> talo

	    
	    $new_ids = label2unambiguous_id($alt_term, $to) || 0;
	    if ( $new_ids && !label2ids($alt_term, 'yso/eng') ) {
		return $new_ids;
	    }
	}

	if ( $to eq 'yso/eng' ) {
	    $new_ids = alt_label2unambiguous_id($term, $to) || 0;
	    
	    if ( $new_ids && !label2ids($term, 'yso/fin') ) {
		return $new_ids;
	    }
	    # Try plural
	    my $alt_term = $term.'s';
	    $alt_term =~ s/ys$/ies/ || $alt_term =~ s/ss$/ses/;
	    
	    $new_ids = label2unambiguous_id($alt_term, $to) || 0;
	    if ( $new_ids && !label2ids($alt_term, 'yso/fin') ) {
		return $new_ids;
	    }
	    # Try singular:
	    if ( $term =~ /[^sy]s$/ ) {
		my $alt_term = $term;
		$term =~ s/ies/y/ || $term =~ s/s$//;
		$new_ids = label2unambiguous_id($alt_term, $to) || 0;
		if ( $new_ids && !label2ids($alt_term, 'yso/fin') ) {
		    return $new_ids;
		}
	    }
	}


	
	if ( $to !~ /^yso-paikat/ ) {
	    # Try with a normalized helecon term:
	    my $alt_term = helecon2yso_normalization($term);
	    if ( $alt_term ) {
		$new_ids = switch_lexicon_get_ids($alt_term, $from, $to) || 0;
		
		print STDERR "ALT SLGI: '$alt_term' $from => $to?", ( $new_ids ? $new_ids : '' ), "\n"; # die();
		if ( $new_ids ) {
		    return $new_ids;
		}		
	    }
	}
    }
    
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

    if ( $to =~ /^(allars|soto|slm\/fin|slm\/swe|yso\/fin|yso\/swe|yso\/eng|yso-aika\/fin|yso-aika\/swe|ysoyso-paikat\/fin|yso-paikat\/swe|yso-paikat\/eng)$/ ) {
	if ( $content =~ /^.7\x1Fa([^\x1F]+)\x1F2\Q$from\E(\x1F[059][^\x1F]+)*$/ ) {
	    my $term = $1;
	    my $new_id = switch_lexicon_get_unambiguous_id($term, $from, $to);
	    print STDERR "SL: '$term' $from => $to?\n";
	    if ( !$new_id ) {
		return $content;
	    }
	    # Hack. We really don't want to make yso/eng terms:
	    if ( $from eq 'helecon' || $from eq 'pha' ) {
		if ( $to eq 'yso/eng' ) {
		    $to = 'yso/fin';
		}
		if ( $to eq 'yso-paikat/eng' ) {
		    $to = 'yso-paikat/fin';
		    $tag = '651'; # just to make lex_add_sf0() work...
		}
	    }
	    
	    my $new_term = id2unambiguous_pref_label($new_id, $to);
	    
	    if ( defined($new_term) ) {
		$content =~ s/\x1Fa[^\x1F]+/\x1Fa$new_term/;
		$to =~ s/^yso-(aika|paikat)/yso/;
		$content =~ s/\x1F2[^\x1F]+/\x1F2$to/;
		
		$content =~ s/\x1F0[^\x1F]+//; # remove $0 (should replace this though)
		$content = lex_add_sf0($content, $tag);

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


    # Lisää $0 (TODO: tehdäänkö kaunokki ja bella? Kaunokki oli välissä päällä...)
    if ( $tag =~ /^(257|370|388|648|65[015])$/ &&
	 $content =~ /^..(?:\x1F8[^\x1F]+)*\x1Fa([^\x1F]+)\x1F2(slm\/fin|slm\/swe|yso\/fin|yso\/swe)(\x1F9[A-Z]+<(DROP|KEEP)>)*$/ ) { # TODO: support $5 and $9, entäs alku-$8:t?
	print STDERR "lex_add_sf0('$content', $tag)\n";
        my $cand_term = $1;
        my $cand_lex = $2;
        my $cand_id;

	my $tmp_lex = $cand_lex;
        if ( $tag eq '257' ||$tag eq '370' || $tag eq '651' ) { # 651: yso -> yso-paikat
            $tmp_lex =~ s/^yso\//yso-paikat\//;
	}
	elsif ( $tag eq '388' || $tag eq '648' ) {
	    $tmp_lex =~ s/^yso\//yso-aika\//;
	}
	$cand_id = pref_label2unambiguous_id($cand_term, $tmp_lex);
	if ( !defined($cand_id) && $cand_term =~ s/(.)\.$/$1/ ) {
	    $cand_id = pref_label2unambiguous_id($cand_term, $tmp_lex);
	    if ( $cand_id ) {
		$content =~ s/\x1Fa[^\x1F]+/\x1Fa$cand_term/;
	    }
	}
	
        if ( defined($cand_id) ) {

            if ( 0 || $cand_lex eq 'kaunokki' ) { # miksi halusin tukea kaunokkia?
                $content =~ s/(\x1F2[^\x1F]+)/$1\x1F0http:\/\/urn.fi\/URN:NBN:fi:au:kaunokki:$cand_id/; 
            }
            elsif ( $cand_lex eq 'slm/fin' || $cand_lex eq 'slm/swe' ) {
                $content =~ s/(\x1F2[^\x1F]+)/$1\x1F0http:\/\/urn.fi\/URN:NBN:fi:au:slm:$cand_id/; 
            }
            elsif ( $cand_lex eq 'yso/fin' || $cand_lex eq 'yso/swe' ) {
                $content =~ s/(\x1F2[^\x1F]+)/$1\x1F0http:\/\/www.yso.fi\/onto\/yso\/$cand_id/;
            }
            else {
                die();
            }
        }
	else {
	    print STDERR "WARNING: lex_add_sf0: no id found for $tag '$content'\n";
	}
    }
    # Periaatteessa varmaan replikointisuojaukset olis kivoja fenni- ja
    # violakeepeille, mutta tämä kun on oma fiksi, niin en ole vielä
    # implementoinut...

    return $content;
}      



sub sf2_lex_add_missing_language_suffix($) {
    my ( $content ) = @_;
    my $baselex = get_lex($content);
    if ( !defined($baselex) || $baselex !~ /^(kauno|slm|yso)$/ ) {
	return $content;
    }
    print STDERR "CHECKING '$content' vs $baselex\n";

    # Allow $a $x* $2 $0? $9?
    if ( $content =~ /^..\x1Fa[^\x1F]+(\x1F[x][^\x1F]+)*\x1F2[^\x1F]+(\x1F0[^\x1F]+)?(\x1F+[^\x1F]+)?$/ ) {
	my @arr = split(/\x1F/, $content);
	my @langlist = ( 'fin', 'swe' );
	for ( my $j=0; $j <= $#langlist; $j++ ) {
	    my $new_lex = $baselex ."/" .$langlist[$j];
	    my $ok = 1;
	    for ( my $i=1; $i <= $#arr && $ok; $i++ ) {
		$ok = 0;
		if ( $arr[$i] =~ /^(.)(.+)$/ ) {
		    my $sf_code = $1;
		    my $sf_value = $2;
		    if ( $sf_code =~ /^[0259]$/ ) {
			$ok = 1;
		    }
		    # sf_code 'x' should be dropped for slm and yso...
		    elsif ( $sf_code eq 'a' || $sf_code eq 'x' ) {
			# There was an error here. I just wonder...
			if ( defined(label2ids($sf_value, $new_lex)) ) {
			    $ok = 1;
			}
		    }
		    # Support yso-paikat:
		    if ( !$ok && $sf_code eq 'a' && $baselex eq 'yso' ) {
			my $new_lex = $baselex .'-paikat/' .$langlist[$j];
			if ( defined(label2ids($sf_value, $new_lex)) ) {
			    $ok = 1;
			}
			if ( !$ok ) {
			    $new_lex = $baselex .'-aika/' .$langlist[$j];
			    if ( defined(label2ids($sf_value, $new_lex)) ) {
				$ok = 1;
			    }
			}
		    }
		    
		}
	    }
	    if ( $ok ) {
		print STDERR "FIX CONTENT '$content', NEW: \$2 $new_lex\n";
		$content =~ s/\x1F2[^\x1F]+/\x1F2$new_lex/;
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
    return undef;
}


sub map_sf0_to_lex($) {
    # Argument can be either whole field or subfield 0's value
    my $sf = shift();
    if ( $sf =~ /\x1F0([^\x1F]+)/ ) { # map field to subfield
        $sf = $1;
    }
    if ( $sf =~ /^https?:\/\/urn\.fi\/URN:NBN:fi:au:kaunokki:\d+$/ ) {
        return 'kaunokki';
    }
    # TODO: slm
    if ( $sf =~ /^https?:\/\/www\.yso\.fi\/onto\/yso\/p\d+$/ ) {
        return 'yso';
    }

    if ( $sf =~ /^https?:\/\/urn.fi\/URN:NBN:fi:au:slm:s\d+$/ ) {
        return 'slm';
    }
    return undef;
}



sub sfa_and_sf2_match($) {
    my $content = shift();
    my $sf2 = get_lex($content);
    if ( defined($sf2) && $sf2 =~ /^(kaunokki|slm\/fin|slm\/swe|yso\/fin|yso\/swe)$/ ) {
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
    my $id = sfa_and_sf2_match($content);
    if ( !defined($id) || $id eq "0" || $id =~ /\t/ ) { return undef; }

    if ( $content =~ /\x1F2kaunokki($|\x1F)/ ) {
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



my %ttka_mappings;
$ttka_mappings{'roomalaiskatolinen teologia'} = [ "610	24\x1FaKatolinen kirkko.\x1F0(FIN11)000213215",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Vanha testamentti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti." ];
$ttka_mappings{'Luther-tutkimus'} = [ "600	14\x1FaLuther, Martti,d1483-1546.\x1F0(FIN11)000051426" ];
$ttka_mappings{'luterilainen teologia'} = [ "650	 7\x1Faluterilaiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11818",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'protestanttinen teologia'} = [ "650	 7\x1Faprotestanttiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6842",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Uusi testamentti'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti." ];
$ttka_mappings{'kirkko ja yhteiskunta'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Fakirkkososiologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16169",  "650	 7\x1Fayhteiskunta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9778" ];
$ttka_mappings{'Paavalin teologia'} = [ "600	04\x1FaPaavali,\x1Fcapostoli.\x1F0(FIN11)000106353",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'uskonnonopetus'} = [ "650	 7\x1Faopetus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2630",  "650	 7\x1Fauskonto ja uskonnot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2921" ];
$ttka_mappings{'Jeesus-tutkimus'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186" ];
$ttka_mappings{'Jeesus'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186" ];
$ttka_mappings{'kirkko ja valtio'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Favaltio (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2538" ];
$ttka_mappings{'kirkon ykseys'} = [ "650	 7\x1Faekumenia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13701",  "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938" ];
$ttka_mappings{'kirkon oppi'} = [ "650	 7\x1Fadogmatiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12684" ];
$ttka_mappings{'teologian historia'} = [ "650	 7\x1Faoppihistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16329",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Vanhan testamentin teologia'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'oppikeskustelut'} = [ "650	 7\x1Faekumeniikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p15154" ];
$ttka_mappings{'ortodoksinen teologia'} = [ "610	24\x1FaOrtodoksinen kirkko.\x1F0(FIN11)000214916",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Uuden testamentin teologia'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Vanhan testamentin ajanhistoria'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'usko ja tieto'} = [ "650	 7\x1Fakritisismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11679",  "650	 7\x1Fauskonnonfilosofia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6225" ];
$ttka_mappings{'Uuden testamentin ajanhistoria'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'raamattuteologia'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Raamattu'} = [ "630	04\x1FaRaamattu." ];
$ttka_mappings{'synoptiset evankeliumit'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan.",  "650	 7\x1Faevankeliumit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12379" ];
$ttka_mappings{'rabbiininen kirjallisuus'} = [ "650	 7\x1Farabbiininen kirjallisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p38562" ];
$ttka_mappings{'Raamatun arkeologia'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faarkeologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1265" ];
$ttka_mappings{'deuteronomistinen historiateos'} = [ "630	04\x1FaRaamattu.\x1FpHistorialliset kirjat." ];
$ttka_mappings{'Logia-lähde'} = [ "650	 7\x1FaQ-teoria\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9641" ];
$ttka_mappings{'viisauskirjallisuus'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Faapokryfit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7204",  "650	 7\x1Fajuutalainen kirjallisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p23523",  "650	 7\x1Faviisaus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11362" ];
$ttka_mappings{'ilmoitus'} = [ "650	 7\x1Failmoitus (teologia)\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9766" ];
$ttka_mappings{'Paavali'} = [ "600	04\x1FaPaavali,\x1Fcapostoli.\x1F0(FIN11)000106353" ];
$ttka_mappings{'Jeesuksen kärsimyshistoria'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fakärsimys\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4620" ];
$ttka_mappings{'teologian opiskelu'} = [ "650	 7\x1Faopiskelu\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4781",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'bilateraaliset keskustelut'} = [ "650	 7\x1Faekumenia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13701",  "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "650	 7\x1Fakokoukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7500" ];
$ttka_mappings{'Septuaginta'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti,\x1Flkreikka.\x1FsSeptuaginta." ];
$ttka_mappings{'nuoret kirkot'} = [ "650	 7\x1Fakehitysmaat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17004",  "650	 7\x1Fakirkkohistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19610",  "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "650	 7\x1Falähetystyö\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11784" ];
$ttka_mappings{'Jeesuksen opetus'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Favaikutushistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21324" ];
$ttka_mappings{'Uuden testamentin teksti'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fatekstikritiikki\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17140" ];
$ttka_mappings{'Raamatun auktoriteetti'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600",  "650	 7\x1Fapyhät kirjat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11248" ];
$ttka_mappings{'dialektinen teologia'} = [ "650	 7\x1Fadialektinen teologia\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9640" ];
$ttka_mappings{'Jeesuksen ylösnousemus'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Faylösnousemus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p630" ];
$ttka_mappings{'Vanhan testamentin teksti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Fatekstikritiikki\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17140" ];
$ttka_mappings{'lähetyshistoria'} = [ "650	 7\x1Fakirkkohistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19610",  "650	 7\x1Falähetystyö\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11784" ];
$ttka_mappings{'anglikaaninen teologia'} = [ "650	 7\x1Faanglikaaninen kirkko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8767",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'orientaaliset kirkot'} = [ "650	 7\x1Faorientaaliortodoksiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p39258" ];
$ttka_mappings{'Raamatun kääntäminen'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Fakääntäminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9586",  "650	 7\x1Faraamatunkäännökset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20549" ];
$ttka_mappings{'teologia ja tiede'} = [ "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830",  "650	 7\x1Fatiede\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2240",  "650	 7\x1Fauskonnonfilosofia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6225" ];
$ttka_mappings{'Jeesuksen elämä'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fahenkilöhistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2718" ];
$ttka_mappings{'fundamentaaliteologia'} = [ "650	 7\x1Fafundamentaaliteologia\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9764" ];
$ttka_mappings{'narratiivinen kritiikki'} = [ "650	 7\x1Fanarratiivinen kritiikki\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9765" ];
$ttka_mappings{'profeetat'} = [ "650	 7\x1Faprofeetat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19564" ];
$ttka_mappings{'Jeesuksen ihmeteot'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Faihmeet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p627",  "650	 7\x1Fatoiminta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8090" ];
$ttka_mappings{'Vatikaanin kirkolliskokoukset'} = [ "610	24\x1FaKatolinen kirkko.\x1FbKirkolliskokous.\x1F0(FIN11)000031111",  "650	 7\x1Fakirkolliskokoukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17463" ];
$ttka_mappings{'koptilaisuus'} = [ "650	 7\x1Fakoptilainen kirkko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p937" ];
$ttka_mappings{'liitto'} = [ "650	 7\x1Faliitto (teologia)\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9768" ];
$ttka_mappings{'idän skismaattiset kirkot'} = [ "650	 7\x1Faorientaaliortodoksiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p39258" ];
$ttka_mappings{'Jeesuksen vertaukset'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Faopetus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2630",  "650	 7\x1Fatoiminta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8090",  "650	 7\x1Favertaukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5556" ];
$ttka_mappings{'redaktiokritiikki'} = [ "650	 7\x1Faredaktiokritiikki\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9645" ];
$ttka_mappings{'pakkosiirtolaisuuden aika'} = [ "648	 7\x1Fa eKr.\x1F2yso/fin",  "650	 7\x1Fajuutalaiset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8494",  "650	 7\x1Faväestöhistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5344",  "650	 7\x1Faväestönsiirrot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8437",  "651	 7\x1FaEgypti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p105841" ];
$ttka_mappings{'synoptinen ongelma'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan.",  "650	 7\x1Faeksegetiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9983",  "650	 7\x1Fahypoteesit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p18809" ];
$ttka_mappings{'antijudaismi'} = [ "650	 7\x1Faantisemitismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p610" ];
$ttka_mappings{'Jeesus-kuvat'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Famielikuvat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1490" ];
$ttka_mappings{'rukoushetket'} = [ "650	 7\x1Farukoushetket\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9646" ];
$ttka_mappings{'Raamatun käyttäminen'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Fakäyttö\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1736" ];
$ttka_mappings{'pelastushistoria'} = [ "650	 7\x1Fapelastus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5255" ];
$ttka_mappings{'intertestamentaarinen tutkimus'} = [ "650	 7\x1Faeksegetiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9983",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859",  "650	 7\x1Favarhaisjuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21992" ];
$ttka_mappings{'kirkkopäivät'} = [ "610	24\x1FaKirkkopäivät." ];
$ttka_mappings{'laki ja evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumit.",  "650	 7\x1Faevankeliumi (sanoma)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12378",  "650	 7\x1Falait\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1464",  "650	 7\x1Fauskonnolliset käsitykset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p26368" ];
$ttka_mappings{'Uuden testamentin johdanto-oppi'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Faeksegetiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9983" ];
$ttka_mappings{'afrikkalainen teologia'} = [ "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830",  "651	 7\x1FaAfrikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p94080" ];
$ttka_mappings{'Jumalan tunteminen'} = [ "650	 7\x1FaJumala\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13849",  "650	 7\x1Fajumalakäsitykset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p10555" ];
$ttka_mappings{'Jeesuksen nimet'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fanimet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1638" ];
$ttka_mappings{'kristillinen nuorisoliike'} = [ "650	 7\x1Fakristillisyys\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p14270",  "650	 7\x1Fanuoret\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11617",  "650	 7\x1Fauskonnolliset liikkeet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4851" ];
$ttka_mappings{'Vanhan testamentin johdanto-oppi'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Faeksegetiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9983" ];
$ttka_mappings{'kirkon tilastot'} = [ "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "655	 7\x1Fatilastot\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s276" ];
$ttka_mappings{'apostolisuus'} = [ "650	 7\x1Faapostolisuus\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9769" ];
$ttka_mappings{'piispuus'} = [ "650	 7\x1Fapiispuus\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/5694" ];
$ttka_mappings{'rabbiininen juutalaisuus'} = [ "650	 7\x1Fajuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p727" ];
$ttka_mappings{'apokryfit'} = [ "650	 7\x1Faapokryfit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7204" ];
$ttka_mappings{'erehtymättömyys'} = [ "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600",  "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Favalta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2551" ];
$ttka_mappings{'kuninkuus'} = [ "650	 7\x1Fakuninkaat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9664" ];
$ttka_mappings{'raamattukäsitykset'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faraamatuntulkinta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9984" ];
$ttka_mappings{'kirkon virka'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Fakirkon työntekijät\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2488" ];
$ttka_mappings{'Jumalan sana'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600",  "650	 7\x1FaJumala\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13849" ];
$ttka_mappings{'Qumranin veljeskunta'} = [ "650	 7\x1FaQumranin liike\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9674" ];
$ttka_mappings{'suomalainen teologia'} = [ "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830",  "651	 7\x1FaSuomi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p94426" ];
$ttka_mappings{'kirkkojärjestykset'} = [ "650	 7\x1Fakirkkolait\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p15944" ];
$ttka_mappings{'kirkollinen tiedotus'} = [ "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "650	 7\x1Faviestintä\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p36" ];
$ttka_mappings{'reformoitu teologia'} = [ "650	 7\x1Fareformoidut kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20252",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'musta teologia'} = [ "650	 7\x1Famusta teologia\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9670" ];
$ttka_mappings{'traditiohistoria'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Fasyntyhistoria (teokset)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p37836",  "650	 7\x1Fatekstikritiikki\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17140" ];
$ttka_mappings{'kaksiluonto-oppi'} = [ "650	 7\x1Fakaksiluonto-oppi\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9761" ];
$ttka_mappings{'kirkon lapsityö'} = [ "650	 7\x1Fakirkon lapsityö\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9676" ];
$ttka_mappings{'ideologiakritiikki'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faideologiat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p216",  "650	 7\x1Fakritiikki\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1067" ];
$ttka_mappings{'Jeesuksen syntyminen'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fasyntymä\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13026" ];
$ttka_mappings{'kirkon talous'} = [ "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "650	 7\x1Fatalous\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2555" ];
$ttka_mappings{'kirkkounionit'} = [ "650	 7\x1Faekumenia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13701" ];
$ttka_mappings{'Leuenbergin konkordia'} = [ "630	04\x1FaLeuenberger Konkordie.",  "650	 7\x1Faprotestanttiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6842",  "650	 7\x1Fasopimukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3356" ];
$ttka_mappings{'parusia'} = [ "650	 7\x1Faapokalyptiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17206",  "650	 7\x1Faeskatologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3913",  "650	 7\x1Fakristinusko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4668" ];
$ttka_mappings{'seurakuntasuunnittelu'} = [ "650	 7\x1Faseurakunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3029",  "650	 7\x1Fasuunnittelu\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1377" ];
$ttka_mappings{'Jumalan olemassaolo'} = [ "650	 7\x1Fajumalatodistukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1013" ];
$ttka_mappings{'juutalainen teologia'} = [ "650	 7\x1Fajuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p727",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'usko ja teot'} = [ "650	 7\x1Fausko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1726" ];
$ttka_mappings{'radikaalireformaatio'} = [ "650	 7\x1Fareformaatio\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13129" ];
$ttka_mappings{'teologia ja kirkko'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'diakonian virka'} = [ "650	 7\x1Fadiakonit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20497" ];
$ttka_mappings{'kanaanilaiset'} = [ "650	 7\x1Fakanaanilaiset\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9677" ];
$ttka_mappings{'skotismi'} = [ "650	 7\x1Faskotismi\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9671" ];
$ttka_mappings{'uusprotestantismi'} = [ "650	 7\x1Fauusprotestantismi\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9672" ];
$ttka_mappings{'paimenkirjeet'} = [ "650	 7\x1Fakiertokirjeet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8645",  "650	 7\x1Fapiispat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5769" ];
$ttka_mappings{'panenteismi'} = [ "650	 7\x1Fapanenteismi\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9673" ];
$ttka_mappings{'teologiset tiedekunnat'} = [ "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830",  "650	 7\x1Fatiedekunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16678",  "650	 7\x1Fayliopistot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p10895" ];
$ttka_mappings{'Uuden testamentin tekstikritiikki'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fatekstikritiikki\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17140" ];
$ttka_mappings{'apuneuvot'} = [ "630	04\x1FaRaamattu.",  "655	 7\x1Fahakuteokset\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s654" ];
$ttka_mappings{'kirkkopolitiikka'} = [ "650	 7\x1Fauskontopolitiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20383" ];
$ttka_mappings{'kultainen sääntö'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan, 7:12.",  "650	 7\x1Fakristillinen etiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9366" ];
$ttka_mappings{'regimenttioppi'} = [ "650	 7\x1Faluterilaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8758",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830",  "650	 7\x1Favallanjako\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2548" ];
$ttka_mappings{'Daavid'} = [ "600	04\x1FaDaavid,\x1FcIsraelin kuningas.\x1F0(FIN11)000104072" ];
$ttka_mappings{'Esra'} = [ "630	04\x1FaRaamattu.\x1FpEsran kirja." ];
$ttka_mappings{'kirkkoreformit'} = [ "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "650	 7\x1Fauudistukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6795" ];
$ttka_mappings{'lapsikaste'} = [ "650	 7\x1Fakaste\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3370",  "650	 7\x1Falapset (ikäryhmät)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4354" ];
$ttka_mappings{'lähteet'} = [ "650	 7\x1Falähdeaineisto\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7605" ];
$ttka_mappings{'opetusvirka'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Fakirkon työntekijät\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2488",  "650	 7\x1Faopettajuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8790" ];
$ttka_mappings{'raamattulähetys'} = [ "650	 7\x1Falähetystyö\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11784" ];
$ttka_mappings{'dogminkehitys'} = [ "650	 7\x1Fadogmihistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p25959" ];
$ttka_mappings{'Joona'} = [ "630	04\x1FaRaamattu.\x1FpJoonan kirja." ];
$ttka_mappings{'kasteopetus'} = [ "650	 7\x1Fakaste\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3370" ];
$ttka_mappings{'kirkon aikuistyö'} = [ "650	 7\x1Faaikuiset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5590",  "650	 7\x1Fakirkon kasvatustoiminta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1926" ];
$ttka_mappings{'kreikan kieli'} = [ "650	 7\x1Fakreikan kieli\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p684" ];
$ttka_mappings{'kristologiset kiistat'} = [ "650	 7\x1Fadogmihistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p25959",  "650	 7\x1Fakristologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6748",  "650	 7\x1Faoppiriidat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8611" ];
$ttka_mappings{'monofysitismi'} = [ "650	 7\x1Famiafysitismi\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9691" ];
$ttka_mappings{'montanolaisuus'} = [ "650	 7\x1Famontanolaisuus\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9685" ];
$ttka_mappings{'pseudoklementiininen kirjallisuus'} = [ "630	04\x1FaKerygmata Petrou." ];
$ttka_mappings{'radikaalipietismi'} = [ "650	 7\x1Faradikaalipietismi\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9686" ];
$ttka_mappings{'suhteet'} = [ "650	 7\x1Fasuhteet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1372" ];
$ttka_mappings{'tuonpuoleisuus'} = [ "650	 7\x1Fakuolemanjälkeinen elämä\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p629" ];
$ttka_mappings{'auktoriteetti'} = [ "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600" ];
$ttka_mappings{'filistealaiset'} = [ "650	 7\x1Fafilistealaiset\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9687" ];
$ttka_mappings{'leeviläiset'} = [ "650	 7\x1Faleeviläiset\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9688" ];
$ttka_mappings{'muotohistoria'} = [ "650	 7\x1Famuotohistoria\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9689" ];
$ttka_mappings{'Pappiskirja'} = [ "630	04\x1FaPappiskirja." ];
$ttka_mappings{'vähemmistökirkot'} = [ "650	 7\x1Fadiaspora\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8486",  "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938" ];
$ttka_mappings{'ylipapit'} = [ "650	 7\x1Faylipapit\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9690" ];
$ttka_mappings{'eriuskolaiset'} = [ "650	 7\x1Fauskonnolliset vähemmistöt\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11266" ];
$ttka_mappings{'hetkipalvelukset'} = [ "650	 7\x1Fajumalanpalvelus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p15215" ];
$ttka_mappings{'Jeesuksen kuolema'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fakuolema\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p626" ];
$ttka_mappings{'luterilainen etiikka'} = [ "650	 7\x1Fakristillinen etiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9366",  "650	 7\x1Faluterilaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8758" ];
$ttka_mappings{'makkabilaiset'} = [ "650	 7\x1Famakkabilaiset\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9684" ];
$ttka_mappings{'metodistikirkot'} = [ "650	 7\x1Fametodismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p14597" ];
$ttka_mappings{'toisen temppelin aika'} = [ "650	 7\x1Favarhaisjuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21992" ];
$ttka_mappings{'tuomio'} = [ "650	 7\x1Faviimeinen tuomio\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/550" ];
$ttka_mappings{'ebionit'} = [ "650	 7\x1Faebionilaiset\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9692" ];
$ttka_mappings{'eksistentiaalinen interpretaatio'} = [ "650	 7\x1Fakristillinen eksistentialismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p23508",  "650	 7\x1Faraamatuntulkinta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9984" ];
$ttka_mappings{'kristillinen päihdehuolto'} = [ "650	 7\x1Fakaritatiivinen työ\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p29019",  "650	 7\x1Fapäihdehuolto\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5720" ];
$ttka_mappings{'maallikkoliikkeet'} = [ "650	 7\x1Fakristinusko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4668",  "650	 7\x1Famaallikot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8003",  "650	 7\x1Fauskonnolliset liikkeet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4851" ];
$ttka_mappings{'Misna'} = [ "630	04\x1FaMišna." ];
$ttka_mappings{'papinvaalit'} = [ "650	 7\x1Fakirkolliset vaalit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p14220",  "650	 7\x1Fapapit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5468" ];
$ttka_mappings{'suksessio'} = [ "650	 7\x1Faapostolinen suksessio\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9683" ];
$ttka_mappings{'uhrit'} = [ "650	 7\x1Fauhraaminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p10265" ];
$ttka_mappings{'Uuden testamentin etiikka'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fakristillinen etiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9366" ];
$ttka_mappings{'augustinolaiset'} = [ "650	 7\x1Faaugustinolaiset\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9729" ];
$ttka_mappings{'baptistikirkot'} = [ "650	 7\x1Fabaptismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5042" ];
$ttka_mappings{'Ben Sira'} = [ "630	04\x1FaRaamattu.\x1FpSirakin kirja." ];
$ttka_mappings{'Englannin kirkko'} = [ "650	 7\x1Faanglikaaninen kirkko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8767" ];
$ttka_mappings{'evankelinen kirkko'} = [ "650	 7\x1Faprotestanttiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6842" ];
$ttka_mappings{'evankeliumiharmoniat'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan." ];
$ttka_mappings{'Ihmisen poika'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fakristologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6748" ];
$ttka_mappings{'Jeesuksen taivaaseenastuminen'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fataivaaseenastuminen\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9730" ];
$ttka_mappings{'Jumalan poika'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Fakristologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6748" ];
$ttka_mappings{'jumalanpalveluselämä'} = [ "650	 7\x1Fajumalanpalvelus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p15215" ];
$ttka_mappings{'kirjanoppineet'} = [ "650	 7\x1Fafariseukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p26262" ];
$ttka_mappings{'kristikunta'} = [ "650	 7\x1Fakristityt\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6991" ];
$ttka_mappings{'käännökset'} = [ "650	 7\x1Fakäännökset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16349" ];
$ttka_mappings{'lapsuusevankeliumit'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186",  "650	 7\x1Faapokryfit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7204",  "650	 7\x1Falapsuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13735" ];
$ttka_mappings{'pre-eksistenssi'} = [ "650	 7\x1Faeksistenssi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p15960" ];
$ttka_mappings{'pyhät kuvat'} = [ "650	 7\x1Faikonoklasmi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4429" ];
$ttka_mappings{'Qumranin yhteisö'} = [ "650	 7\x1FaQumranin liike\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9674" ];
$ttka_mappings{'targumit'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti,\x1Flaramea." ];
$ttka_mappings{'Tobit'} = [ "630	04\x1FaRaamattu.\x1FpTobitin kirja." ];
$ttka_mappings{'vanhakatoliset kirkot'} = [ "650	 7\x1Favanhakatoliset kirkot\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9732" ];
$ttka_mappings{'afrikkalaiset kirkot'} = [ "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938",  "651	 7\x1FaAfrikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p94080" ];
$ttka_mappings{'aramean kieli'} = [ "650	 7\x1Faaramean kieli\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4264" ];
$ttka_mappings{'Barukin kirja'} = [ "630	04\x1FaRaamattu.\x1FpBarukin kirja." ];
$ttka_mappings{'epäusko'} = [ "650	 7\x1Faepäily\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1724",  "650	 7\x1Fausko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1726" ];
$ttka_mappings{'Hanna'} = [ "600	04\x1FaHanna\x1Fc(Raamatun henkilö)" ];
$ttka_mappings{'investituurakiista'} = [ "650	 7\x1Fainvestituurariita\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/1764" ];
$ttka_mappings{'Josefus'} = [ "600	14\x1FaJosephus, Flavius.\x1F0(FIN11)000097239" ];
$ttka_mappings{'Juudas Iskariot'} = [ "600	04\x1FaJuudas Iskariot.\x1F0(FIN11)000122053" ];
$ttka_mappings{'kaikkivaltius'} = [ "650	 7\x1FaJumala\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13849" ];
$ttka_mappings{'kastepuheet'} = [ "650	 7\x1Fakaste\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3370",  "650	 7\x1Fapuheet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7468" ];
$ttka_mappings{'keisarikultti'} = [ "650	 7\x1Fakeisarit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9668",  "650	 7\x1Fakultit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1016" ];
$ttka_mappings{'kuvakielto'} = [ "650	 7\x1Faikonoklasmi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4429" ];
$ttka_mappings{'maailma'} = [ "650	 7\x1Famaailma\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7319" ];
$ttka_mappings{'Mirjam'} = [ "600	04\x1FaMirjam\x1Fc(Raamatun henkilö)" ];
$ttka_mappings{'pelastusarmeija'} = [ "610	24\x1FaPelastusarmeija.\x1F0(FIN11)000017174" ];
$ttka_mappings{'protestanttinen etiikka'} = [ "650	 7\x1Faetiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3166",  "650	 7\x1Faprotestanttiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6842" ];
$ttka_mappings{'Raamatun kirjallisuuslajit'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Fagenret\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17134" ];
$ttka_mappings{'Salomon oodit'} = [ "630	04\x1FaSalomon oodit." ];
$ttka_mappings{'soteriologia'} = [ "650	 7\x1Fapelastus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5255" ];
$ttka_mappings{'tulkinnat'} = [ "650	 7\x1Faraamatuntulkinta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9984" ];
$ttka_mappings{'Uuden testamentin kaanon'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fakaanonit (valikoimat)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9577" ];
$ttka_mappings{'yleinen pappeus'} = [ "650	 7\x1Famaallikot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8003",  "650	 7\x1Fapappeus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1498" ];

$ttka_mappings{'Roomalaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpRoomalaiskirje." ];
$ttka_mappings{'Korinttilaiskirjeet'} = [ "630	04\x1FaRaamattu.\x1FpKorinttilaiskirjeet." ];
$ttka_mappings{'Johanneksen ilmestys'} = [ "630	04\x1FaRaamattu.\x1FpJohanneksen ilmestys." ];
$ttka_mappings{'Jeesus'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186" ];
$ttka_mappings{'laki'} = [ "650	 7\x1Falait\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1464" ];
$ttka_mappings{'Kirkkotaistelu'} = [ "650	 7\x1Fakirkkotaistelu\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p26341" ];
$ttka_mappings{'Jesaja'} = [ "630	04\x1FaRaamattu.\x1FpJesajan kirja." ];
$ttka_mappings{'1. Mooseksen kirja'} = [ "630	04\x1FaRaamattu.\x1FpEnsimmäinen Mooseksen kirja." ];
$ttka_mappings{'Raamatun kaanon'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Fakaanonit (valikoimat)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9577" ];
$ttka_mappings{'Sananlaskut'} = [ "630	04\x1FaRaamattu.\x1FpSananlaskujen kirja." ];
$ttka_mappings{'Pietarin kirjeet'} = [ "630	04\x1FaRaamattu.\x1FpPietarin kirjeet." ];
$ttka_mappings{'Galatalaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje galatalaisille." ];
$ttka_mappings{'Siirakin kirja'} = [ "630	04\x1FaRaamattu.\x1FpSirakin kirja." ];
$ttka_mappings{'Kuningasten kirjat'} = [ "630	04\x1FaRaamattu.\x1FpKuninkaiden kirjat." ];
$ttka_mappings{'Aikakirjat'} = [ "630	04\x1FaRaamattu.\x1FpAikakirjat." ];
$ttka_mappings{'sovitus'} = [ "650	 7\x1Fasovitus (uskonto)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5254" ];
$ttka_mappings{'Samuelin kirjat'} = [ "630	04\x1FaRaamattu.\x1FpSamuelin kirjat." ];
$ttka_mappings{'Filippiläiskirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje filippiläisille." ];
$ttka_mappings{'korinttilaiskirjeet'} = [ "630	04\x1FaRaamattu.\x1FpKorinttilaiskirjeet." ];
$ttka_mappings{'Kolossalaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje kolossalaisille." ];
$ttka_mappings{'Heprealaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje heprealaisille." ];
$ttka_mappings{'Saarnaaja'} = [ "630	04\x1FaRaamattu.\x1FpSaarnaajan kirja." ];
$ttka_mappings{'Job'} = [ "630	04\x1FaRaamattu.\x1FpJobin kirja." ];
$ttka_mappings{'Jeremia'} = [ "630	04\x1FaRaamattu.\x1FpJeremian kirja." ];
$ttka_mappings{'Hesekiel'} = [ "630	04\x1FaRaamattu.\x1FpHesekielin kirja." ];
$ttka_mappings{'Efesolaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje efesolaisille." ];
$ttka_mappings{'pienet profeetat'} = [ "630	04\x1FaRaamattu.\x1FpPienet profeetat." ];
$ttka_mappings{'Deuteronomistinen historiateos'} = [ "630	04\x1FaRaamattu.\x1FpHistorialliset kirjat." ];
$ttka_mappings{'Tuomaan evankeliumi'} = [ "630	04\x1FaTuomaan evankeliumi." ];
$ttka_mappings{'Johanneksen kirjeet'} = [ "630	04\x1FaRaamattu.\x1FpJohanneksen kirjeet." ];
$ttka_mappings{'5. Mooseksen kirja'} = [ "630	04\x1FaRaamattu.\x1FpViides Mooseksen kirja." ];
$ttka_mappings{'Tessalonikalaiskirjeet'} = [ "630	04\x1FaRaamattu.\x1FpTessalonikalaiskirjeet." ];
$ttka_mappings{'Valitusvirret'} = [ "630	04\x1FaRaamattu.\x1FpValitusvirret." ];
$ttka_mappings{'Nag Hammadi'} = [ "651	 7\x1FaNag Hammadi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p116444" ];
$ttka_mappings{'hakuteokset'} = [ "655	 7\x1Fahakuteokset\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s654" ];
$ttka_mappings{'2. Mooseksen kirja'} = [ "630	04\x1FaRaamattu.\x1FpToinen Mooseksen kirja." ];
$ttka_mappings{'Jaakobin kirje'} = [ "630	04\x1FaRaamattu.\x1FpJaakobin kirje." ];
$ttka_mappings{'Daniel'} = [ "630	04\x1FaRaamattu.\x1FpDanielin kirja." ];
$ttka_mappings{'Laulujen laulu'} = [ "630	04\x1FaRaamattu.\x1FpLaulujen laulu." ];
$ttka_mappings{'Joosua'} = [ "630	04\x1FaRaamattu.\x1FpJoosuan kirja." ];
$ttka_mappings{'luominen'} = [ "650	 7\x1Faluominen (uskonto)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9610" ];
$ttka_mappings{'vastaanotto'} = [ "650	 7\x1Fareseptio\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p24663" ];
$ttka_mappings{'Timoteuskirjeet'} = [ "630	04\x1FaRaamattu.\x1FpKirjeet Timoteukselle." ];
$ttka_mappings{'Juudan kirje'} = [ "630	04\x1FaRaamattu.\x1FpJuudaksen kirje." ];
$ttka_mappings{'Vuorisaarna'} = [ "650	 7\x1FaVuorisaarna\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p14042" ];
$ttka_mappings{'Hoosea'} = [ "630	04\x1FaRaamattu.\x1FpHoosean kirja." ];
$ttka_mappings{'pastoraalikirjeet'} = [ "630	04\x1FaRaamattu.\x1FpPastoraalikirjeet." ];
$ttka_mappings{'messias'} = [ "650	 7\x1Famessianismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20455" ];
$ttka_mappings{'tunnustus'} = [ "650	 7\x1Fauskon tunnustaminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p10531" ];
$ttka_mappings{'Miika'} = [ "630	04\x1FaRaamattu.\x1FpMiikan kirja." ];
$ttka_mappings{'kirkkokäsikirjat'} = [ "655	 7\x1Fakirkkokäsikirjat\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s741" ];
$ttka_mappings{'Filemoninkirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje Filemonille." ];
$ttka_mappings{'Aamos'} = [ "630	04\x1FaRaamattu.\x1FpAamoksen kirja." ];
$ttka_mappings{'uskonpuhdistus'} = [ "650	 7\x1Fareformaatio\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13129" ];
$ttka_mappings{'Sakarja'} = [ "630	04\x1FaRaamattu.\x1FpSakarjan kirja." ];
$ttka_mappings{'profetismi'} = [ "650	 7\x1Faprofetismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p28944" ];
$ttka_mappings{'lähdeaineisto'} = [ "650	 7\x1Falähdeaineisto\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7605" ];
$ttka_mappings{'Ester'} = [ "630	04\x1FaRaamattu.\x1FpEsterin kirja." ];
$ttka_mappings{'3. Mooseksen kirja'} = [ "630	04\x1FaRaamattu.\x1FpKolmas Mooseksen kirja." ];
$ttka_mappings{'vertaukset'} = [ "650	 7\x1Favertaukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5556" ];
$ttka_mappings{'Suomen ev.lut. kirkko'} = [ "610	24\x1FaSuomen evankelis-luterilainen kirkko.\x1F0(FIN11)000004477" ];
$ttka_mappings{'Ruut'} = [ "630	04\x1FaRaamattu.\x1FpRuutin kirja." ];
$ttka_mappings{'Nehemia'} = [ "630	04\x1FaRaamattu.\x1FpNehemian kirja." ];
$ttka_mappings{'Luukkan evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan." ];
$ttka_mappings{'luther-tutkimus'} = [ "600	14\x1FaLuther, Martti,d1483-1546.\x1F0(FIN11)000051426" ];
$ttka_mappings{'Israel'} = [ "651	 7\x1FaIsrael\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p105162" ];
$ttka_mappings{'fariseukset'} = [ "650	 7\x1Fafariseukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p26262" ];
$ttka_mappings{'anabaptistit'} = [ "650	 7\x1Fauudestikastajat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21915" ];
$ttka_mappings{'uskonnot'} = [ "650	 7\x1Fauskonto ja uskonnot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2921" ];
$ttka_mappings{'temppelit'} = [ "650	 7\x1Fatemppelit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11347" ];
$ttka_mappings{'Salomo'} = [ "600	04\x1FaSalomo,\x1FcIsraelin kuningas.\x1F0(FIN11)000125263" ];
$ttka_mappings{'psalmit'} = [ "630	04\x1FaRaamattu.\x1FpPsalmien kirja." ];
$ttka_mappings{'maailmanuskonnot'} = [ "650	 7\x1Fauskonto ja uskonnot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2921" ];
$ttka_mappings{'lunastus'} = [ "650	 7\x1Falunastus (uskonto)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p24818" ];
$ttka_mappings{'kirkko'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835" ];
$ttka_mappings{'juutalaiset - kristityt'} = [ "650	 7\x1Fajuutalaiset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8494",  "650	 7\x1Fakristityt\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6991",  "650	 7\x1Faryhmien väliset suhteet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p29483" ];
$ttka_mappings{'Tiituksen kirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje Titukselle." ];
$ttka_mappings{'rukous'} = [ "650	 7\x1Farukoileminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3551" ];
$ttka_mappings{'perhe'} = [ "650	 7\x1Faperheet\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4363" ];
$ttka_mappings{'makkabilaiskirjat'} = [ "630	04\x1FaRaamattu.\x1FpMakkabilaiskirjat." ];
$ttka_mappings{'kirkot'} = [ "650	 7\x1Fakirkkokunnat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p938" ];
$ttka_mappings{'käsikirjoitukset'} = [ "650	 7\x1Fakäsikirjoitukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11009" ];
$ttka_mappings{'Uuden Testamentin teologia'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'Ugarit'} = [ "651	 7\x1FaUgarit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p212377" ];
$ttka_mappings{'Suomen evankelis-luterilainen kirkko'} = [ "610	24\x1FaSuomen evankelis-luterilainen kirkko.\x1F0(FIN11)000004477" ];
$ttka_mappings{'Luukas'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan." ];
$ttka_mappings{'Kirkkojen maailmanneuvosto'} = [ "610	24\x1FaKirkkojen maailmanneuvosto.\x1F0(FIN11)000001974" ];
$ttka_mappings{'Jeesus Kristus'} = [ "600	04\x1FaJeesus Kristus.\x1F0(FIN11)000105186" ];
$ttka_mappings{'Tuomarien kirja'} = [ "630	04\x1FaRaamattu.\x1FpTuomarien kirja." ];
$ttka_mappings{'tunnustuksellisuus'} = [ "650	 7\x1Fatunnustuksellisuus (uskonto)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17039" ];
$ttka_mappings{'Luther-tutkimus'} = [ "600	14\x1FaLuther, Martti,d1483-1546.\x1F0(FIN11)000051426" ];
$ttka_mappings{'Habakuk'} = [ "630	04\x1FaRaamattu.\x1FpHabakukin kirja." ];
$ttka_mappings{'Obadja'} = [ "630	04\x1FaRaamattu.\x1FpObadjan kirja." ];
$ttka_mappings{'Malakia'} = [ "630	04\x1FaRaamattu.\x1FpMalakian kirja." ];
$ttka_mappings{'Filemonin kirje'} = [ "630	04\x1FaRaamattu.\x1FpKirje Filemonille." ];
$ttka_mappings{'Sefanja'} = [ "630	04\x1FaRaamattu.\x1FpSefanjan kirja." ];
$ttka_mappings{'metafora'} = [ "650	 7\x1Fametaforat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3517" ];
$ttka_mappings{'liitto (teol.)'} = [ "650	 7\x1Faliitto (teologia)\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9768" ];
$ttka_mappings{'kokousjulkaisut'} = [ "655	 7\x1Fakokousjulkaisut\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s16" ];
$ttka_mappings{'kirja-arvostelut'} = [ "655	 7\x1Fakirja-arvostelut\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s1093" ];
$ttka_mappings{'kertomukset'} = [ "650	 7\x1Fakertomukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p24639" ];
$ttka_mappings{'evankeliumi'} = [ "650	 7\x1Faevankeliumi (sanoma)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12378" ];
$ttka_mappings{'Viisauden kirja'} = [ "630	04\x1FaRaamattu.\x1FpViisauden kirja." ];
$ttka_mappings{'vanhurskauttamisoppi'} = [ "650	 7\x1Favanhurskauttaminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5252" ];
$ttka_mappings{'tekstijulkaisut'} = [ "655	 7\x1Falähdejulkaisut\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s1287" ];
$ttka_mappings{'sanakirjat'} = [ "655	 7\x1Fasanakirjat\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s1144" ];
$ttka_mappings{'runous'} = [ "650	 7\x1Falyriikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1365" ];
$ttka_mappings{'radikaaliortodoksia'} = [ "650	 7\x1Faradikaali ortodoksia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p27561" ];
$ttka_mappings{'Qumranin tekstit'} = [ "650	 7\x1FaQumranin kirjoitukset\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p14723" ];
$ttka_mappings{'ortodoksisuus'} = [ "650	 7\x1Faortodoksisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4666" ];
$ttka_mappings{'Naahum'} = [ "630	04\x1FaRaamattu.\x1FpNahumin kirja." ];
$ttka_mappings{'midrash'} = [ "650	 7\x1Faraamatuntulkinta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9984",  "650	 7\x1Farabbiininen kirjallisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p38562" ];
$ttka_mappings{'kartastot'} = [ "655	 7\x1Fakartastot\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s998" ];
$ttka_mappings{'Jooel'} = [ "630	04\x1FaRaamattu.\x1FpJoelin kirja." ];
$ttka_mappings{'Jeesus-liike'} = [ "650	 7\x1FaJeesus-liike\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9537" ];
$ttka_mappings{'dekalogi'} = [ "630	04\x1FaKymmenen käskyä." ];
$ttka_mappings{'uudestisyntyminen'} = [ "650	 7\x1Fakääntymys\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5412" ];
$ttka_mappings{'usko ja tieto'} = [ "650	 7\x1Fakritisismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11679",  "650	 7\x1Fauskonnonfilosofia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6225" ];
$ttka_mappings{'Talmud'} = [ "630	04\x1FaTalmud." ];
$ttka_mappings{'rukouskirjat'} = [ "650	 7\x1Farukouskirjat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21730" ];
$ttka_mappings{'parantaminen'} = [ "650	 7\x1Faparantaminen (terveys)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p425" ];
$ttka_mappings{'misna'} = [ "630	04\x1FaMišna." ];
$ttka_mappings{'Kirkon virka'} = [ "650	 7\x1Fakirkko (instituutio)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8835",  "650	 7\x1Fakirkon työntekijät\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2488" ];
$ttka_mappings{'käsikirjat'} = [ "655	 7\x1Fakäsikirjat\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s1148" ];
$ttka_mappings{'Henokin kirja'} = [ "630	04\x1FaHenokin kirja." ];
$ttka_mappings{'halakha'} = [ "650	 7\x1Fahalakha\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9790" ];
$ttka_mappings{'1. Samuelin kirja'} = [ "630	04\x1FaRaamattu.\x1FpEnsimmäinen Samuelin kirja." ];
$ttka_mappings{'2. Samuelin kirja'} = [ "630	04\x1FaRaamattu.\x1FpToinen Samuelin kirja." ];
$ttka_mappings{'Tobiaan kirja'} = [ "630	04\x1FaRaamattu.\x1FpTobitin kirja." ];
$ttka_mappings{'Sananlaskujen kirja'} = [ "630	04\x1FaRaamattu.\x1FpSananlaskujen kirja." ];
$ttka_mappings{'Rooman valtakunta'} = [ "651	 7\x1FaRooman valtakunta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p105081" ];
$ttka_mappings{'Pietari'} = [ "600	04\x1FaPietari,\x1Fcapostoli.\x1F0(FIN11)000106479" ];
$ttka_mappings{'maallikkosaarna'} = [ "650	 7\x1Fasaarnaajat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6344" ];
$ttka_mappings{'Luther-tutkimus'} = [ "600	14\x1FaLuther, Martti,d1483-1546.\x1F0(FIN11)000051426" ];
$ttka_mappings{'lahkot'} = [ "650	 7\x1Fauskonnolliset yhteisöt\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5605" ];
$ttka_mappings{'lähetyskirjallisuus'} = [ "650	 7\x1Falähetystyö\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11784",  "650	 7\x1Fauskonnollinen kirjallisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7289" ];
$ttka_mappings{'kirkkojen maailmanneuvosto'} = [ "610	24\x1FaKirkkojen maailmanneuvosto.\x1F0(FIN11)000001974" ];
$ttka_mappings{'kiliasmi'} = [ "650	 7\x1Famillenarismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9035" ];
$ttka_mappings{'kieli'} = [ "650	 7\x1Fakielenkäyttö\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11302" ];
$ttka_mappings{'käskyt'} = [ "630	04\x1FaKymmenen käskyä." ];
$ttka_mappings{'Jaakob'} = [ "600	04\x1FaJaakob,\x1Fcpatriarkka." ];
$ttka_mappings{'Israelin historia'} = [ "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'Haggai'} = [ "630	04\x1FaRaamattu.\x1FpHaggain kirja." ];
$ttka_mappings{'ylipappi'} = [ "650	 7\x1Faylipapit\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9690" ];
$ttka_mappings{'vuosikirjat'} = [ "655	 7\x1Favuosikirjat\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s575" ];
$ttka_mappings{'valitus'} = [ "650	 7\x1Favalituslaulut\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p28694" ];
$ttka_mappings{'vaikutus'} = [ "650	 7\x1Favaikutushistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21324" ];
$ttka_mappings{'Uusi Testamentti'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti." ];
$ttka_mappings{'uskonto'} = [ "650	 7\x1Fauskonto ja uskonnot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2921" ];
$ttka_mappings{'tilastot'} = [ "655	 7\x1Fatilastot\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s276" ];
$ttka_mappings{'temppeli'} = [ "650	 7\x1Fatemppelit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11347" ];
$ttka_mappings{'tekstitutkimus'} = [ "650	 7\x1Fatekstintutkimus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13523" ];
$ttka_mappings{'talmud'} = [ "600	04\x1FaTalmud." ];
$ttka_mappings{'Suomen ev. lut. kirkko'} = [ "610	24\x1FaSuomen evankelis-luterilainen kirkko.\x1F0(FIN11)000004477" ];
$ttka_mappings{'Ruutin kirja'} = [ "630	04\x1FaRaamattu.\x1FpRuutin kirja." ];
$ttka_mappings{'raamatun auktoriteetti'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600",  "650	 7\x1Fapyhät kirjat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11248" ];
$ttka_mappings{'Pietarin evankeliumi'} = [ "630	04\x1FaPietarin evankeliumi" ];
$ttka_mappings{'muistelmat'} = [ "655	 7\x1Famuistelmat\x1F2slm/fin\x1F0http://www.yso.fi/onto/yso/p8111" ];
$ttka_mappings{'Mooses'} = [ "600	04\x1FaMooses\x1Fc(Raamatun henkilö)\x1F0(FIN11)000204455" ];
$ttka_mappings{'laki (teologia)'} = [ "650	 7\x1Falait\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1464" ];
$ttka_mappings{'kristologia'} = [ "650	 7\x1Fakristologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6748" ];
$ttka_mappings{'Juudaksen evankeliumi'} = [ "630	04\x1FaJuudaksen evankeliumi." ];
$ttka_mappings{'julistus'} = [ "650	 7\x1Fajulistaminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20729" ];
$ttka_mappings{'Jobin kirja'} = [ "630	04\x1FaRaamattu.\x1FpJobin kirja." ];
$ttka_mappings{'grundtvigilaisuus'} = [ "650	 7\x1Fagrundtvikilaisuus\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9792" ];
$ttka_mappings{'evangelikaalit'} = [ "650	 7\x1Faevankelikalismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19950" ];
$ttka_mappings{'Esterin kirja'} = [ "630	04\x1FaRaamattu.\x1FpEsterin kirja." ];
$ttka_mappings{'elokuva'} = [ "650	 7\x1Fauskonnolliset elokuvat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20201" ];
$ttka_mappings{'Elia'} = [ "600	04\x1FaElia,\x1Fcprofeetta.\x1F0(FIN11)000041901",  "630	04\x1FaRaamattu.\x1FpEnsimmäinen kuninkaiden kirja, 17-19." ];
$ttka_mappings{'Danielin kirja'} = [ "630	04\x1FaRaamattu.\x1FpDanielin kirja." ];
$ttka_mappings{'bibliografiat'} = [ "655	 7\x1Fabibliografiat\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s103" ];
$ttka_mappings{'apokryfikirjat'} = [ "650	 7\x1Faapokryfit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p7204" ];
$ttka_mappings{'4. Mooseksen kirja'} = [ "630	04\x1FaRaamattu.\x1FpNeljäs Mooseksen kirja." ];
$ttka_mappings{'2. Korinttilaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpToinen kirje korinttilaisille." ];
$ttka_mappings{'yhteiskuntauskonto'} = [ "650	 7\x1Fauskontososiologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16170" ];
$ttka_mappings{'vuorisaarna'} = [ "600	04\x1FaVuorisaarna." ];
$ttka_mappings{'varhaisjuutalaisuus'} = [ "650	 7\x1Favarhaisjuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21992" ];
$ttka_mappings{'Vanha testanmentti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti." ];
$ttka_mappings{'Vanhan testamentin ajanhistoria'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'tyyli'} = [ "650	 7\x1Fatyylit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p421" ];
$ttka_mappings{'traditio'} = [ "650	 7\x1Fatraditionalismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6109" ];
$ttka_mappings{'teologian opiskelu'} = [ "650	 7\x1Faopiskelu\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4781",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'suullinen traditio'} = [ "650	 7\x1Fasuullinen perinne\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p27868" ];
$ttka_mappings{'selitykset'} = [ "650	 7\x1Faselittäminen\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p332" ];
$ttka_mappings{'seksuaaliset vähemmistöt'} = [ "650	 7\x1Faseksuaalivähemmistöt\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1828" ];
$ttka_mappings{'Sanalaskujen kirja'} = [ "630	04\x1FaRaamattu.\x1FpSananlaskujen kirja." ];
$ttka_mappings{'Salomon psalmit'} = [ "630	04\x1FaSalomon psalmit." ];
$ttka_mappings{'Roomalaiskatolinen kirkko'} = [ "610	24\x1FaKatolinen kirkko.\x1F0(FIN11)000213215" ];
$ttka_mappings{'reseptiohistoria'} = [ "650	 7\x1Fareseptio\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p24663" ];
$ttka_mappings{'realismi'} = [ "650	 7\x1Farealismi (filosofia)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p2884" ];
$ttka_mappings{'raamattukritiikki'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600",  "650	 7\x1Fakritiikki\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1067" ];
$ttka_mappings{'psalttarit'} = [ "630	04\x1FaRaamattu.\x1FpPsalmien kirja." ];
$ttka_mappings{'Pelastusarmeija'} = [ "610	24\x1FaPelastusarmeija.\x1F0(FIN11)000017174" ];
$ttka_mappings{'ontologia'} = [ "650	 7\x1Faontologia (filosofia)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1055" ];
$ttka_mappings{'oleminen'} = [ "650	 7\x1Faoleva\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1060" ];
$ttka_mappings{'oikeudenkäynti'} = [ "650	 7\x1Faoikeudenkäynti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9063" ];
$ttka_mappings{'myöhäisjuutalaisuus'} = [ "650	 7\x1Favarhaisjuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21992" ];
$ttka_mappings{'muutokset'} = [ "650	 7\x1Faredaktiokritiikki\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9645" ];
$ttka_mappings{'mitralaisuus'} = [ "650	 7\x1Famithralaisuus\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9784" ];
$ttka_mappings{'messu'} = [ "650	 7\x1Famessu (jumalanpalvelus)\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p15214" ];
$ttka_mappings{'Messias'} = [ "650	 7\x1Famessianismi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20455" ];
$ttka_mappings{'merkitys'} = [ "650	 7\x1Famielekkyys\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p14869" ];
$ttka_mappings{'Markuksen evankelimi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan." ];
$ttka_mappings{'Maria'} = [ "600	04\x1FaMaria,\x1FcJeesuksen äiti.\x1F0(FIN11)000105935" ];
$ttka_mappings{'Luther'} = [ "600	14\x1FaLuther, Martti,d1483-1546.\x1F0(FIN11)000051426" ];
$ttka_mappings{'luterilainen kirkko'} = [ "650	 7\x1Faluterilaiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p11818" ];
$ttka_mappings{'logia-lähde'} = [ "650	 7\x1FaQ-teoria\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9641" ];
$ttka_mappings{'kultti'} = [ "650	 7\x1Fakultit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1016",  "650	 7\x1Faliturgiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8301" ];
$ttka_mappings{'konkordanssit'} = [ "655	 7\x1Fakonkordanssit\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s643" ];
$ttka_mappings{'kirjallisuustiede'} = [ "650	 7\x1Fakirjallisuudentutkimus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1066" ];
$ttka_mappings{'kirjallisuuden historia'} = [ "650	 7\x1Fakirjallisuudenhistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p17103" ];
$ttka_mappings{'Kaifas'} = [ "600	04\x1FaKaifas,\x1Fcylipappi." ];
$ttka_mappings{'juhlajulkaisut'} = [ "655	 7\x1Fajuhlajulkaisut\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s812" ];
$ttka_mappings{'Joosia'} = [ "600	04\x1FaJoosia,\x1FcJuudean kuningas." ];
$ttka_mappings{'Joonan kirja'} = [ "630	04\x1FaRaamattu.\x1FpJoonan kirja." ];
$ttka_mappings{'Jonatan'} = [ "600	04\x1FaJoonatan\x1Fc(Raamatun henkilö)" ];
$ttka_mappings{'Jonanneksen evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Johanneksen mukaan." ];
$ttka_mappings{'Johannes Kastaja'} = [ "600	04\x1FaJohannes,\x1FcKastaja." ];
$ttka_mappings{'Joel'} = [ "630	04\x1FaRaamattu.\x1FpJoelin kirja." ];
$ttka_mappings{'ideologia'} = [ "650	 7\x1Faideologiat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p216" ];
$ttka_mappings{'hymnit'} = [ "650	 7\x1Fahymnit\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16052" ];
$ttka_mappings{'Helsingin yliopisto'} = [ "610	24\x1FaHelsingin yliopisto.\x1FbTeologinen tiedekunta.\x1F0(FIN11)000001019" ];
$ttka_mappings{'hartauskirjoitukset'} = [ "650	 7\x1Fahartauskirjat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12098" ];
$ttka_mappings{'fideismi'} = [ "650	 7\x1Fauskonnonfilosofia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6225" ];
$ttka_mappings{'esivalta'} = [ "650	 7\x1Fajulkinen valta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13042" ];
$ttka_mappings{'Eenokin kirja'} = [ "630	04\x1FaHenokin kirja." ];
$ttka_mappings{'Eenok'} = [ "630	04\x1FaHenokin kirja." ];
$ttka_mappings{'diakoniatiede'} = [ "650	 7\x1Fadiakonia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p228" ];
$ttka_mappings{'Baal'} = [ "600	04\x1FaBaal\x1Fc(kanaanilainen jumalolento)" ];
$ttka_mappings{'Augustinus'} = [ "600	04\x1FaAugustinus,d354-430.\x1F0(FIN11)000040816" ];
$ttka_mappings{'1. Tessalonikalaiskirje'} = [ "630	04\x1FaRaamattu.\x1FpEnsimmäinen kirje tessalonikalaisille." ];
$ttka_mappings{'Yhdysvallat'} = [ "651	 7\x1FaYhdysvallat\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p105078" ];
$ttka_mappings{'vatikaanin kirkolliskokoukset'} = [ "610	24\x1FaKatolinen kirkko.\x1FbKirkolliskokous.\x1F0(FIN11)000031111" ];
$ttka_mappings{'Vanha testamenttti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti." ];
$ttka_mappings{'vanha testamentti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti." ];
$ttka_mappings{'Vanha testamenti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti." ];
$ttka_mappings{'Vanha tesamentti'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti." ];
$ttka_mappings{'Vanhan testamentin ajanhistoria'} = [ "630	04\x1FaRaamattu.\x1FpVanha testamentti.",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'Uuden testamentin ajanhistoria'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'UT:n ajanhistoria'} = [ "630	04\x1FaRaamattu.\x1FpUusi testamentti.",  "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780",  "650	 7\x1Favanha aika\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p19859" ];
$ttka_mappings{'Uskonopin kongregaatio'} = [ "610	24\x1FaKatolinen kirkko.\x1FbCongregatio pro Doctrina Fidei." ];
$ttka_mappings{'systemaattinen teologia'} = [ "650	 7\x1Fasystemaattinen teologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3827" ];
$ttka_mappings{'systemaattiinen teologia'} = [ "650	 7\x1Fasystemaattinen teologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3827" ];
$ttka_mappings{'synoptiset evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan." ];
$ttka_mappings{'synoptiset evakeliumit'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan.",  "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan." ];
$ttka_mappings{'suvaitsevuus'} = [ "650	 7\x1Fasuvaitsevaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6236" ];
$ttka_mappings{'suvaitsemattomuus'} = [ "650	 7\x1Fasuvaitsemattomuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9996" ];
$ttka_mappings{'spiritualitetti'} = [ "650	 7\x1Faspiritualiteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p176" ];
$ttka_mappings{'Raamattu'} = [ "630	04\x1FaRaamattu." ];
$ttka_mappings{'Psalmi 110'} = [ "630	04\x1FaRaamattu.\x1FpPsalmien kirja, 110." ];
$ttka_mappings{'Psalmi 104'} = [ "630	04\x1FaRaamattu.\x1FpPsalmien kirja, 104." ];
$ttka_mappings{'protestaanttinen teologia'} = [ "650	 7\x1Faprotestanttiset kirkot\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6842",  "650	 7\x1Fateologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p3830" ];
$ttka_mappings{'prosessteologia'} = [ "650	 7\x1Faprosessiteologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p20936" ];
$ttka_mappings{'Pappeus'} = [ "650	 7\x1Fapappeus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1498" ];
$ttka_mappings{'Origenes'} = [ "600	04\x1FaOrigenes.\x1F0(FIN11)000109103" ];
$ttka_mappings{'Midrash'} = [ "650	 7\x1Faraamatuntulkinta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9984",  "650	 7\x1Farabbiininen kirjallisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p38562" ];
$ttka_mappings{'midras'} = [ "650	 7\x1Faraamatuntulkinta\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9984",  "650	 7\x1Farabbiininen kirjallisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p38562" ];
$ttka_mappings{'Maria Magdaleena'} = [ "600	04\x1FaMagdalan Maria\x1Fc(Raamatun henkilö)" ];
$ttka_mappings{'Magdalan Maria'} = [ "600	04\x1FaMagdalan Maria\x1Fc(Raamatun henkilö)" ];
$ttka_mappings{'Luukkaan evankelumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan." ];
$ttka_mappings{'Luterilaisuus'} = [ "650	 7\x1Faluterilaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p8758" ];
$ttka_mappings{'Jumalan sana'} = [ "630	04\x1FaRaamattu.",  "650	 7\x1Faauktoriteetti\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p12600",  "650	 7\x1FaJumala\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p13849" ];
$ttka_mappings{'Armenian kirkko'} = [ "610	24\x1FaArmenian apostolinen kirkko.\x1F0(FIN11)000214099" ];

##
if ( 1 ) {
    $ttka_mappings{'roomalaiskatolinen kirkko'} = [ "610	24\x1FaKatolinen kirkko.\x1F0(FIN11)000213215" ];
    $ttka_mappings{'Apostolien teot'} = [ "630	04\x1FaRaamattu.\x1FpApostolien teot."];
    $ttka_mappings{'Johanneksen evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Johanneksen mukaan."];
    $ttka_mappings{'Luukkaan evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Luukkaan mukaan."];
    $ttka_mappings{'Markuksen evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Markuksen mukaan."];
    $ttka_mappings{'Matteuksen evankeliumi'} = [ "630	04\x1FaRaamattu.\x1FpEvankeliumi Matteuksen mukaan."];
    $ttka_mappings{'Mooseksen kirjat'} = [ "630	04\x1FaRaamattu.\x1FpPentateukki."];
    $ttka_mappings{'Paavalin kirjeet'} = [ "630	04\x1FaRaamattu.\x1FpPaavalin kirjeet."];
    $ttka_mappings{'Psalmit'} = [ "630	04\x1FaRaamattu.\x1FpPsalmien kirja."];
    $ttka_mappings{'kommentaarit'} = [ "655	 7\x1Fakommentaarit\x1F2slm/fin\x1F0http://urn.fi/URN:NBN:fi:au:slm:s132" ];
    $ttka_mappings{'kirkkotaistelu'} = [ "650	 7\x1Fakirkkotaistelu\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p26341" ];
    $ttka_mappings{'Kirkkotaistelu'} = [ "650	 7\x1Fakirkkotaistelu\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p26341" ];
    $ttka_mappings{'eksegetiikka'} = [ "650	 7\x1Faeksegetiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p9983" ];
    $ttka_mappings{'historia'} = [ "650	 7\x1Fahistoria\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p1780" ];
    $ttka_mappings{'kristinusko'} = [ "650	 7\x1Fakristinusko\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p4668" ];
    $ttka_mappings{'kristologia'} = [ "650	 7\x1Fakristologia\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p6748" ];
    $ttka_mappings{'teologinen etiikka'} = [ "650	 7\x1Fateologinen etiikka\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21033" ];
    $ttka_mappings{'uskontodialogi'} = [ "650	 7\x1Fauskontodialogi\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p5893" ];
    $ttka_mappings{'varhaisjuutalaisuus'} = [ "650	 7\x1Favarhaisjuutalaisuus\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p21992" ];
    $ttka_mappings{'varhaiskristillisyys'} = [ "650	 7\x1Favarhaiskristillisyys\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p16480" ];
    $ttka_mappings{'Qumran'} = [ "651	 7\x1FaQumran\x1F2yso/fin\x1F0http://www.yso.fi/onto/yso/p156522" ];
    $ttka_mappings{'risti'} = [ "650	 7\x1Faristin teologia\x1F2yso/fin\x1F0https://github.com/Finto-ehdotus/YSE/issues/9786" ];
}

sub has_ttka_mapping($) {
    my $term = shift;

    if ( defined($ttka_mappings{$term}) ) { return 1; }
    return 0;
}

sub get_ttka_mappings($) {
    my $term = shift;
    if ( !defined($ttka_mappings{$term}) ) { return undef; }
    my $new_fieldsP = $ttka_mappings{$term};
    my @new_fields = @{$new_fieldsP};
    return @new_fields;

}


sub ttka2yso($) {
    my $term = shift;
    # Accept subset:
    if ( $term =~ /^(juutalaisuus|dogmihistoria|Jumala|raamatuntulkinta|kirkko-oppi|teologia|ekumenia|vanhurskauttaminen|tekstikritiikki|kirkkoisät|pastoraaliteologia|evankeliumit|paavius|filosofinen teologia|pelastus|etiikka|pneumatologia|naiset|uskontoteologia|teologinen antropologia|eskatologia|keskiaika|uskonnollinen kieli|islam|juutalaiskristillisyys|ehtoollinen|tutkimus|kolminaisuusoppi|hellenismi|poliittinen teologia|hermeneutiikka|gnostilaisuus|Qumranin kirjoitukset|juutalainen kirjallisuus|tulkinta|ylösnousemus|kaste|usko|luterilaisuus|antiikki|jumalakäsitykset|areiolaisuus|apokalyptiikka|uskonnonfilosofia|synti|spiritualiteetti|lähetystyö|juutalaiset|katekismukset|kontekstuaalinen teologia|älykäs suunnittelu|alkuperä|mariologia|filosofia|Pyhä Henki|narratiivinen teologia|retoriikka|jumalanpalvelus|prosessiteologia|dialogi|buddhalaisuus|messiaaniset juutalaiset|systemaattinen teologia|saarnat|Raamatun henkilöt|pappeus|asiakirjat|piispat|ortodoksinen kirkko|monoteismi|luterilaiset kirkot|kuolema|kirkon jäsenyys|katolisuus|jumalallistaminen|armo|viisaus|puhdasoppisuus|kuninkaat|kirkkokritiikki|arkeologia|sääntökunnat|pseudepigrafit|narratiivinen tutkimus|kaitselmus|juutalaiskristityt|ekumeniikka|avioliitto|apostoliset isät|sosiologia|protestanttiset kirkot|protestantismi|nestoriolaisuus|kääntäminen|historiankirjoitus|hindulaisuus|temppelit|tekstit|politiikka|missiologia|kritiikki|kristillinen etiikka|identiteetti|dogmatiikka|sielunhoito|rakkaus|postmodernismi|peruskoulu|pelagiolaisuus|manikealaisuus|liturgia|kuolemanrajakokemukset|juutalaissodat|ikuisuus|ihmeet|henkilöhistoria|diakonia|arminiolaisuus|tomismi|sosiaalihistoria|mystiikka|metaforat|kulttuuri|Jumalan valtakunta|ihmiskuva|demonit|anglikaaninen kirkko|uhraaminen|sosiaalietiikka|raamatunkäännökset|luonnontieteet|luonnollinen teologia|kokoukset|kirkkohistoria|kirjallisuus|kärsimys|kalvinismi|darwinismi|syntiinlankeemus|sukupuoli|seksuaalisuus|sakramentit|postkolonialismi|paavit|kielikuvat|kansakoulu|jumalat|feministiteologia|elokuvat|elämäkerrat|apofaattinen teologia|tutkimusmenetelmät|tietoteoria|seurakunnat|rituaalit|pluralismi|myytit|messianismi|liturgiikka|lääketiede|köyhyys|käytännöllinen teologia|katumus|kardinaalit|kansallissosialismi|homiletiikka|heprean kieli|evankelikalismi|epäjumalat|yhteiskunta|vapautuksen teologia|teismi|stoalaisuus|samarialaiset|perisynti|patristiikka|kaupungit|kääntymys|globalisaatio|feminismi|englannin kieli|ekoteologia|ekologia|donatolaisuus|dalit-teologia|antisemitismi|vastustus|uskonnolliset kokemukset|tutkimushistoria|ruumiillisuus|reformoidut kirkot|rauha|psykologia|polemiikki|papisto|pakanuus|oikeudenmukaisuus|narratiivisuus|monikulttuurisuus|metodismi|kultit|kirkkomusiikki|kiirastuli|kehitys|karismaattisuus|järki|intertekstuaalisuus|ihminen|historiantutkimus|evankelis-luterilainen kirkko|elämä|bioetiikka|apostolit|antropologia|AIDS|uskontojen vuorovaikutus|uskonnonvapaus|tekstianalyysi|tahdonvapaus|suullinen perinne|sosiaalinen oikeudenmukaisuus|siunaukset|sielu|rukoukset|rippi|ranskan kieli|rakenneanalyysi|pyhyys|profetiat|persoona|patriarkat|palvonta|pahuus|opiskelijat|omatunto|nimet|naisen asema|muistitieto|moraaliteologia|moraali|marttyyrit|luostarilaitos|luonto|liberaaliteologia|lait|kuolemanjälkeinen elämä|kadotus|inkarnaatio|homoseksuaalisuus|historiallinen sosiologia|helluntailiike|armolahjat|vanhurskaus|valta|uudestikastajat|uskontohistoria|työ|toivo|tiede|teodikea|symboliikka|suunnittelu|pyhät paikat|postliberaali teologia|pietismi|parisuhde|paratiisi|oppiriidat|oppihistoria|opiskelu|opetuslapset|opetus|naispappeus|mytologia|musiikki|muinaiskansat|modernisaatio|metafysiikka|maallikot|logiikka|latinan kieli|lähdekritiikki|kuolemattomuus|kungfutselaisuus|kulttuurihistoria|koptin kieli|kognitiivinen kielitiede|kiroukset|kirkko-oikeus|kirkkokunnat|kehitysstrategiat|kaunokirjallisuus|karismaattiset liikkeet|ihmisoikeudet|hautaus|harhaoppisuus|evoluutio|essealaiset|enkelit|ekumeeniset kirkolliskokoukset|biologia|avioero|asenteet|argumentointi|aitous|aika|adventismi|yliopistot|yhteisö|verbit|vapaus|vanhuus|vanhemmat|valdolaiset|väkivalta|vaikutteet|väärennökset|uskontunnustukset|uskontotiede|uskonnonpedagogiikka|uskonnollinen kirjallisuus|uranvalinta|tutkijat|tunteet|tunnustuskirjat|todisteet|tieto|taide|sosialismi|sosiaalitutkimus|seka-avioliitto|sapatti|saddukeukset|ruumis|ruotsin kieli|rasismi|pyhitys|pyhät kirjat|psykoterapia|populaarikulttuuri|perimätieto|perheet|papit|paholainen|pääsiäinen|orjuus|onnellisuus|omaisuus|näyt|naisnäkökulma|naiskuva|myöhäisantiikki|muutos|mieskuva|metodologia|mennoniitat|menetelmät|magia|maailmankuva|luottamushenkilöt|luonnollinenn teologia|lestadiolaisuus|legendat|kristityt|koulutus|kosmologia|konfliktit|kokemukset|kirkon työntekijät|kirkon hallinto|kirjallisuuskritiikki|kehitysoppi|kartusiaanit|kapitalismi|kantilaisuus|kansalaisyhteiskunta|kanoninen oikeus|juutalaisvainot|ikonit|humanismi|holokausti|historiankäsitys|herrnhutilaisuus|haudat|estetiikka|eläimet|deismi|ateismi|apologetiikka|anteeksianto|analyysi|almut|ajanlasku|zarathustralaisuus|ystävyys|ylistys|yliluonnolliset olennot|yleisö|yhteisöllisyys|vuorovaikutus|vesi|velkaantuminen|vatsa|vastuu|vastauskonpuhdistus|varhaiskeskiaika|vapaa tahto|vapaakirkot|vapaaehtoistyö|vainot|vaikutushistoria|vähemmistöt|vaatteet|uusplatonismi|uskontososiologia|uskontokritiikki|uskontokasvatus|uskonnollisuus|uskonnolliset yhteisöt|uskonnolliset liikkeet)$/ ) {
	return 1;
    }
    # Currently we accept everything that hasn't been treated before:
    if ( pref_label2id($term, 'yso/fin') ) {
	return 1;
    }
    
    return 0;
}



our @tarkenteelliset_ysot;
sub ysofin_tarkenne2pref_label($) {
    my $basename = shift();
    if ( !$yso_loaded ) {
	&read_yso();
	@tarkenteelliset_ysot = grep(/\(/, sort keys %ysofin_pref_label2yso_id);
    }
    
    my @results = ();
    my $len = length($basename);
    foreach my $term ( grep(/\(/, @tarkenteelliset_ysot) ) {
	if ( $basename eq substr($term, 0, $len) &&
	     $term =~ /^\Q$basename\E \(/ ) {
	    $results[$#results+1] = $term;
	}
    }
    return @results;
}

our @tarkenteelliset_yso_paikat;
sub ysopaikatfin_tarkenne2pref_label($) {
    my $basename = shift();
    if ( !$yso_paikat_loaded ) {
	&read_yso_paikat();
	@tarkenteelliset_yso_paikat = grep(/\(/, sort keys %ysopaikatfin_pref_label2ysopaikat_id);
    }
    

    &read_yso_paikat();
    my @results = ();
    my $len = length($basename);
    foreach my $term ( grep(/\(/, @tarkenteelliset_yso_paikat) ) {
	if ( $basename eq substr($term, 0, $len) &&
	     $term =~ /^\Q$basename\E \(/ ) {
	    $results[$#results+1] = $term;
	}
    }
    return @results;
}

sub tarkenne2pref_label($$) {
    my ( $term, $lex ) = @_;
    if ( $lex eq 'yso/fin' ) {
	return ysofin_tarkenne2pref_label($term);
    }

    if ( $lex eq 'yso-paikat/fin' ) {
	return ysopaikatfin_tarkenne2pref_label($term);
    }
    
    #die("Unsupported lex: '$lex'");
}

sub yso_or_ysopaikat_pref_label2id($$) {
    my ( $term, $lex ) = @_;
    my $id = pref_label2id($term, $lex);
    if ( $id ) { return $id; }
    $lex =~ s/^yso\//yso-paikat\// || die();
    return pref_label2id($term, $lex);
}


sub is_valid_a20($) {
    my $content = shift;

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

# TODO:
# "kielet" & "opetusmenetelmät" => "kieltenopetus"
# jos "koulut" ja "kiusaaminen" niin lisää "koulukiusaaminen"...
#
1;

