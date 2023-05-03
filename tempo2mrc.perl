#!/usr/bin/perl -w -I. -I/opt/tempo/bin
#
# tempo2mrc.perl -- convert Yle's tempo files to Marc21
#
# Copyright (c) 2021-2023 HY (KK). All Rights Reserved.
#
# Author(s): Nicholas Volk <nicholas.volk@helsinki.fi>
#

use strict;
use warnings;
use JSON;


use nvolk_marc_record;
use nvolk_finto;

use File::Copy;

use tempo_multipart;
use tempo_theme;
use tempo_title;
use tempo_utils; # unlike other tempo_* files this contains generic funcs
use tempo_recording_location_details;
use tempo_artists_ownerships;

my $dd_regexp = get_dd_regexp();
my $mm_regexp = get_mm_regexp();
my $yyyy_regexp = get_yyyy_regexp();

#my $fi_yle = '(FI-Yle)';

sub get_datestring();

our $debug = 1;
our $robust = 0; 
our %config;

our $default007 = 's|||||||||||||'; # We don't know much, do we...
our $default_CD = 'sd|f||g|||m|||';
our $default_C =  'ss||||j|||p|||';
our $default007c = 'cr||n|||||||||';
our $default008 = get_datestring(). 's        xx ||nn             |||||' ;
#                             0-5    6789012345678901234567890123456789

# Defaults:
our $input_directory = undef;
our $output_directory = undef;
our $error_directory = undef;



# specific language is not https://marc21.kansalliskirjasto.fi/kielet_nimet.htm
# so this get two 041 fields: one for more generic value + a ISO-639-9 version
our $iso639_3_regexp = "(guw|sjd)"; 
# Säveltäjä might be a few hundred years old I guess:





our %d773;
our %h773;
our %o773;
our %t773;
our %field006;
our %field007;
our %field008_15_17;
#our %field300;



my $iso_kirjain =  "(?:[A-Z]|Á|Å|Ä|Ç|É|Md|Ø|Ó|Õ|Ö|Ø|Š|Ü|Ž)"; # Md. on mm. Bangladeshissä yleinen lyhenne M[ou]hammedille...
#my $pikkukirjain =  Encode::encode('UTF-8', "[a-z]|a\-a|à|á|å|ä|æ|č|ç|ć|è|é|ë|ì|í|ï|ñ|ń|ò|ó|õ|ö|š|ù|ú|ü|ỳ|ý|ø|ß");
my $pikkukirjain =  "(?:[a-z]|a\-a|à|á|â|å|ã|ä|æ|ă|ā|č|ç|ć|è|é|ê|ë|ě|ė|ȩ|ì|í|ï|î|ī|ł|ñ|ń|o-o|ò|ó|õ|ö|ô|š|ş|ð|ù|ú|ü|û|ū|ỳ|ý|ÿ|ž|ø|ß)";




#my $paikka_regexp = "$iso_kirjain(?:$pikkukirjain)+";



sub usage() {
    print STDERR "Usage:\n",
	" $0 input.json\n",
	" $0 --input-directory=/what/ever\n",
	" $0 --input-directory=TODO --output-directory=processed --error-directory=rejected\n";
}

sub pp_json($) {
    my $ld_ref = shift;
    #return JSON->new->ascii->pretty->encode(decode_json join '', $ld)
    return JSON->new->ascii->pretty->encode($ld_ref);
}


sub digitalized_by_Yle($) {
    my ( $customID ) = @_;
    if ( $customID =~ /^DIG[IY]-/ ) {
	return 1;
    }
    return 0;
}

sub int2finnish_month_name($$) {
  my ( $m, $marc_record_ref ) = @_;
  if ( $m eq "01" ) { return "tammikuu"; }
  if ( $m eq "02" ) { return "helmikuu"; }
  if ( $m eq "03" ) { return "maaliskuu"; }
  if ( $m eq "04" ) { return "huhtikuu"; }
  if ( $m eq "05" ) { return "toukokuu"; }
  if ( $m eq "06" ) { return "kesäkuu"; }
  if ( $m eq "07" ) { return "heinäkuu"; }
  if ( $m eq "08" ) { return "elokuu"; }
  if ( $m eq "09" ) { return "syyskuu"; }
  if ( $m eq "10" ) { return "lokakuu"; }
  if ( $m eq "11" ) { return "marraskuu"; }
  if ( $m eq "12" ) { return "joulukuu"; }

  mark_record_as_rejected($marc_record_ref, "Illegal month code '$m'");

  return '';
}






sub add_REP_skip($) {
    my $marc_record_ref = shift;
    my $field = ${$marc_record_ref}->add_field('REP', "  \x1Fas");
    print STDERR "ADD REJECT FIELD: ", $field->toString(), "\n";
}

sub mark_record_as_rejected($$) {
    my ( $marc_record_ref, $error_msg ) = @_;
    &add_REP_skip($marc_record_ref);
    if ( $error_msg ) {
	print STDERR "ERROR\tReject record, reason: ", $error_msg, "\n";
    }
}
    

sub reject_batch($) {
    my $marc_records_ref = shift;
    my $n = $#{$marc_records_ref} + 1;
    if ( $n == 0 ) {
	print STDERR "BATCH REJECTED! NO RECORDS\n";
	return 1;
    }

    foreach my $record ( @{$marc_records_ref} ) {
	if ( $record->is_deleted() ) {
	    print STDERR "BATCH REJECTED! REASON: CDY/DIGY (MARC AS DELETED)\n";
	    return 1;
	}
    }
    
    # KK is interested only in relatively new publications:
    my $publication_year = ${$marc_records_ref}[0]->get_publication_year();
    if ( $publication_year =~ /^[1-9][0-9]*$/ && $publication_year < 2000 ) {
	print STDERR "BATCH REJECTED! REASON: PUBLICATION_YEAR $publication_year\n";
	return 1;
    }

    if ( 0 ) {
	# Won't work for multiparts...
	foreach my $record ( @{$marc_records_ref} ) {
	    my $field = $record->get_first_matching_field('773');
	    if ( defined($field) && $field->{content} =~ /\x1Fg[^\x1F]*[Rr]aita (\d+)/ ) {
		my $raita = $1;
		if ( $raita > $n ) {
		    print STDERR "BATCH REJECTED! 773\$g TRACK $raita (Set of $n record(s))\n";
		    return 1;
		}
	    }
	}
    }
    
    my $album_title = ${$marc_records_ref}[0]->get_first_matching_field('245');
    if ( !defined($album_title) ) {
	my $f338 = ${$marc_records_ref}[0]->get_first_matching_field('338');
	my $content = $f338->{content} || '(myös kenttä 338 puuttuu)';
	$content =~ s/.*?\x1Fa//;
	$content =~ s/\x1F.*$//;
	print STDERR "BATCH REJECTED! REASON: MISSING ALBUM TITLE (Set of $n record(s))\t", $content, "\n";
	return 1;
    }
    




    foreach my $record ( @{$marc_records_ref} ) {
	# Sanity checks. (We might drop the nameless host,
	# but keep the rest eventually?)
	my @required_tags = ( '007', '245' );
	foreach my $tag ( @required_tags ) {
	    my $field = $record->get_first_matching_field($tag);
	    if ( !defined($field) ) {
		print STDERR "BATCH REJECTED! REASON: MISSING $tag FIELD (Set of $n record(s))\n";
		return 1;
	    }
	}
    }


    # REP $a s (=skip) detected
    foreach my $record ( @{$marc_records_ref} ) {
	# Sanity checks. (We might drop the nameless host,
	# but keep the rest eventually?)
	my @required_tags = ( 'REP' );
	foreach my $tag ( @required_tags ) {
	    my $field = $record->get_first_matching_field($tag);
	    if ( defined($field) ) { # Donät bother to check $a 's':
		print STDERR "BATCH REJECTED! REASON: ", $field->toString(), "\n";
		return 1;
	    }
	}
    }

    
    print STDERR "BATCH ACCEPTED\n";
    # TODO: REJECT BATCH IF YEAR IS PRE-2020
    return 0;
}


sub is_year($) {
    my $year = shift();
    if ( $year =~ /^${yyyy_regexp}$/ ) { return 1; }
    return 0;
}

sub get_year($$$) {
    my ( $key, $tempo_dataP, $marc_record_ref ) = @_;
    my ( $val ) = keyvals2vals(extract_keys($key, $tempo_dataP));
    my $specifier = undef;
    if ( defined($val) && $val ) {
	if ( $val =~ s/^([0-9 ]+) (noin|viim)$/$1/ ) {
	    $specifier = $2;
	}
	if ( is_year($val) ) {
	    return ( $val, $specifier );
	}
	if ( $val =~ /^($yyyy_regexp)-($yyyy_regexp)/ && $1 < $2 ) {
	    my $y1 = $1;
	    my $y2 = $2;
	    # use the 2nd year hackily as specifier
	    if ( !defined($specifier) ) {
		return ( $y1, $y2 );
	    }
	    return ( $val, $specifier ); # will this cause issues?
	}
	# Seen once:
	if ( $val =~ /^($yyyy_regexp) ($yyyy_regexp)/ && $1 < $2 ) {
	    return ( $val, $specifier ); # will this cause issues?
	}
	# Can't handle/guess:
	if ( $val =~ /^(20.)$/ ) {
	    return ( undef, $specifier );
	}

	&mark_record_as_rejected($marc_record_ref, "Check $key, val='$val'\n");
	return ( undef, undef );
    }
    return ( undef, $specifier );
}

sub add_marc_field($$$) {
    my ( $marc_recordP, $tag, $content ) = @_;
    my $field = ${$marc_recordP}->add_field($tag, $content);
    if ( $debug ) {
	print STDERR "ADD FIELD '", $field->toString(), "'\n";
    }
    return $field;
}

sub get_tempo_id_from_marc_record($) {
    my $marc_record_ref = shift;
    my @cands = ${$marc_record_ref}->get_all_matching_fields('035');
    #print STDERR "WP has ", ($#cands+1), " cands\n";
    @cands = grep { $_->{content} =~ /\x1Fa\(FI-Yle\)/ } @cands;
    if ( $#cands == 0 ) {
	if ( $cands[0]->{content} =~ /\x1Fa\(FI-Yle\)([^\x1F]+)$/ ) {
	    return $1;
	}
	die(); # NB! Batch rejection is already decided, thus keep die() here
    }
    die("No ID from ".($#cands+1)." cands"); # NB! Batch rejection is already decided, thus keep die() here
    return undef;
}



my $yhtyeen = "(?:muut )?(?:jousikvartetin|jousikvintetin|jousisekstetin|kamariorkesterin|kamariyhtyeen|kuoron|lauluyhtyeen|orkesterin|säestävän yhtyeen|yhtyeen)";
my $rooli = "(?:levyllä esiintyvät |mahdollinen |muut? )?(?:avustajat?|esittäjät?|jäsen|jäsenet|jäseniä|mahdollinen avustaja|muusikot|soitinsolistit|solistit|soololaulaja|säestävät muusikot)";
my $jossakin = "(?:teoskohtaisesti )?(?:albumin |levyn )?(?:albumitasolla|esittelylehtisessä|kannessa|kansilehdessä|oheislehtisessä|oheistiedoissa|sisäkannessa|tekstilehtisessä|tiedoissa|yleistietodokumentissa)";


sub description_cleanup($) {
    my ( $description_ref ) = @_;

    if ( !defined(${$description_ref}) ) { return; }
    
    ${$description_ref} =~ s/^ +//gm;
    ${$description_ref} =~ s/ +$//gm;
    print STDERR "DC: '", ${$description_ref}, "'\n";
    while ( ${$description_ref} =~ s/(^|\. |  )(?:$yhtyeen )?(?:$rooli|$rooli ja $rooli) lueteltu $jossakin(?:( ja| sekä) $jossakin)?(?:$|\.)/$1/im ) {
	${$description_ref} =~ s/^ +//gm;
	#${$description_ref} =~ s/ +$//gm;
	${$description_ref} =~ s/ +/ /gm;	
    }
}


sub is_sacd($) {
    my ( $description_ref ) = @_;

    if ( !defined(${$description_ref}) ) { 
	return 0;
    }

    if ( ${$description_ref} =~ s/\. SACD\././ ||
	 ${$description_ref} =~ s/^SACD\.\s*// ) {
	return 1;
    }

    return 0;
}


# (this data apparently originates from "kokoonpanokoodit_YKL_korjattu.txt")
our %ykl = ( 'KAB' => '78.742', 'KAF' => '78.812', 'KAG' => '78.65',
	     'KAH' => '78.66',  'KAK' => '78.822', 'KAP' => '78.61',
	     'KAR' => '78.871', 'KAS' => '78.822', 'KAT' => '78.852',
	     'KAV' => '78.712', 'KKL' => '78.3414', 'KKM' => '78.3412',
	     # 'KI' => 'Instrumentaaliesitys.')); last SWITCH; };
	     'KKN' => '78.3413', 'KKP' => '78.3414', 'KKQ' => '78.3411',
	     'KKT' => '78.3414', 'KKU' => '78.3414', 'KO' => '78.54',
	     'KOC' => '78.52',   'KOF' => '78.54', 'KOJ' => '78.521',
	     'KOW' => '78.53', 'KW'  => '78.51',
    );

sub process_ensemble($$$) {
    my ( $ensembles_ref, $marc_recordP ) = @_;
    my @ensembles = @{$ensembles_ref};
    for ( my $i=0; $i <= $#ensembles; $i++ ) {
	my $curr_ensemble = $ensembles[$i];
	if ( $curr_ensemble =~ /^([A-Z]+) / ) {
	    my $code = $1;
	    if ( defined($ykl{$code}) ) {
		add_marc_field($marc_recordP, '084', "  \x1Fa".$ykl{$code}."\x1F2ykl");
	    }
	    elsif ( $code eq 'KI' ) {
		add_marc_field($marc_recordP, '500', "  \x1FaInstrumentaaliesitys.");
	    }
	    elsif ( $debug ) {
		print STDERR "WARNING\tUnable to map ensemble '$curr_ensemble'\n";
	    }
	}
    }
}


sub extract_identifier($$$) {
    my ( $key, $tempo_dataP, $marc_record_ref ) = @_;

    my @codes = keyvals2vals(extract_keys($key, $tempo_dataP));
    if ( scalar(@codes) == 0 ) {
	if ( $debug ) {
	    print STDERR "No ISRC found via '$key'\n";
	}
	return;
    }
    # Multiple EAN/ISRC should not happen
    if ( scalar(@codes) > 1 && $key =~ /\/(ean|isrc)$/ ) {
	print STDERR "ERROR\tReject record\tReason: multiple instance of '$key'\n";
	&add_REP_skip($marc_record_ref);
    }
    
    @codes = sort @codes; # TM wished this for isrc 2022-08-19. (Should we do ean and isrc separately?)
    
    foreach my $curr_code ( @codes ) {
	if ( $curr_code !~ /\S/ ) {
	    # harmless, value is ''.
	}
	elsif ( $key =~ /\/ean$/ ) {
	    # LS 2021-10-18: "Viivakoodeista: meillä ei aikaisemmin ole ollut
	    # kuin yksi kenttä kaikentyyppisille viivakoodeille, ja se on
	    # Tempossa mäpätty Fonosta tuohon EAN-kenttään. Paras ratkaisu olisi
	    # kai ollut käyttää GTINiä ja lisätä etunollat kaikille, mutta koska
	    # tätä ei ollut Tempon tuotteessa saatavilla, kaikki Ylen
	    # viivakoodit ovat jatkossa tuossa EAN-kentässä (myös ne vanhan
	    # aikakauden viivakoodit jotka eivät ole UPC:tä eivätkä EAN:ää).
	    if ( $curr_code =~ /^[0-9]{13}$/ ) {
		add_marc_field($marc_record_ref, '024', "3 \x1Fa$curr_code");
	    }
	    # Assume it a UPC code
	    elsif ( $curr_code =~ /^[0-9]{12}$/ ) {
		add_marc_field($marc_record_ref, '024', "1 \x1Fa$curr_code");
	    }
	    # Assume it a GTIN code, and convert it to EAN:
	    # (KS apparently provived this simple conversion rule:
	    elsif ( $curr_code =~ /^0([0-9]{13})$/ ) {
		my $gtin2ean = $1;
		add_marc_field($marc_record_ref, '024', "3 \x1Fa${gtin2ean}");
	    } 
	    else {
		if ( $robust ) {
		    print STDERR "WARNING\tUnexpected ean '$curr_code'\n";
		}
		else {

		}
	    }
	}
	elsif ( $key =~ /\/isrc$/ ) {
	    if ( $curr_code =~ /^([A-Z0-9]-?){11}[A-Z0-9]$/ ) {
		# TM 2022-08-19: "ISRC:t tallennetaan Violaan ilman väliviivoja"
		# TODO: näille pitäs kirjoittaa testejä...
		$curr_code =~ s/-//g;
		add_marc_field($marc_record_ref, '024', "0 \x1Fa$curr_code");
	    }
	    # Bug in data?: 628dfa6ac5799c0029f78b2f.json:"isrc": "FIBAR2200107 Gert Kaasik,Juha Vainio,Kaisa",
	    elsif ( $curr_code =~ /^(([A-Z0-9]-?){11}[A-Z0-9]) / ) {
		$curr_code = $1;
		add_marc_field($marc_record_ref, '024', "0 \x1Fa$curr_code");
	    }
	    else {
		print STDERR "Unexpected/unhandled ISRC value\n key:'$key',\n val:'$curr_code'\n";
		# Crappy ISRC is not worth dying for :D
	    }
	}
	# ISWC is new, and not seen in Fono!
	elsif ( $key =~ /\/iswc$/ && $curr_code =~ /^[a-z0-9]{11}/i ) {
	    add_marc_field($marc_record_ref, '024', "7 \x1Fa$curr_code");
	}
	else {
	    
	    print STDERR "ERROR\tReject record\tUnexpected key or value key\n key:'$key',\n val:'$curr_code'\n";
	    &add_REP_skip($marc_record_ref);
	}
    }
} 

sub get_customID($$$) {
    my ( $tempo_dataP, $prefix, $marc_record_ref ) = @_;
    my $key = "/$prefix/custom/CustomID";
    my @vals = keyvals2vals(extract_keys($key, $tempo_dataP));
    if ( scalar(@vals) == 0 ) {
	# 2022-09-26: CustomID-less stuff has started to appear...
	return undef;
    }
    if ( scalar(@vals) > 1 ) {

	print STDERR "ERROR\tReject record\tReason: multiple custom ids\n";
	&add_REP_skip($marc_record_ref);
	
	print STDERR "Unexpected number of custom ids (N=", ($#vals), ") for $key:\n  ", join("\n  ", @vals), "\n";

	print STDERR "ALL DATA:\n", join("\n", @{$tempo_dataP}), "\n";

    }
    my $customID = $vals[0];   
    return $customID;
}

# Tempo provides us with more detailed 007 fields than what the fono
# conversion derived from 104. Conversion handled 007/{00,01,03,06,10}
my %custom_id2f007 = (
    # 'CD-' =>
    'CD-'   => $default_CD, # Yle's suggestion: 'sd|fsnunnmmn||'
    'CDY-'  => $default_CD, # Yle's suggestion: 'sd|fsnunnumn||',
    'MLP-'  => 'sd|bmmcnnmpl||', # Yle suggestion
    '-LP-'  => 'sd|bmmdnnmpl||', # Yle suggestion
    #'+LP-'  => 'sd|bmmennmpl||', # Yle suggestion, # 12" (normal) == FONO104 /^33rpm/
    '+LP-'  => 'sd|b||e|||p|||', # 12" (normal) == FONO104 /^33rpm/
    'MLPS-' => 'sd|bsmcnnmpl||', # Yle suggestion
    '-LPS-' => 'sd|bsmdnnmpl||', # Yle suggestion
    '+LPS-' => 'sd|bsmennmpl||', # Yle suggestion, Fono 104: LP
    'LP-'   => 'sd|bzmznnmpl||', # Yle suggestion
    '45-'   => 'sd|cmmcnnmpl||', # Yle suggestion
    '45S-'  => 'sd|csmcnnmpl||', # Yle suggestion
    '+45S-' => 'sd|csmennmpl||', # Yle suggestion
    '78-'   => 'sd|dmsznnusl||', # Yle suggestion
    'D78-'  => 'sd|dmsznnusl||', # Yle suggestion
    'DA-'   => 'ss||znz|uumn||', # Yle suggestion
    'DAY-'  => 'ss||znz|uumn||', # Yle suggestion
    'KN-'   => 'ss||znzlcm|n||', # Yle suggestion
    'SRK-'  => 'st||mnzmuu|n||', # Yle suggestion
    'SRKS-' => 'st||snzmuu|n||', # Yle suggestion
    'ÄN-'   => 'st||snzmuu|n||', # Yle suggestion
    'V-'    => 'st||snzmuu|n||' # Yle suggestion
);

sub tempo_is_electronic_resource($$) {
    my ( $customID, $is_sacd ) = @_;
    if ( !defined($customID) ) { return 0; }
    if ( !digitalized_by_Yle($customID) || $is_sacd ) {
	return 0;
    }
    return 1;
}

sub custom_id2f007($$$$$) {
    my ( $customID, $tempo_dataP, $is_sacd, $tempo_title, $marc_record_ref ) = @_;

    # LS 20211018:
    # "Meillä ei suoraan ole kenttää, jossa ilmoitetaan aineiston ilmiasu,
    # mutta tuon custom_id:n ensimmäinen osa, meillä 'kartuntasarja',
    # indikoi asiaa ja useimmiten ilmiasun voisi mäpätä siitä suoraan.
    # ...Meillä lainaustarkkailuun on mäpätty kartuntasarjat tällä tavoin
    # [=%custom_id2f007], jos siitä on apua:"
    if ( defined($customID) && !digitalized_by_Yle($customID) && $customID =~ /^([\-\+]?[A-Z]+-)/ ) {
	my $type = $1;
	if ( !defined($custom_id2f007{$type}) ) {
	    print STDERR "ERROR\tReject record\tReason: can't handle customID '$customID'\n";
	    &add_REP_skip($marc_record_ref);
	    return undef;
	}
	my $value = $custom_id2f007{$type};

	# Every (already seen) kartuntasarja is listed (=supported) by the regexp
	if ( $customID =~ /^(CD-|CDY-|\+LP-)/ ) {
	    return $value;
	}
	# Untested/unsupported values:
	print STDERR "ERROR\tReject record\tReason: untested/unsupported customID value '$value'\n";
	&add_REP_skip($marc_record_ref);

	return $value;
    }

    # LS 2021-10-18:
    # "Ainoa mahdollinen ongelma ovat DIGI-sarjaan tallennetut digitoinnit
    # fyysisiltä taltioilta - sarja kertoo missä muodossa julkaisu on Ylen
    # kokoelmassa, mutta ei sen alkuperäisen julkaisun muotoa. Näitä on
    # satunnaisesti ja niissä alkuperäinen formaatti on muistaakseni
    # laitettu tekstihuomautuksena albumitasolle."
    # Let's assume that DIGI is pretty much the same as Fono 104 Audiofile...
    #
    # LS2022-05-16:
    # "DIGI-sarja on lähtökohtaisesti syntysähköisiä julkaisuja, ja nämä
    # fyysisiltä taltioilta digitoidut poiminnat ovat siellä vähemmistö.
    # Pääsääntönä voisi siis olla, että DIGI-sarja on elektronisia julkaisuja,
    # ja Jaskan kanssa voitte tarkentaa jos esim. äänitteen tasolla olisi sopiva
    # huomautus silloin kun alkup. tallenne on ollut fyysinen julkaisu kuten
    # meillä lainassa ollut levy tai cd-single jonka fyysinen taltio on
    # digitoinnin jälkeen poistettu.
    #
    # 246 oli Fono-aikana välittäjän eli hankintapaikan koodi, jolloin esim.
    # iTunes-ostot voitiin sen pohjalta päätellä kaikki tiedostomuotoisiksi.
    # Tempossa tätä kenttää ei enää käytetä koska tilausten hallinta ja
    #kirjanpito hoidetaan toisessa järjestelmässä.
    if ( &tempo_is_electronic_resource($customID, $is_sacd) ) {
	# Beyond this point we assume everything is digital:
	# If we have no information about source at this point,
	# and there's no title, we *very boldly* assume that this is
	# a verkkoaineisto,
	# if there's no title 
	# (Same as empty Fono-130 before)
	if ( !defined($tempo_title) ) {
	    # Require that this is a B-sideless single:
	    if ( grep(/tracks\[1\]/, @{$tempo_dataP}) ) {
		print STDERR "WARNING\tMultitrack nameless whatever.\n";
		# We don't probably want these...
	    }
	    else {
		print STDERR "WARNING\tOne track nameless whatever.\n";
	    }
	    # return $default007c;
	}
	
	print STDERR "WARNING\tUsing fallback 007. Description might contain some information...\n";
	# Fallback value for electronic stuff:
	return $default007c;
    }
   return undef;
}



our %map2physical_description = (
    'CD' => 'CD-äänilevy',
    'KN' => 'C-kasetti'
# seen: m4a	
);

sub map2physical_description($$) {
    my ( $desc, $marc_record_ref ) = @_;
    if ( defined($map2physical_description{$desc}) ) {
	return $map2physical_description{$desc};
    }
    # Unhandled values, that do not cause rejection:
    if ( $desc =~ /^(m4a)$/ ) {
	print STDERR "WARNING\tNot sure about the physical description of $desc.\n";
	return undef;
    }

    # Unhandled values that cause rejection:
    foreach my $key ( sort keys %map2physical_description ) {
	my $val = $map2physical_description{$key};
	print STDERR "'$key' => '$val'\n";
    }

    print STDERR "ERROR\tReject record\tReason: unknown physical description '$desc'\n";
    &add_REP_skip($marc_record_ref);

    return undef;
}

my %physical_description_to_007 = (
    'C-kasetti' => $default_C,
    'CD-äänilevy' => $default_CD
);

sub physical_description_to_007($$) {
    my ( $pd, $marc_record_ref ) = @_;
    if ( defined($physical_description_to_007{$pd}) ) {
	return $physical_description_to_007{$pd};
    }
    print STDERR "ERROR\tReject record\tReason: unable to map phys. desc => 007 '$pd'\n";
    &add_REP_skip($marc_record_ref);
    return undef;
    
}

sub normalize_musicians($) {
    my ( $musicians_ref ) = @_;
    # Sekä: Masa Orpana (saksofoni /01). Kalle Alatalo (mandoliini /05).
    if ( ${$musicians_ref} =~ /$rooli:.*\. sekä:/i ) {
	${$musicians_ref} =~ s/Sekä:/Lisäksi:/; # KS 2016-02-22
    }
    else {
	${$musicians_ref} =~ s/. Sekä: /, /; # KS 2016-02-22
    }
    ${$musicians_ref} =~ s/\)\. /\), /g;
    ${$musicians_ref} =~ s/\), Lisäksi/\). Lisäksi/g;
    ${$musicians_ref} =~ s/\)\.$/\)/g;
}

sub description2musicians($$) {
    my ( $description_ref, $marc_record_ref ) = @_;

    print STDERR "D2M '",  ${$description_ref}, "'\n";

    if ( ${$description_ref} =~ s/^(.*) ja (.*?)\. Muut jäsenet: (.*)$// ) {
	my $musicians = "$1 ja $2: $1, $3";
	normalize_musicians(\$musicians);
	return $musicians;
    }
    # Emil Brandqvist Trio. Muut jäsenet: Max Thornberg (kontrabasso). Tuomas Turunen (piano).
    # FAIL: 'Max De Aloe Baltic Trio. Muut jäsenet: Niklas Winter (kitara), Jesper Bodilsen (kontrabasso).' # p.o. "Max De Aloe (Baltic Trio)" tma.
    if ( ${$description_ref} =~ s/^(Max De Aloe) (Baltic Trio)\. Muut jäsenet: (.*)$// ||
	${$description_ref} =~ s/^(\S+(?: \S+)+) (Trio)\. Muut jäsenet: (.*)$// ) {
	my $musicians = "$1 $2: $1, $3";
	normalize_musicians(\$musicians);
	return $musicians;
    }
    
    my $tmp = ${$description_ref};
    if ( $tmp =~ s/(?:^| )((?:$yhtyeen )?(?:$rooli): .*)$//i ) {
	my $musicians = $1;
	if ( $musicians =~ /^[A-Z]/ ) {
	    ${$description_ref} = $tmp;
	    normalize_musicians(\$musicians);
	    return $musicians;
	}
    }

    if ( ${$description_ref} =~ /jäsenet/i ) {
	# 'Jere Ijäs ja Monacon Työväen Palloilijat. Muut jäsenet: Tom Nyman (bassokitara). Anssi Nykänen (rummut). Sekä: Viitasen Piia (taustalaulu). J. Karjalainen (huuliharppu). Miikka Paatelainen (steel-kitara).'

	# Don't accept record as some information is lost:
	print STDERR "ERROR\tReject record\tReason: desc2musicians '", ${$description_ref}, "'\n";
	&add_REP_skip($marc_record_ref);
    }

    return undef;
}
    
sub description2additional_musicians($) {
    my ( $description_ref ) = @_;

    # NB! We have never seen anything else after "Sekä:" (yet).
    # However, N=4 (2022-10-02)
    # Yes we have: ["Jäsenet: Arttur Teränen (kitara, taustalaulu). Juho Eskola (bassokitara). Eero Sampolahti (rummut, taustalaulu). Soittovapaa 19.8."]
    
    if ( ${$description_ref} =~ s/ ?Sekä: ?(.*?)((?: Soittovapaa: .*)?)$/$2/ ) {
	my $additional_musicians = $1;
	&normalize_musicians(\$additional_musicians);
	return $additional_musicians;
    }
    return undef;
}


sub description2physical_description($$) {
    my ( $description_ref, $marc_record_ref ) = @_;

    my %etlist;

    if ( ${$description_ref} =~ s/ ?Alkup(?:\.|eräinen) formaatti:? (CD|KN|m4a)\.?$// ||
	 ${$description_ref} =~ s/ ?Alkup(?:\.|eräinen) formaatti:? (CD|KN|m4a)\. / / ) {
	my $original_format = $1;
	return &map2physical_description($original_format, $marc_record_ref);
    }

    if ( ${$description_ref} =~ /Alkup.*? formaatti: / ) {
	print STDERR "ERROR\tReject record\tReason: incomplete description proecessing '", ${$description_ref}, "'\n";
	&add_REP_skip($marc_record_ref);
    }
    return undef;
}

sub custom_id2physical_description($$$$$) { # 300$a basename
    my ( $customID, $tempo_dataP, $is_sacd, $physical_description, $marc_record_ref) = @_;
    my %hits;
    if ( defined($customID) ) {
	if ( $customID =~ /^(\+LPS-|45S-)/ ) {
	    $hits{'äänilevy'} = 1;
	}
	if ( $customID =~ /^(CD-|CDY-)/ ) {
	    $hits{'CD-äänilevy'} = 1;
	}
    }

    if ( $is_sacd ) {
	$hits{'CD-äänilevy'} = 1;
    }

    #my $extent_type_as_per_descriptions = &descriptions2physical_description($description_ref);
    
    if ( defined($physical_description) ) {
	$hits{$physical_description} = 1;	
    }
    
    if ( tempo_is_electronic_resource($customID, $is_sacd) ) {
	# Verkkoaineisto is an (un)educated guess at best.
	if ( !defined($physical_description) ) {
	    $hits{'verkkoaineisto'} = 1;
	}
    }

    my @extent_types = sort keys %hits;
    if ( scalar(@extent_types) > 1 ) {
	print STDERR "ERROR\tReject record\tReason: multiple extent types: ", join("\n", @extent_types), "\n";
	&add_REP_skip($marc_record_ref);
    }

    if ( scalar(@extent_types) == 1 ) {
	return $extent_types[0];
    }

    
    print STDERR "ERROR\tUnable to create field 300\n";
    if ( defined($customID) ) {
	print STDERR " CustomID='$customID'\n";
    }
    return undef;
}



sub extract_field_006($$$$) {
    my ( $marc_record_ref, $customID, $is_sacd, $tempo_record_id ) = @_;

    # As per TM 2022-08-19:
    if ( &tempo_is_electronic_resource($customID, $is_sacd) ) {
	# MELINDA-8090:
	# Sometimes we know that DIGI material comes from a CD.
	# Thus we skip adding 006.
	my $f007 = ${$marc_record_ref}->get_first_matching_field('007');
	
	if ( defined($f007) && $f007->{content} =~ /^s/ ) {
	    # Don't add 006...
	    return;
	}

	# Add field 006:
	my $content = 'm|||||o||h||||||||';
	add_marc_field($marc_record_ref, '006', $content);	
	$field006{$tempo_record_id} = $content; # Cache me
    }
}

sub extract_field_007($$$$$$$) {
    my ( $tempo_dataP, $marc_record_ref, $tempo_record_id, $customID, $is_sacd, $tempo_title, $physical_description ) = @_;
    my $content = custom_id2f007($customID, $tempo_dataP, $is_sacd, $tempo_title, $marc_record_ref);

    # if ( defined($content) ) { print STDERR "Custom ID -based 007: $content\n"; }
    if ( !defined($content) ) {
	# As said above SACD information is sometimes found.
	if ( $is_sacd ) {
	    $content = $default_CD;
	    # if ( defined($content) ) { print STDERR "SACD -based 007: $content\n"; }
	}
    }


    if ( defined($physical_description) ) {
	my $content2 = &physical_description_to_007($physical_description, $marc_record_ref);
	# Override CustomID=DIGI-based value: 
	if ( defined($content2) && ( !defined($content) || $content eq $default007c ) ) {
	    $content = $content2;
	    #if ( defined($content) ) { print STDERR "Physical description based 007: $content\n"; }
	}
	elsif ( !defined($content2) || $content eq $content2 ) {
	    # do nothing
	}
	else {
	    print STDERR "ERROR\tReject record\tReason: DESC '$physical_description'/'$default_CD' vs '$content'\n";
	    &add_REP_skip($marc_record_ref);
	}
    }
    

    if ( !defined($content) ) {
	print STDERR "WARNING\tResort to default 007\n";
	$content = $default007;
    }

    add_marc_field($marc_record_ref, '007', $content);
    $field007{$tempo_record_id} = $content; # Cache me
}

#sub media_nom2ptv($) { # convert nominative case to partitive case
#    my $nom = shift;
#    if ( $nom =~ s/levy$/levyä/ ) {
#	return $nom;
#    }
#    if ( $nom =~ s/kasetti$/kasettia/ ) {
#	return $nom;
#    }
#    die($nom);
#}



sub extract_field_300($$$$$$$) {
    my ( $tempo_dataP, $marc_record_ref, $customID, $is_sacd, $tempo_record_id, $physical_description, $media_as_per_title ) = @_;

    my $f300a_base = custom_id2physical_description($customID, $tempo_dataP, $is_sacd, $physical_description, $marc_record_ref);

    if ( !defined($f300a_base) ) {
	if ( defined($media_as_per_title) ) {
	    # TODO: Use $media_as_per_title information!
	    print STDERR "ERROR\tReject record\tReason: use '$media_as_per_title' for field 300\n";
	    &add_REP_skip($marc_record_ref);
	} 
	return undef;
    }

    $f300a_base = "1 $f300a_base";
    if ( defined($media_as_per_title) ) {
	if ( $f300a_base eq "1 CD-äänilevy" && $media_as_per_title =~ /^\d+ CD-äänilevyä/ ) {
	    $f300a_base = $media_as_per_title;
	}
	else {
	    print STDERR "ERROR\tReject record\tReason: conflicting field 300 data: $f300a_base vs $media_as_per_title\n";
	    &add_REP_skip($marc_record_ref);
	}
    }

    add_marc_field($marc_record_ref, '300', "  \x1Fa$f300a_base");
    $h773{$tempo_record_id} = $f300a_base;

}


sub extract_field_344($) {
    my ( $marc_recordP ) = @_;
    my $f007 = ${$marc_recordP}->get_first_matching_field_content('007');
    if ( !defined($f007) ) {
	print STDERR "extract_field_344(): No 007 field found!\n";
	return undef;
    }
    if ( $f007 =~ /^s..b/ ) {
	return add_marc_field($marc_recordP, '344', "  \x1Fc33 1/3 kierr./min");
    }
    if ( $f007 =~ /^s..c/ ) {
	return add_marc_field($marc_recordP, '344', "  \x1Fc45 kierr./min");
    }
    if ( $f007 =~ /^s..d/ ) {
	return add_marc_field($marc_recordP, '344', "  \x1Fc78 kierr./min");
    }
    return undef;
}


our %normalized_countries = (
    'Englanti (ja Kanaalin ym. saaret; Iso-Britannian valtiollinen koodi)' => 'Englanti', 
    # Ignore Northern Ireland?
    'Irlanti (tasavalta ja erittelemätön saarialue)' => 'Irlanti',
    'Iso-Britannia (UK)'           => 'Iso-Britannia',
    'Saksan liittotasavalta (BRD)' => 'Saksan liittotasavalta',
    'Venäjä (myös nykyisen Venäjän federaation valtiollinen koodi)' => 'Venäjä',
    'Yhdysvallat (USA)'            => 'Yhdysvallat'
);

sub normalize_location($) {
    my $location = shift;
    if ( defined($normalized_countries{$location}) ) {
	return $normalized_countries{$location};
    }
    if ( $location =~ /^.?Venäjä/ ) { return 'Venäjä'; }

    # SUOMI => Suomi
    my $tmp = &tempo_ucfirst_lcrest($location);
    if ( $tmp ne $location ) {
	if ( new_label2ids($tmp, 'yso-paikat', 'fin', 'pref') ) {
	    print STDERR "LOC: $location => $tmp!\n";
	    return $tmp;
	}
    }
    
    return $location;
}


our %country2code_hash = (
    'Englanti' => 'xxk',
    'Etelä-Korea' => 'ko ',
    'Iso-Britannia' => 'xxk',
    'Italia' => 'it ',
    'Itävalta' => 'au ',
    'Keski-Suomi' => 'fi ',
    'Latvia' => 'lv ',
    'Liettua' => 'li ',
    'Norja' => 'no ',
    'Ranska' => 'fr ',
    'Ruotsi' => 'sw ',
    'Saksan liittotasavalta' => 'gw ',
    'Suomi' => 'fi ', 'SUOMI' => 'fi ',
    'Sveitsi' => 'sz ',
    'Tanska' => 'dk ',
    'Venäjä' => 'ru ',
    'Yhdysvallat' => 'xxu',
);

sub keyvals2vals {
    if ( $#_ == -1 ) { return (); }
    return map { s/^.*? = '//; s/'$//; return $_; } @_;
}

sub keyvals2unique_vals {
    return uniq(&keyvals2vals(@_));
}








sub get_label($$$) {
    my ( $head, $arr_ref, $marc_record_ref ) = @_;
    my $label = undef;
    my $curr_prefix = "/$head/master_ownerships";
    my $index = 0;
    my @labels = keyvals2vals(extract_keys($curr_prefix."[$index]/label/label_name", $arr_ref));

    if ( scalar(@labels) > 1 ) { # Not seen yet
	print STDERR "ERROR\tReject record\tReason: multiple label_names\n";
	&add_REP_skip($marc_record_ref);
    }

    @labels = grep { $_ ne 'Ei levymerkkiä' } @labels;

    if ( $#labels == -1 ) { return undef; }

    if ( $#labels > 0 ) {
	print STDERR "WARNING! Multiple labels, return just the first one:\n ", join("\n ", @labels), "\n";
    }
    
    return $labels[0]; # should we return an array?
}




sub process_performer_note($$$$$) {
    die();
    # Re-implemented in tempo_artists_ownerships.pm.
    # Remove this sub() eventually.
    my ( $prefix, $tempo_dataP, $marc_record_ref, $additional_musicians, $field_511_content_ref ) = @_;
    my $prefix2 = "/$prefix/artists_master_ownerships";
    my @results = grep { index($_, $prefix2) == 0 } @{$tempo_dataP}; # non-desctructive

    my @name;
    my @instrument;

    my $skip_nimeamaton = 0;

    my $yhtye = undef;
    for ( my $i=0; $i <= $#results; $i++ ) {
	my $line = $results[$i];

	if ( $line =~ /^\Q$prefix2\E\[(\d+)\]\/artist\/full_name = '(.*)'$/ ) {
	    my $index = $1;
	    my $name = $2;
	    if ( not_really_a_name($name) ) { # $name eq 'Nimeämätön' ) {
		$skip_nimeamaton = 1;
		next;
	    }

	    $skip_nimeamaton = 0;
	    $name =~ s/ \(.*\)$//; # remove tempo tarke etc.
	    if ( defined($name[$index]) ) {
		print STDERR "ERROR\tReject record\tReason: performer note issue #1\n";
		&add_REP_skip($marc_record_ref);
	    }
	    $name[$index] = $name;

	}
	elsif ( $line =~ /^\Q$prefix2\E\[(\d+)\]\/instruments\[\d+\]\/key = '(.*)'$/ ) {
	    if ( !$skip_nimeamaton ) {
		my $index = $1;
		my $instrument = $2;
	    
		$instrument = normalize_instrument($instrument, $marc_record_ref);

		if ( $instrument ) { # will be stored in marc field 511
		    if ( $instrument =~ /yhtye$/ ) {
			if ( defined($yhtye) ) {
			    if ( $yhtye eq $instrument ||
				 $instrument eq 'yhtye' ) {
				# do nothing
			    }
			    else {
				print STDERR "ERROR\tReject record\tReason: performer note issue #2: $yhtye vs $instrument\n";
				&add_REP_skip($marc_record_ref);
			    }
			}
			else {
			    $yhtye = $instrument;
			}
		    }
		    elsif ( !defined($instrument[$index]) ) {
			$instrument[$index] = $instrument;
		    }
		    else {
			if ( $instrument ne 'ym.' ) {
			    $instrument[$index] .= ', '.$instrument;
			}
			else {
			    $instrument[$index] .= ' '.$instrument;
			}
		    }
		}
	    }
	}
	elsif ( $line =~ /rights_type/ ||
		$line =~ /(artist|birth_year|instruments\[\d+\])\/(created_at|_id|ingestion_id|locale|updated_at) =/ ) {
	    # skip warnings
	}
	else {
	    print STDERR "WARNING\t511 creation: skip '$line'\n";
	}

    }
    if ( scalar(@name) < scalar(@instrument) ) {
	print STDERR "ERROR\tReject record\tReason: performer note issue #3: N name vs N instrument\n";
	&add_REP_skip($marc_record_ref);
    }
    my $f511 = '';
    for ( my $i=0; $i < scalar(@name); $i++ ) {
	if ( defined($name[$i]) && $name[$i] ne 'Nimeämätön' ) {
	    $f511 .= $name[$i];
	    if ( defined($instrument[$i]) ) {
		$f511 .= " (".$instrument[$i].")";
	    }
	    if ( $i < $#name ) { $f511 .= ", "; }
	}
    }


    # Handle additional musicians
    if ( defined($additional_musicians) ) {
	if ( length($f511) > 0 ) {
	    $f511 .= ', ' . $additional_musicians;
	}
	else {
	    $f511 = $additional_musicians;
	}
    }

    if ( length($f511) == 0 ) {
	return;
    }

    if ( $yhtye ) {
	$f511 .= ', ' . $yhtye;
    }

    my $content = "0 \x1Fa$f511.";

    if ( ${$field_511_content_ref} ) {
	# We have an existing data for field 511 as well. Merge them? Skip this?
	# (Band name comes from here, and members from elsewhere)

	# Append to the existing 511 (condidition performs the change...):
	if ( ${$field_511_content_ref} =~ s/\x1Fa(Jäsenet|\S+ jäsenet):/\x1Fa$f511:/ ) {

	    return;
	}

	# The two 511 fields are logically separate or sumthing... Keep both:
	print STDERR "MULTI-511 ERROR/WARNING #1 for $f511:\n  '", ${$field_511_content_ref}, "'\n  '$content'\n";

	# Fallback: keep ${$field_511_content_ref} as it was,
	# and add this field as a separate field:
	add_marc_field($marc_record_ref, '511', $content);	    
    }
    else {
	${$field_511_content_ref} = $content;
    }

}
    





sub is_nld_auth($) {
    my $auth_record = shift;
    if ( $auth_record->containsSubfieldWithValue('040', 'a', 'FI-NLD') ||
	 $auth_record->containsSubfieldWithValue('040', 'd', 'FI-NLD') ) {
	return 1;
    }
    return 0;
}






sub country2code($$) {
    my ( $country, $marc_record_ref ) = @_;
    $country = &normalize_location($country);
    if ( defined($country2code_hash{$country}) ) {
	return $country2code_hash{$country};
    }
    my $msg = "WARNING\tUnable to map country '$country' to 008/15-17 code.";

    print STDERR "ERROR\tReject record\tReason: $msg\n";
    &add_REP_skip($marc_record_ref);

    return '|||'; # default, might be 'fi ' as well...
}


# These come from descpiptions and go to 041$g ("esittelylehtinen englanniksi")
my %language2code = ( 'englanniksi' => 'eng',
		      'latviaksi' => 'lav',
		      'puolaksi' => 'pol',
		      'ranskaksi' => 'fre',
		      'ruotsiksi' => 'swe',
		      'saksaksi' => 'ger',
		      'suomeksi' => 'fin',
		      'tanskaksi' => 'dan',
		      'venäjäksi' => 'rus' );


# http://marc21.kansalliskirjasto.fi/kielet.htm
my %lang2marc_lookup = (
    afrikaans => 'afr',
    albania => 'alb',
    amhara => 'amh',
    arabia => 'ara',
    armenia => 'arm',
    azeri => 'aze',
    baski => 'baq',
    bosnia => 'bos',
    bulgaria => 'bul',
    eesti => 'est',
    EN => 'eng',
    ENG => 'eng',
    eglanti => 'eng', # Fono2020Q3 typo
    englanti => 'eng',
    espanja => 'spa',
    'eskimokieli: grönlanti' => 'kal', # kalaallisut, grönlanti
    gaeli => 'gla', # 2017Q3: Yle koodannut iirin pieleen
    georgia => 'geo',
    heprea => 'heb',
    hindi => 'hin',
    iiri => 'gle',
    indonesia => 'ind',
    instrumental => 'zxx',
    islanti => 'ice',
    IT => 'ita',
    italia => 'ita',
    japani => 'jpn',
    jiddish => 'yid',
    karjala => 'krl',
    kiina => 'chi',
    kirkkoslaavi => 'chu',
    korea => 'kor',
    kreikka => 'gre',
    kroatia => 'hrv',
    LAT => 'lat',
    latina => 'lat',
    liettua => 'lit',
    malta => 'mlt',
    nenetsi => 'fiu', # yleiskoodi suom.-ugr.
    norja => 'nor',
    puola => 'pol',
    persia => 'per',
    portugali => 'por',
    ranska => 'fre',
    romanikieli => 'rom',
    romania => 'rum',
    RU => 'swe',
    ruotsi => 'swe',
    saame => 'smi',
    SA => 'ger',
    SAK => 'ger',
    saksa => 'ger',
    sanaton => 'zxx',
    sechuana => 'tsn', # Tswana
    serbia => 'srp',
    sloveeni => 'slv',
    SU => 'fin',
    suahili => 'swa',
    suomi => 'fin',
    SUOMI => 'fin',
    tamasek => 'tmh',
    tanska => 'dan',
    tshekki => 'cze', # 'ces',
    tunnistamaton => 'und',
    turkki => 'tur',
    'udmurtti' => 'udm', 
    ukraina => 'ukr',
    unkari => 'hun',
    urdu => 'urd',
    valekieli => 'zxx',
    'valkovenäjä' => 'bel',
    VEN => 'rus',
    'venäjä' => 'rus',
    viro => 'est',
    wolof => 'wol',
    );

# add lowercase keys too as an experiment; this should be optimised, preferably by defining lowercase keys
%lang2marc_lookup = (%lang2marc_lookup, map {(tempo_lc($_), $lang2marc_lookup{$_})} keys %lang2marc_lookup);

sub lang_to_marc($$) {
    # Copypasted directly from fono_to_marc.pl
    my ( $langFono, $marc_record_ref ) = @_;

    if ( $langFono =~ /^Afrikka: gun$/ ) { return 'guw'; } # ISO-639-3
    
    if ( $langFono eq "Australia: tunnistamaton" ) { return 'aus'; }
    if ( $langFono =~  /^saame: / ) {
	if ( $langFono =~  /^saame: inarinsaame$/ ) {
	    return 'smn';
	}
	if ( $langFono =~  /^saame: kiltinänsaame$/ ) {
	    return 'sjd';
	}
	if ( $langFono =~  /^saame: koltansaame$/ ) {
	    return 'sms';
	}
	if ( $langFono =~  /^saame: pohjoissaame$/ ) {
	    return 'sme';
	}

	print STDERR "ERROR\tReject record\tReason: unhandled sami variant '$langFono'\n";
	&add_REP_skip($marc_record_ref);
	return 'smi';
    }

    if ( $langFono eq "englanti: keskienglanti" ) { return 'enm'; }
    if ( $langFono eq "englanti: muinaisenglanti" ) { return 'ang'; }
    # Rumat hackit (informaatiota katoaa, mutta voi voi):
    $langFono =~ s/^(?:Afrikka|Australia|Intia|valekieli): ([a-z])/$1/s;
    $langFono =~ s/(.): murre$/$1/s;
    $langFono =~ s/ \/\d+$//; 
  
    # Nähty mm. "200ruotsi: murre: Pohjanmaa"
    $langFono =~ s/(.): murre: \S+(n murre)?$/$1/s;
    $langFono =~ s/(.): slangi$/$1/s;
    $langFono =~ s/(.): ulkomaalainen korostus$/$1/s;

    $langFono =~ s/^([a-z]+) \/[a-z]+$/$1/; # 'suomi /takaperin' 20181015
    
    if ( $langFono !~ /\S/ ) { # happens in 2018Q2
	return '';
    }
    
    if ( defined($lang2marc_lookup{$langFono}) ) {
	return $lang2marc_lookup{$langFono};
    }
    if ( defined($lang2marc_lookup{lc($langFono)}) ) {
	return $lang2marc_lookup{lc($langFono)};
    }
    
    if ( $langFono =~ s/\?$// ) {
	return &lang_to_marc($langFono, $marc_record_ref);
    }
    
    print STDERR "Tuntematon kieli: '$langFono'\n";
    # muotoa "kieli?" on esiintynyt 2017Q3:sta alkaen...
    if ( $langFono eq 'Brasilia: tunnistamaton' ||
	 $langFono eq 'intiaanikieli' ||
	 $langFono eq 'kreoli' ||
	 $langFono eq 'slangi' ||
	 $langFono eq 'ym' ) {
	return '';
    }

    print STDERR "ERROR\tReject record\tReason: unhandled language '$langFono'\n";
    &add_REP_skip($marc_record_ref);    
    return '';
}



sub duration2hhmmss($) {
    my $duration = shift;
    my $hh = 0;
    my $mm = 0;
    my $ss = 0;
    # 626b76d7333da90039eb5d70 has duration 195 (without milliseconds)
    if ( $duration =~ s/^(\d+)(\.\d+)?$/$1/ ) { # remove milliseconds etc
	$ss = $duration;
	if ( $ss >= 60 ) {
	    $mm = int($ss/60);
	    $ss = $ss % 60;
	}
	if ( $mm >= 60 ) {
	    $hh = int($mm/60);
	    $mm = $mm % 60;
	}
    }
    else {
	return '';
    }

    if ( $hh > 99 ) { return ''; } # Hour range is 00...99 in field 306$a...
	
    $hh = sprintf("%02d", $hh);
    $mm = sprintf("%02d", $mm);
    $ss = sprintf("%02d", $ss);
    return "$hh$mm$ss";
}

sub uniq {
    # based on https://perldoc.perl.org/perlfaq4#How-can-I-remove-duplicate-elements-from-a-list-or-array%3f
    my %seen;
    grep !$seen{$_}++, @_; # returns array of seen values
}

sub iso639_3_to_marc_language_code($) {
    my $code = shift;
    if ( $code eq 'sjd' ) { return 'smi'; }
    if ( $code eq 'guw' ) { return 'nic'; }
    if ( $code =~ /^$iso639_3_regexp$/ ) { die(); } # sanity check
    return $code
}

sub languages_to_008_35_37($$$) {
    my ( $languages_ref, $ensembles_ref, $marc_record_ref ) = @_;
    my @languages = @{$languages_ref};

    if ( scalar(@languages) == 0 ) {
	# TM 2022-08-17: "Instrumentaaliesityksissä koodiksi tallennetaan "zxx".
	# Tieto löytyy Tempo-tietueen kohdasta custom: ensemble: 0: "KI instrumentaaliesitys"
	if ( grep(/^KI\b/, @{$ensembles_ref}) ) {
	    return 'zxx';
	}
	return '|||';
    }

    if ( scalar(@languages) > 2 ) { return 'mul'; } # 3+ languages mean multilang


    if ( $languages[0] =~ /^$iso639_3_regexp$/ ) {
	# Language might not have an official MARC language code.
	# However, it might belong to a language family that has such a code.
	return iso639_3_to_marc_language_code($languages[0]);
    }

    # "Jos kielikoodia ei löydy virallisten MARC-kielikoodien
    # joukosta, mutta kielelle kuitenkin löytyy (ISO-)koodi, niin
    # 008-kentän merkkipaikkaan 35-37 voidaan merkitä koodi '|||'
    # (ei koodattu) ja 041-kenttään tarkempi koodi.
    
    if ( length($languages[0]) != 3 ) {
	print STDERR "ERROR\tReject record\tReason: lang length != 3 '", $languages[0], "'\n";
	&add_REP_skip($marc_record_ref);
	return '|||';
    }
    return $languages[0];
}


sub get_datestring() {
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
  $year -= 100;
  $mon++;
  # if length is 1, add leading zero
  if (length($mday) == 1) {
    $mday = "0$mday";
  }
  # if length is 1, add leading zero
  if (length($mon) == 1) {
    $mon = "0$mon";
  }
  return  "$year$mon$mday";
}



sub init_config() {
    # Read configuration variables from ARGV, store them to %config
    # and remove them from ARGV.
    for ( my $i=$#ARGV; $i >= 0; $i-- ) { # using splice() is simpler when starting from the end
	my $command_line_argument = $ARGV[$i];
	if ( $command_line_argument =~ /^\-\-.*/ ) {
	    if ( $command_line_argument =~ /^--input-directory=(.*)$/ ) {
		$input_directory = $1;
	    }
	    elsif ( $command_line_argument =~ /^--output-directory=(.*)$/ ) {
		$output_directory = $1;
	    }

	    elsif ( $command_line_argument =~ /^--error-directory=(.*)$/ ) {
		$error_directory = $1;
	    }
	    else {
		print STDERR "WARNING\tIgnore option '$command_line_argument'\n";
	    }
	    splice(@ARGV, $i, 1);	    
	}

    }
}


sub file2string($) {
    my $filename = shift;
    my $FH;
    my $string = '';
    open($FH, "<$filename") or die($!);
    while ( my $line = <$FH> ) {
	$string .= $line;
    }
    close($FH);
    return $string;
}

sub recursively_process_tempo($$);
sub recursively_process_tempo($$) {
    my ( $jsonP, $path ) = @_;
    my $ref = ref($jsonP);
    my $output = '';

    if ( $ref eq '' ) {
	if ( !defined($jsonP) ) {
	    #print STDERR "PROCESSING $path = NULL\n";
	    $output .= $path . " = NULL\n";
	}
	else {
	    #print STDERR "PROCESSING $path = '$jsonP'\n";
	    $output .= $path . " = '$jsonP'\n";
	}
    }
    elsif ( $ref eq 'JSON::PP::Boolean' ) {
	if ( $jsonP ) {
	    $output .= $path . " = true\n";
	    #print STDERR "PROCESSING $path = true\n";
	}
	else {
	    $output .= $path . " = false\n";
	    #print STDERR "PROCESSING $path = false\n";
	}
    }
    else {
	#print STDERR "PROCESSING $path... ($ref)\n";
	if ( $ref eq 'ARRAY' ) {
	    for ( my $i=0; $i < @$jsonP; $i++ ) {
		$output .= recursively_process_tempo($$jsonP[$i], $path."[$i]");
	    }
	}
	elsif ( $ref eq 'HASH' ) {
	    my @keys = sort keys(%{$jsonP});
	    #print STDERR "$path : $ref contains ", ($#keys+1), " key(s).\n";
	    for ( my $i=0; $i <= $#keys; $i++ ) {
		my $curr_key = $keys[$i];
		$output .= recursively_process_tempo($$jsonP{$curr_key}, $path.'/'.$curr_key);
	    }
	}
	else {
	    die("TODO: Support REF type '$ref'");
	}
    }
    return $output;
}


sub is_classical_music($$) {
    my ( $tempo_dataP, $prefix ) = @_;
    # Album: hosts
    # Comps: data
    # Songs in a multipart: /album/tracks[N]/custom/...
    if ( grep(/^\/$prefix\/custom\/genre\[0\] = 'L1($|[^0-9])/, @{$tempo_dataP}) ) {
	return 1;
    }
    return 0;
}


sub genre_to_008_18_19($) {
    my ( $genre ) = @_;

    if ( $genre eq 'L1B' ) { return 'pt'; } 
    if ( $genre eq 'L1C' ) { return 'sg'; }
    if ( $genre =~ /^L2(A|B|BB|L|N)?$/ ) { return 'gm'; }
    if ( $genre =~ /^L3[ALUX]?$/ ) { return 'fm'; }
    if ( $genre =~ /^L4(A|AA|L)?$/ ) { return 'rc'; }
    if ( $genre eq 'L5A' || $genre eq 'L5AA' ) { return 'jz'; }
    if ( $genre eq 'L5B' ) { return 'bl'; }
    if ( $genre =~ /^L6[CDLVX]?$/ ) { return 'pp'; }
    if ( $genre =~ /^L6B$/ ) { return 'cy'; }
    if ( $genre =~ /^L6T$/ ) { return 'df'; }
    if ( $genre =~ /^L9E$/ ) { return 'mp'; }

    return '||';
}

sub map_genre_to_field_008($$) {
    my ( $genre, $marc_record_ref ) = @_;
    if ( !defined($genre) ) {
	# Complain?
	return;
    }
    if ( $genre =~ /\/genre\[\d+\] = '(.*)'$/ ) {
	$genre = $1;
    }
    
    # Pretty much aped from Ye Olde Fono Conversion (Fono field 170)

    # fono.fi has some info on these:
    # http://www.fono.fi/Dokumentti.aspx?kappale=lapsi&culture=fi&sort=3&ID=36332ba3-065e-4993-a396-0f1ad44ec67a
    my $f008 = ${$marc_record_ref}->get_first_matching_field('008');
    if ( !defined($f008) ) {
	print STDERR "ERROR\tReject record\tReason:no 008 to map genre info '$genre'\n";
	&add_REP_skip($marc_record_ref);
	return;
    }

    
    if ( $genre =~ /^(L(1[ABCL]|2(A|B|BB|L|N)?|3[ALUX]?|4(A|AA|L)?|5(A|AA|B|L)|6[BCDKTVX]|L9E))\b/ ) {
	$genre = $1;



	if ( $genre eq 'L1A' ) {
	    add_marc_field($marc_record_ref, '084', "  \x1Fa78.35\x1F2ykl");
	}	
	elsif ( $genre eq 'L1C' ) {
	    add_marc_field($marc_record_ref, '084', "  \x1Fa78.32\x1F2ykl");
	}

	my $f008_18 = &genre_to_008_18_19($genre);
	
	if ( length($f008_18) != 2 ) { # Sanity check:
	    print STDERR "ERROR\tReject record\tReason: size!=2 '$f008_18'\n";
	    &add_REP_skip($marc_record_ref);
	    $f008_18 = '||';
	}
	
	${$marc_record_ref}->update_controlfield_character_position('008', 18, $f008_18);

	if ($genre =~ /^L[123456]L$/ ) {
	    ${$marc_record_ref}->update_controlfield_character_position('008', 22, 'j');
	}
    }
    else {
	print STDERR "WARNING: Unable to map genre '$genre' to 008/18-19!\n";
    }
}





sub field_has_name($$$$) {
    my ( $recordP, $tag, $subfield_code, $value ) = @_;
    my @data = ${$recordP}->get_all_matching_subfields_without_punctuation($tag, $subfield_code);
    print STDERR "$tag\$$subfield_code got ", ($#data+1), " hits whilst matching against '$value'\n";
    # Compare:
    @data = grep { $_ eq $value } @data;
    print STDERR "FINAL $tag\$$subfield_code has ", ($#data+1), " values left\n";
    return $#data+1;
}
    

sub remove_noise_from_tempo($$) {
    my ( $prefix, $tempo_dataP ) =@_;

    # This list has been defined with component part in mind...
    my @remove_regexps = ( "= ''\$", '= NULL$',
			   "^/$prefix/artists_publishing_ownerships\\[\\d+\\]/rights_type/names.*",
			   "^/$prefix/artists_master_ownerships\\[\\d+\\]/instruments\\[\\d+\\]/names.*",
			   "^/$prefix/artists_master_ownerships\\[\\d+\\]/rights_type/names.*",
			   "^/$prefix/agents\\[\\d+\\].*",
			   "^/$prefix/audiofile",
			   '_mp3_key = ',
			   '/territories\[\d+\] = '."'WW'",
			   "\/tenant = ",
			   "rights_type\/names", 
			   'image/is_converted',
			   "^/$prefix/showcase\\[\\d+\\].*",
			   "^/$prefix/version/names\\[\\d+\\].*"
	);
    for ( my $i=0; $i <= $#remove_regexps; $i++ ) {
	my $curr_regexp = $remove_regexps[$i];
	@{$tempo_dataP} = grep(! /$curr_regexp/, @{$tempo_dataP});
    }
    # Remove empty data:
    @{$tempo_dataP} = grep(! /( = ''|__v = '0')$/, @{$tempo_dataP});
}


sub json2tempo_data_string_array($) {
    my $json = shift;
    # Seems that without "use bytes" are umlauts get corrupted within
    # from_json() perl module
    use bytes;
    my $json_string = from_json($json); #decode_json($tempo_as_string); # corrupts input
    no bytes;
    my $result_string = &recursively_process_tempo($json_string, '');
    #print STDERR $result_string; die();
    
    my @tempo_data = split(/\n/, $result_string);
    return @tempo_data;
}


sub get_languages($$$) {
    my ( $prefix, $tempo_dataP, $marc_record_ref ) = @_;
    my $curr_key = "/$prefix/custom/languages";
    my @languages = extract_keys($curr_key, $tempo_dataP);
    
    # Used at least by 008/35-37 (OK), 041$a (TODO), 240 IND2 and 245 IND2 (TODO)
    if ( $#languages == -1 ) {
	print STDERR "WARNING\tDetected language(s): NONE\n";
    }
    else {
	@languages = keyvals2vals(@languages);
	#print STDERR "LANGUAGES:\n", join("\n", @languages);
	@languages = map { lang_to_marc($_, $marc_record_ref) } @languages;
	@languages = uniq(@languages); # remove duplicates
	@languages = grep(/\S/i, @languages); # remove empty
	if ( $debug ) {
	    print STDERR "DEBUG\tDetected language(s): ", join(", ", @languages), "\n";
	}

    }
    return @languages;
}


    
sub process_composition_country($$$) {
    my ( $prefix, $tempo_dataP, $marc_recordP) = @_;
    my ( $original_composition_country ) = keyvals2vals(extract_keys("/$prefix/custom/composition_country", $tempo_dataP)); # current unused, just remove
    if ( defined($original_composition_country) && $original_composition_country ne '' ) {
	
	my $composition_country = normalize_location($original_composition_country);
	
	my $yso_paikat_id =  new_pref_label2unambiguous_id($composition_country, 'yso-paikat', 'fin');
	my $entry = "  \x1Fg".$composition_country;
	if ( $yso_paikat_id ) {
	    $entry .= "\x1F2yso/fin\x1F0http:\/\/www.yso.fi\/onto\/yso\/".$yso_paikat_id;
	    add_marc_field($marc_recordP, '370', $entry);
	}
	else {
	    print STDERR "WARNING\tComposition country '$composition_country' not found in yso-paikat. Using field 500 instead of 370\n";
	    add_marc_field($marc_recordP, '500', "  \x1FaSävellysmaa Tempon mukaan: $original_composition_country.");
	}

    }
}

sub process_composition_year($$$$) {
    my ( $prefix, $tempo_dataP, $marc_recordP, $is_host) = @_;
    my ( $composition_year ) = keyvals2vals(extract_keys("/$prefix/custom/composition_year", $tempo_dataP)); # current unused, just remove
    my $ind1 = $is_host ? ' ' : '1';
    if ( defined($composition_year) && $composition_year ne '' ) {
	my $orig_val = $composition_year;
	if ( $composition_year =~ /^(1[0-9][0-9][0-9]|20[012][0-9])$/ ||
	     $composition_year =~ s/^(1[0-9][0-9][0-9]|20[012][0-9]) (uud|julk)$/$1/ ) { # uudistettu, julkaistu
	    add_marc_field($marc_recordP, '046', "${ind1} \x1Fk${composition_year}");
	}
	# $2 edtf: 
	elsif ( $composition_year =~ s/^($yyyy_regexp) ?noin$/$1~/ ||
		$composition_year =~ s/^([1-9]|1[0-9]|20)00-luku$/${1}XX/ ||
		$composition_year =~ s/^((?:[1-9]|1[0-9]|20)[0-9])0-luku$/${1}X/ ||
		# open start time interval:
		$composition_year =~ s/^((?:[1-9]|1[0-9]|20)[0-9][0-9]) (valm|viim)$/..\/${1}/ ) {
	    print STDERR "WARNING\t046\$2 edtf used with \$k '${composition_year}' (derived from $orig_val)!\n";
	    add_marc_field($marc_recordP, '046', "${ind1} \x1Fk${composition_year}\x1F2edtf");
	}
	elsif ( $composition_year =~ /^($yyyy_regexp) ([a-z]+)$/ ) {
	    print STDERR "WARNING\t046 CREATION SKIPPED. NOT SURE HOW TO CONVERT '$composition_year'!\n";
	}
	else { # menee 045:een?
	    die($composition_year);
	}
    }
}


sub add_languages_to_041g($$) {
    my ( $marc_record_ref, $text ) = @_;

    my $f041 = ${$marc_record_ref}->get_first_matching_field('041');
		
    my @words = split(/\s+/, $text);
    foreach my $word ( @words ) {
	$word =~ s/[^\p{PosixAlnum}]$//;
	if ( $word =~ /^(.*)ksi$/ ) {
	    my $lang_nom_cand = $1;
	    my $lang_code = undef;
	    if ( defined($language2code{$word}) ) { # Languages in translative
		$lang_code = $language2code{$word};
	    }
	    else { # Use the normal version as fallback:
		$lang_code = &lang_to_marc($lang_nom_cand);
	    }

	    if ( $lang_code ) {
		if ( !defined($f041) ) {
		    $f041 = add_marc_field($marc_record_ref, '041', "  \x1Fg${lang_code}");
		}
		else {
		    print STDERR "ADD SUBFIELD ‡g $lang_code TO 041.\n";
		    unless ( $f041->{content} =~ s/(.*\x1Fg[^\x1F]+)/$1\x1Fg$lang_code/ || # as last $g
			     $f041->{content} =~ s/(.*\x1F[h-z])/\x1Fg$lang_code$1/ ) { # before $h-z
			$f041->{content} .= "\x1Fg$lang_code";
		    }
		}
	    }
	    else {
		&mark_record_as_rejected($marc_record_ref, "Map '$word' to a language code");
	    }
	}
    }

}


sub add_subfield_300e($) {
    my ( $marc_record_ref ) = @_;
    my $f300 = ${$marc_record_ref}->get_first_matching_field('300');
    if ( !defined($f300) ) {
	# unexpected but we soldier on...
	return;
    }

    if ( index($f300->{content}, "\x1Fa") == -1 ) {
	print STDERR "ERROR\tReject record\tReason: missing 300\$a\n";
	&add_REP_skip($marc_record_ref);
	return;
    }

    if ( index($f300->{content}, "\x1Fe") == -1 ) {
	print STDERR "Field 300: add subfield \$e1 tekstiliite\n";
	$f300->{content} .= " +\x1Fe1 tekstiliite";
	return;
    }

    if ( index($f300->{content}, "\x1Fe1 tekstili") > -1 ) {
	# No need to add the same $e content again
	return;
    }
    # We should not get here...
    print STDERR "ERROR\tReject record\tReason: unhandled 300\$e data\n";
    &add_REP_skip($marc_record_ref);

}

sub process_description2language_notes($$$) {
    my ( $description_ref, $marc_record_ref, $is_host ) = @_;

    if ( !defined(${$description_ref}) ) { return; }
    
    if ( !$is_host ) { return; }
    
    my $n_hits = 0;

    my $esittelylehtinen = "(?:Esittelylehtinen|Esittelylehtinen ja synopsis|Esittelylehtinen ja tekstilehtinen|Libretto|Tekstilehtinen|Tekstilehtinen ja esittelylehtinen|\\S+lehtinen)(?: myös)?";


    # YLE: "Oheistiedot
    #
    # Mikäli äänitteeseen liittyy oheistietoina musiikkiin liittyvät sanat,
    # libretto, musiikkiin tai esittäjiin liittyvää esittelymateriaalia tms.
    #
    # Kaikissa levyissä oletetaan olevan jonkinlainen kansilehtinen.
    # Tätä ei merkitä erikseen.
    # 
    # Esittelylehtinen tarkoittaa, että oheistiedoissa on enemmän tietoa kuin
    # pelkät teosten nimet, tekijät ja esittäjät.
    #
    # Tekstilehtinen tarkoittaa, että oheistiedoissa on mukana teoksen sanoitus.
    #
    # Näitä termejä käytetään, vaikka varsinainen teksti lukisi esim. levyn
    # kansissa eikä irrallisessa vihkosessa. Näin sanoja 'esittelylehtinen' ja
    # 'tekstilehtinen' voi käyttää hakutermeinä.
    #
    # Esittelylehtisen ja tekstilehtisen kieli mainitaan vain, jos se poikkeaa
    # esityskielestä tai jos kieliä on lehtisessä useampia."
    #
    # If one of the above, we add $e 1 tekstiliite (and *never* two).
    # All related language info is stored in 040$g.

    # typo fixes:
    ${$description_ref} =~ s/sittelylehtien /sittelylehtinen /;
    ${$description_ref} = trim_all(${$description_ref});
	
    my $add_300e = 0;
    print STDERR "TEST: '", ${$description_ref}, "'\n";
    while ( ${$description_ref} =~ s/(?:^| )($esittelylehtinen(?: (?:[a-z]|ä)+ksi,)*(?: (?:[a-z]|ä)+ksi ja)? (?:[a-z]|ä)+ksi)(?:\.?$|\. )/ / ) {
	my $text = $1.'.';
	print STDERR "TEST PASS...\n";
	${$description_ref} = trim_all(${$description_ref});
	$n_hits++;
	
	my $content = "  \x1Fa".$text;
	add_marc_field($marc_record_ref, '546', $content);
	# What's the difference between 'esittelylehtinen' and
	# 'tekstilehtinen'
	if ( $text =~ /(esittelylehtinen|libretto|tekstilehtinen)/i ) {
	    $add_300e = 1;
	    add_languages_to_041g($marc_record_ref, $text);
	}
    }
    print STDERR "TEST2: '", ${$description_ref}, "'\n";
	
    if ( ${$description_ref} =~ s/^$esittelylehtinen( esityskielellä)?\.$//i ) {
	$add_300e = 1;
    }
	
    # Try to detect if we didn't process everything...
    if ( ${$description_ref} =~ /$esittelylehtinen/i ) {
	#${$description_ref} =~ /\s/ &&
	#${$description_ref} =~ /(?:esittelylehti|tekstilehti)/i ) {
	print STDERR "ERROR\tReject record\tReason: esittelylehtinen '", ${$description_ref}, "'\n";
	&add_REP_skip($marc_record_ref);
    }
    
    if ( $add_300e ) { # move to a separate_function
	add_subfield_300e($marc_record_ref);
    }

}



sub process_single_description($$$$) {
    my ( $mess, $marc_record_ref, $is_host, $field_511_content_ref ) = @_;

    &description_cleanup(\$mess);
	
    if ( $mess =~ /lueteltu/ ) {
	print STDERR "ERROR\tReject record\tReason:: 511 /lueteltu/ in '$mess'\n";
	&add_REP_skip($marc_record_ref);
    }
    elsif ( $mess =~ /\S/ ) {
	$mess = trim_all($mess);
	#if ( $is_host && $mess =~ /(^|\. )(Esittelylehtinen|Tekstilehtinen) / ) {
	if ( $mess =~ /(^|\. )(Esittelylehtinen|Tekstilehtinen) / ) {
	    if ( $is_host ) {
		# Something to field 300 as well?
		$mess =~ s/([a-z0-9]|å|ä|ö)$/$1./gi;
		add_marc_field($marc_record_ref, '500', "  \x1Fa$mess");
	    }
	}
	elsif ( $is_host ) {
	    # Apparently KS wanted this Sekä: restriction back in
	    # 2016-02-22
	    $mess =~ s/([^\.])$/$1./;
	    if ( $debug ) {
		print STDERR "descriptions => 511\n";
	    }
	    
	    if ( !${$field_511_content_ref} ) {
		${$field_511_content_ref} = "0 \x1Fa$mess";
	    }
	    elsif ( ${$field_511_content_ref} =~ /\x1Fa([^\x1F]+)\.$/ ) {
		my $a = $1;
		if ( index($mess, $a) == 0 ) {
		    # "Ville Laihala" vs "Ville Laihala ja Saattajat": latter wins
		    ${$field_511_content_ref} = "0 \x1Fa$mess";
		}
		else {
		    print STDERR "MULTI-511 #2. Mergable?\n  '", ${$field_511_content_ref}, "'\n  '0 \x1Fa$mess\n";
		    add_marc_field($marc_record_ref, '511', "0 \x1Fa$mess"); # Store this as well
		}
		
	    }
	    else {
		print STDERR "ERROR\tReject record\tReason: 511 issues\n";
		&add_REP_skip($marc_record_ref);
	    }
	    
	}
	elsif ( $mess ) {
	    print STDERR "TODO or SKIP\tProcess description\t'$mess'\n";
	}
    }
}

sub process_description($$$$$) {
    my ( $is_host, $prefix, $tempo_dataP, $marc_record_ref, $description_ref, $field_511_content_ref) = @_;

    if ( !defined(${$description_ref}) || !${$description_ref} ) { return; }

    my $curr_description = ${$description_ref};
    # print STDERR "Curr Desc: '$curr_description'\n";
    my @desc2 = split(/  +/, $curr_description);
    if ( scalar(@desc2) > 1 ) {
	print STDERR "ERROR\tReject record\tReason: multidescription?\n";
	&add_REP_skip($marc_record_ref);
    }

    &process_single_description($desc2[0], $marc_record_ref, $is_host, $field_511_content_ref);

    print STDERR "SINGLE '", ${$field_511_content_ref}, "\n";
}

sub process_duration($$$) {
    my ( $prefix, $tempo_dataP, $marc_record_ref) = @_;
    my $path = "/$prefix/duration";
    my $duration = get_single_entry($path, $tempo_dataP);
    if ( !defined($duration) || !$duration ) {
	print STDERR "No duration found!\n";
	return;
    }
    
    my $hhmmss = duration2hhmmss($duration); 
    # KS 6.5.2016: "Fono-tietueissa tulee nähtävästi joskus pelkkiä nollia
    # 306-kenttään." Korjaus: vaaditaan [1-9]
    if ( defined($hhmmss) && $hhmmss =~ /[1-9]/ && $hhmmss =~ /^[0-9]{6}$/ ) {
	if ( $debug ) {
	    print STDERR "DEBUG\tConvert duration '$duration' to 306\$a '$hhmmss' (key: hhmmss)\n";
	}
	add_marc_field($marc_record_ref, '306', "  \x1Fa".$hhmmss);
    }
    else {
	print STDERR "ERROR\tReject record\tReason: duration '$duration' does not convert to field 306\$a\n";
	&add_REP_skip($marc_record_ref);
    }
}

sub process_language_codes($$) { # add 041
    my ( $languagesP, $marc_recordP ) = @_;
    my @languages = grep(! /^zxx$/, @{$languagesP});
    if ( $#languages == -1 ) { return; }

    @languages = uniq(@languages);
    

    my @f041 = ();

    # A pair is treated differently: both values are put into the same field.
    # However, ISO-639-3 fields can not be in a dual, so use more generic
    # Marc21 language code in the dual and store ISO-639-3 separately.
    if ( $#languages == 1 &&
	 iso639_3_to_marc_language_code($languages[0]) eq $languages[0] &&
	 iso639_3_to_marc_language_code($languages[1]) eq $languages[1] ) {
	# Put the first two elements into 041 as a pair:
	$f041[0] = "  \x1Fd".$languages[0]."\x1Fd".$languages[1];
	# Remove them from language list:
	@languages = ();
    }

    
    # Remaining language codes in @languages are stored as separate
    # 041 fields.
    # First list them:
    my %seen;
    for ( my $i = 0; $i <= $#languages; $i++ ) { # keep the right order
	my $curr_lang = $languages[$i];
	if ( $seen{$curr_lang} ) {
	    next;
	}

	# NB! Alt comes first! Generic 
	my $alt_lang = iso639_3_to_marc_language_code($curr_lang);
	if ( $curr_lang eq $alt_lang ) {
	    # Sami languages still map to generic language group despite
	    # the more specific code being supported by marc as well:
	    # https://www.kiwi.fi/pages/viewpage.action?spaceKey=kumea&title=2022-10-05+ja+2022-10-12+-+yhteismuistio#id-20221005ja20221012yhteismuistio-3)Kysymys:Saamenkielisenaineistonkielimerkinn%C3%A4t,jatkokysymys
	    if ( $curr_lang =~ /^(sjd|sme|smn|sms)$/ ) {
		$alt_lang = 'smi';
	    }
	}
	$seen{$alt_lang} = 1;

	# NB! The standard version of a pair comes first:
	$f041[$#f041+1] = "  \x1Fd$alt_lang";
	if ( $curr_lang ne $alt_lang ) {
	    $f041[$#f041+1] = " 7\x1Fd$curr_lang\x1F2iso639-3";
	    $seen{$curr_lang} = 1;
	}

    }
    # And then add them:
    for ( my $i = 0; $i <= $#f041; $i++ ) {
	add_marc_field($marc_recordP, '041', $f041[$i]);
    }
    
}

sub normalize_genre($) {
    my ( $genre ) = @_;
    $genre = tempo_lc($genre);
    # TODO: We could rename some common terms that are not in slm/fin...
    return $genre;
}


sub genre2slm($$) {
    my ( $genre, $marc_record_ref ) = @_;

    $genre = normalize_genre($genre);
    
    # All entries get their SLM/655 mappings as well:
    my $slm_id =  new_pref_label2unambiguous_id($genre, 'slm', 'fin');
    if ( defined($slm_id) ) {
	add_marc_field($marc_record_ref, '655', " 7\x1Fa".$genre."\x1F2slm/fin\x1F0http:\/\/urn.fi\/URN:NBN:fi:au:slm:$slm_id");
    }
    else {
	# TM 2022-08-19 "[653-kentän] käyttöä pyritään välttämään."
	# add_marc_field($marc_recordP, '653', " 6\x1Fa".$genre);
    }
}    

sub process_genre($$$) {
    my ( $prefix, $tempo_dataP, $marc_record_ref) = @_;
    my $basename = "/$prefix/custom/genre"; # \\[\\d+\\]";
    my $genre_index = 0;
    my $genre;
    while ( ( $genre ) = keyvals2vals(extract_keys($basename."[$genre_index]", $tempo_dataP)) ) {
	print STDERR "GENRE: '$genre'\n";
	# First entry gets mapped to 008:
	if ( $genre_index == 0 ) {
	    &map_genre_to_field_008($genre, $marc_record_ref);
	}
	$genre =~ s/^\S+ //; # Remove L1F etc
	&genre2slm($genre, $marc_record_ref);
	$genre_index += 1;
    }
    
}

sub process_sub_genre($$$) {
    my ( $prefix, $tempo_dataP, $marc_record_ref) = @_;
    my $basename = "/$prefix/custom/sub_genre"; # \\[\\d+\\]";
    my $genre_index = 0;
    my $genre;
    while ( ( $genre ) = keyvals2vals(extract_keys($basename."[$genre_index]", $tempo_dataP)) ) {
	print STDERR "SUBGENRE: '$genre'\n";
	&genre2slm($genre, $marc_record_ref);
	$genre_index += 1;
    }
    ## Currently we have three unhandled cases where genre is not in an array:
    # 629066d8c5799c0029f8c9b5.json:"sub_genre": "rap",
    # 62ff749769a704003ba2aa51.json:"sub_genre": "rap",
    # 63085a7469a704003bae6db6.json:"sub_genre": "rap",
    $genre = get_single_entry($basename, $tempo_dataP);
    if ( $genre ) {
	&genre2slm($genre, $marc_record_ref);
    }
}




sub marc_add_date_and_place_of_an_event_note($$$$$) { # Add field 518:
    my ( $marc_record_ref, $other_information, $date, $place, $tracks ) = @_;
    if ( !defined($date) && !defined($place) ) {
	return;
    }
    
    if ( !defined($other_information) ) {
	print STDERR "ERROR\tReject record\tReason: no other information\n";
	&add_REP_skip($marc_record_ref);
    }
    
    $other_information =~ s/([^:])$/$1:/; # add ':' if needed
    my $content = "  ";
    if ( defined($tracks) ) {
	$content .= "\x1F3$tracks";
    }
    $content .= "\x1Fo".$other_information;
    if ( defined($date) ) {
	# 200606 => kesäkuu 2006:
	if ( $date =~ /^($yyyy_regexp)($mm_regexp)$/ ) {
	    my $year = $1;
	    my $mm = $2;
	    my $month = &int2finnish_month_name($mm, $marc_record_ref);
	    $date = $month.' '.$year;
	}
	$content .= "\x1Fd".$date;
    }
    if ( defined($place) ) {
        if ( defined($date) ) {
	    $content .= ",";
	}
	$content .= "\x1Fp".$place;
    }
    $content =~ s/([^\.])$/$1./; # Add final punctuation
    add_marc_field($marc_record_ref, '518', $content);
}



sub get_max_seen_disc_number($) {
    my ($tempo_data_ref) = @_;
    my @cands = grep(/disc_number =/, @{$tempo_data_ref});
    if ($#cands > -1 ) {
	my $max = 0;
	foreach my $dn ( @cands ) {
	    if ( $dn =~ /disc_number = '(\d+)'$/ ) {
		my $n = $1;
		
		if ( $n > $max ) {
		    $max = $n;
		}
	    }
	}
	if ( $max > 0 ) {
	    #die($max);
	    return $max;
	}
    }
    return 0;
}

sub process_host_item_entry($$$$) {
    my ( $prefix, $tempo_dataP, $marc_record_ref, $tempo_host_id) = @_;
    if ( !defined($tempo_host_id) ) {
	print STDERR "ERROR\tReject record\tReason: no host id for 773\$w\n";
	&add_REP_skip($marc_record_ref);
	return;
    }
    
    my $g = get_single_entry("/$prefix/track_number", $tempo_dataP);
    my $g2 = get_single_entry("/$prefix/custom/disc_number", $tempo_dataP);	
    if ( defined($g) ) {
	$g =~ s/^0+//;
	if ( $g =~ /^\d+$/ ) { $g = "raita $g"; }
	if ( defined($g2) ) { $g = "levy $g2, ".$g; }
	$g = "\u$g";
    }
    elsif ( defined($g) ) {
	die();
    }
    else {
	# "CustomID" can contains similar info: "CD-140480-1:06"
    }
    my $punc = '';

    my $content773 = "1 \x1F7nnjm";

    $content773 .= "\x1Fw(FI-Yle)$tempo_host_id";
    if ( defined($t773{$tempo_host_id}) ) {
	$content773 .= "\x1Ft".$t773{$tempo_host_id};
	$content773 =~ s/\.$//;
	$punc = ". -";
    }
    else {
	# TODO: Fono used
    }
    if ( defined($d773{$tempo_host_id}) ) {
	$content773 .= "$punc\x1Fd".$d773{$tempo_host_id};
	$punc = ". -";
    }
    if ( defined($h773{$tempo_host_id}) ) {
	$content773 .= "$punc\x1Fh".$h773{$tempo_host_id};
	$punc = ". -";
    }
    if ( defined($o773{$tempo_host_id}) ) {
	$content773 .= "$punc\x1Fo".$o773{$tempo_host_id};
	$punc = ". -";
    }
    
    if ( defined($g) ) {
	$content773 .= "$punc\x1Fg$g";
    }

    if ( $content773 =~ /\x1F[a-z]/ ) {
	add_marc_field($marc_record_ref, '773', $content773);
    }

}


sub process_origin($$$) {
    # Specs: see MELINDA-7748
    my ( $prefix, $tempo_dataP, $marc_recordP) = @_;
    my $path = "/$prefix/custom/origin";
    my $origin = get_single_entry($path, $tempo_dataP);
    if ( defined($origin) && $origin ne "" ) {
	my $original_origin = $origin;
	$origin =~ s/^kansalliset vähemmistöt:\s*//i;
	$origin =~ s/ \(\S+\)$//; # Seen only "(Suomi)" and "(Ruotsi)" so far
	# Now we should have only the term left.
	my $yso_id =  new_pref_label2unambiguous_id($origin, 'yso', 'fin');
	if ( !$yso_id && $origin =~ /nen$/ ) {
	    my $tmp = $origin;
	    $tmp =~ s/nen$/set/;
	    print STDERR "NB\tOrigin: Trying '$tmp' as an alternative for '$tmp'/'$origin'\n";
	    $yso_id = new_pref_label2unambiguous_id($tmp, 'yso', 'fin');
	}
	if ( !$yso_id ) {
	    my $msg = "Failed to handle origin: '$origin'/'$original_origin'\n";
	    if ( !$robust ) {
		die("ERROR\t$msg");
	    }
	    print "WARNING\t$msg\n";
	}
	else {
	    my $content = "  \x1FmEtnisyys\x1Fneth\x1Fa".$origin."\x1F2yso/fin\x1F0http:\/\/www.yso.fi\/onto\/yso\/p".$yso_id;
	    add_marc_field($marc_recordP, '386', $content);
	}

    }
}

sub process_work_notes($$$$) {
    my ( $prefix, $tempo_dataP, $marc_recordP, $is_host) = @_;
    my $path = "/$prefix/custom/work_notes";
    my $work_notes = get_single_entry($path, $tempo_dataP);
    # Overwrite the existing field 046 value that we got from composition_year
    # as this one is more accurate:
    if ( defined($work_notes) ) {
	my $ind1 = $is_host ? ' ' : '1';
	if ( $work_notes =~ s/Sävelletty ($yyyy_regexp)-($yyyy_regexp)\.// ) {
	    my $new_content = "${ind1} \x1Fk$1\x1Fl$2";
	    my $f046 = ${$marc_recordP}->get_first_matching_field('046');

	    if ( defined($f046) ) {
		if ( $new_content ne $f046->{content} ) { 
		    print STDERR "WARNING\t046 change\t'", $f046->{content}, "' => '", $new_content, "'\n";
		    $f046->{content} = $new_content;
		}
		
	    }
	    else {
		add_marc_field($marc_recordP, '046', $new_content);
	    }
	}

	if ( $work_notes =~ /\S/ ) {
	    $work_notes = &trim_all($work_notes);
	    $work_notes =~ s/([a-z0-9]|å|ä|ö)$/$1./gi;
	    add_marc_field($marc_recordP, '500', "  \x1Fa".$work_notes);
	}
    }
}



sub add_935($$) {
    my ( $marc_record_ref, $is_host ) = @_;
    #if ( $is_host ) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
    $year += 1900;
    $mon += 1;
    if ( length($mon) == 1 ) { $mon = "0". $mon; }
    if ( length($mday) == 1 ) { $mday = "0". $mday; }
    add_marc_field($marc_record_ref, '935', "  \x1FaTempo${year}${mon}${mday}\x1F5VIOLA");
    #}
}



sub illegal_prod_code($) {
    my $prod_code = shift;
    if ( $prod_code =~ /^Ei kaupallista tunnusta/i ||
	 # Including typos:
	 $prod_code =~ /^Ei ?(kalogi|katalogi|katqalogi|tilaus)(numeoa|numeroa|umeroa)/i ) {
	return 1;
    }
    return 0;
}

sub get_album_refs($) {
    my ( $tempo_data_ref ) = @_;
    
    my ( @album_refs ) = keyvals2vals(extract_keys('/album/album_ref', $tempo_data_ref)); # take only the first?
    print STDERR "get_album_refs(): '", join("', '", @album_refs), "'\n";
    # Sanity check_ can this happen:
    if ( $#album_refs > 0 ) { die(); }

    # Tempo's album_ref == Fono's prod_code
    @album_refs = grep { !&illegal_prod_code($_ ) } @album_refs;

    if ( $#album_refs == -1 ) {
	return ();
    }

    return @album_refs;
}

sub tempo_album_refs2tempo_album_ref($) {
    my ( $tempo_album_refs_ref ) = @_;
    
    my $tempo_album_ref = undef;
    if ( scalar(@{$tempo_album_refs_ref}) > 0 ) {
	$tempo_album_ref = shift @{$tempo_album_refs_ref}; # remove from array!
	# TM: No space in 028$a. See MELINDA-7748.
	# NB! When have seen "3616846 777418"(which is EAN) here.
	# Just a single instance, so not fixing it. Just letting it pass.
	$tempo_album_ref =~ s/^([A-Z][A-Za-z]*|[a-z]+) ([0-9]+)$/$1$2/;	
	if ( $tempo_album_ref =~ /^([^ ] )+[^ ]$/ || # "B E T C D 0 5"
	     $tempo_album_ref =~ /\-/ ) { # '.' might mean something
	    $tempo_album_ref =~ s/ //g;
	}
	
	if ( $tempo_album_ref =~ / [0-9A-Z]+$/ ) {
	    $tempo_album_ref =~ s/\s+/-/g; # "ZT3 001" => "ZT3-001"
	}

	if ( $tempo_album_ref =~ / / ) { die("TAR has evil space: '$tempo_album_ref'"); }
	
	if ( $debug ) {
	    for ( my $i=0; $i <= $#{$tempo_album_refs_ref}; $i++ ) {
		print STDERR "WARNING\tUnused album ref[$i]: ", ${$tempo_album_refs_ref}[$i], "\n";
	    }
	}
    }
    return $tempo_album_ref;
}

sub get_affiliate_band_field($$) {
    my ( $affiliate_name, $band_fields_ref ) = @_;
    foreach my $band_field ( @{$band_fields_ref} ) {
	my $content = $band_field->{content};
	print STDERR "Compare '$affiliate_name' vs '$content'\n";
	if ( $content =~ /\x1Fa([^\x1F]+)/ ) {
	    my $a = $1;
	    $a =~ s/,$//;
	    if ( $a eq $affiliate_name ) {
		return $band_field;
	    }
	}
    }
    return undef;
}
sub pair_person_and_band($$) {
    my ( $person_field_ref, $band_fields_ref ) = @_;
    print STDERR "ppab in\n"; # die();
    if ( ${$person_field_ref}->{content} =~ /\x1Fa([^\x1F]+)/ ) {
	my $name = $1;
	$name =~ s/,$//;
	my @auth_records = name2auth_records($name);
	print STDERR "ppab2 in: '$name' vs ", ($#auth_records+1), " auth records\n"; # die();

	foreach my $auth_record ( @auth_records ) {
	    my @affiliate_fields = $auth_record->get_all_matching_fields('373');
	    foreach my $affiliate_field ( @affiliate_fields ) {
		my $content = $affiliate_field->{content};
		print STDERR "ppab4 (affiliates) in: $name vs '", $affiliate_field->toString(), "'\n"; # die();

		while ( $content =~ s/\x1Fa([^\x1F]+)// ) {
		    my $affiliate_name = $1;
		    $affiliate_name =~ s/,$//;
		    print STDERR "Try to pair $name and $affiliate_name\n";
		    my $band_field = &get_affiliate_band_field($affiliate_name, $band_fields_ref);
		    if ( defined($band_field) ) {
			if ( $band_field->{content} !~ /\x1F0/ ) {
			    my @band_auth_records = name2auth_records($affiliate_name);
			    my $hits = 0;
			    foreach my $bar ( @band_auth_records ) {
				if ( !$hits && index($bar->toString(), $name) > -1 ) {
				    my $sf0 = $bar->get_first_matching_field('001');				    
				    $band_field->{content} .= "\x1F0(FIN11)".$sf0->{content};
				    $hits++;
				}
			    }
			}
			if ( ${$person_field_ref}->{content} !~ /\x1F0/ ) {
			    my $sf0id = $auth_record->get_first_matching_field('001');
			    print STDERR "Link \$0 (FIN11)",$sf0id->{content}," to '$name'\n";
			    ${$person_field_ref}->{content} .= "\x1F0(FIN11)".$sf0id->{content};
			}
		    }
							       
		}
	    }
	}
    }
}

sub country2place_of_publication_production_or_execution($$) {
    my ( $country, $marc_record_ref ) = @_;
    $country = normalize_location($country);
    my $country_code = country2code($country, $marc_record_ref);
    if ( !defined($country_code) || length($country_code) != 3 ) {
	print STDERR "ERROR\tReject record\tReason: country code '$country_code'\n";
	&add_REP_skip($marc_record_ref);
	return undef;
    }
    return $country_code;
}

sub postprocess_asteri_links($) {
    my ( $marc_record_ref ) = @_;

    my @persons = ${$marc_record_ref}->get_all_matching_fields('[17]00');
    my @bands = ${$marc_record_ref}->get_all_matching_fields('[17]10');

    if ( $#persons == -1 || $#bands == -1 ) { return; }

    foreach my $person ( @persons ) {
	# If person's (potential) auth record maps to a band's (potential)
	# auth record, add $0 to persion. And vice versa.
	pair_person_and_band(\$person, \@bands);
    }
}

sub fix_008_23($) {
    my ( $marc_record_ref ) = @_;
    my $f007 = ${$marc_record_ref}->get_first_matching_field('007');
    if ( defined($f007) && $f007->{content} =~ /^c/ ) {
	# Are all electronic resources online stuff...
	# (008/23=o for verkkoaineisto comes from VIOLA-55)
	${$marc_record_ref}->update_controlfield_character_position('008', 23, 'o');
    }
}
    


sub process_tempo_data2($$$$);
sub process_tempo_data2($$$$) {
    my ( $prefix, $is_host, $tempo_data_ref, $marc_record_ref ) = @_;

    # Create new record iff needed:
    # (The idea was that multiple multipart records can enrich same marc record.
    # However, this is not how we did that in the end. We could simplify code
    # here...)
    if ( !defined($marc_record_ref) ) {
	my $foo_marc_record = new nvolk_marc_record();
	$marc_record_ref = \$foo_marc_record;
    }

    # LS: "DIGY on digitaalinen Ylen kantanauha. ... [K]yseessä on Ylen
    # ohjelmakäyttöön tarkoitettu julkaisematon musiikki. CD-levyille vastaava
    # sarja on CDY."
    # Mark them as deleted, so that they'll be skipped.
    my $customID = &get_customID($tempo_data_ref, $prefix, $marc_record_ref);
    if ( defined($customID) && $customID =~ /^(CDY|DIGY)/ ) {
	print STDERR "WARNING\tDELETE RECORD (Reason: $customID)\n";
	${$marc_record_ref}->mark_record_as_deleted();
    }
    
    
    my $is_classical_music = &is_classical_music($tempo_data_ref, $prefix);
    
    if ( 1 ) {
	my $n = $#{$tempo_data_ref} +1;
	remove_noise_from_tempo($prefix, $tempo_data_ref);
	if ( $debug ) {
	    my $n2 = $#{$tempo_data_ref} +1;
	    print STDERR "remove_noise_from_tempo() cleaned ", ($n-$n2), " row(s).\n";
	    #print STDERR join("\n", @tempo_data), "\n";
	}
	
    }
    #print STDERR "REMAINING LEAF DATA AFTER PREPROCESSING:\n PREPRO\t", join("\n PREPRO\t", @tempo_data), "\n";


    my $tempo_record_id = get_single_entry("/$prefix/_id", $tempo_data_ref);
    my $tempo_host_id = ( $is_host ? undef : get_single_entry("/$prefix/album =", $tempo_data_ref));

    my $tempo_title = get_tempo_title($prefix, $tempo_data_ref);
    my $max_disc_number = get_max_seen_disc_number($tempo_data_ref);
    # HOST has like "TITLE (2CD)"
    my $media_as_per_title = ( !$is_host || !defined($tempo_title) ? undef : &extract_media_from_title(\$tempo_title, $max_disc_number));


    my $description = undef;
    if ( 1 ) {
	my @descriptions = get_array_entry("/$prefix/descriptions", $tempo_data_ref);
	# Sadly descriptions is defined as an array, even though it always
	# contains but one line...
	# Should we simplify code, by making it variable...
	if ( scalar(@descriptions) > 1 ) {
	    print STDERR "ERROR\tReject record\tReason: N of descriptions > 1\n";
	    &add_REP_skip($marc_record_ref);
	}
	$description = $descriptions[0];
    }
    
    &description_cleanup(\$description);

    
    my @tempo_album_refs = &get_album_refs($tempo_data_ref);

    my $is_sacd = 0;    
    my $physical_description = undef;
    my $desc_musicians = undef;
    my $desc_additional_musicians = undef;

    if ( defined($description) ) {
	#print STDERR "DESC: $description\n";
	$is_sacd = &is_sacd(\$description);
	$description =~ s/(^| )(Soittovapaa|Julkaisu[ a-z]*) (\d+.)+$//; # TODO: Check whether TM is interested in these
	$physical_description = &description2physical_description(\$description, $marc_record_ref);
	$desc_musicians = &description2musicians(\$description, $marc_record_ref);
	$desc_additional_musicians = &description2additional_musicians(\$description);
    }
	 
    my $artist_notes = get_single_entry("/$prefix/custom/artist_notes", $tempo_data_ref);

    if ( defined($artist_notes) && $artist_notes ) {
	$artist_notes =~ s/(\((?:[^\) ]+, )?)laulu([,\)])/${1}lauluääni${2}/;
	&description_cleanup(\$artist_notes);
    }
    
    if ( defined($artist_notes) ) {
	print STDERR "AN: $artist_notes\n";
	if ( defined($desc_musicians) || defined($desc_additional_musicians) ) {
	    die();
	}
	$desc_musicians = &description2musicians(\$artist_notes, $marc_record_ref);
	$desc_additional_musicians = &description2additional_musicians(\$artist_notes);
	
	if ( $artist_notes =~ /\S/ ) {
	    if ( defined($desc_additional_musicians) ) {
		die($desc_additional_musicians);
	    }
	    elsif ( defined($desc_musicians) ) {
		print STDERR "AN: $artist_notes\n";
		$artist_notes =~ s/\.$//;
		if ( $desc_musicians =~ s/^Jäsenet:/$artist_notes:/ ) {
		    $artist_notes = undef;
		}
		else {
		    die($artist_notes);
		}
	    }
	    else {
		$desc_musicians = $artist_notes;
		$artist_notes = undef;
	    }
	}
    }
    
    # Set LDR/06-07
    # LDR/06: j=music recording
    ${$marc_record_ref}->update_leader_character_position(6, "j");
    # LDR/07: a=comp, m=host
    my $ldr06_07 = ( $is_host ? 'jm' : 'ja' );
    ${$marc_record_ref}->update_leader_character_position(7, ($is_host ? 'm' : 'a'));

    # Marc field 007
    # Host will extract the value:

    #print STDERR "C: '$customID', SACD:$is_sacd\n";

    # NB! Handle 007 before 006, as 006 decision is no longer based on DIGI
    # but 007.
    # Field 007
    if ( !defined($tempo_host_id) ) { # Host:
	extract_field_007($tempo_data_ref, $marc_record_ref, $tempo_record_id, $customID, $is_sacd, $tempo_title, $physical_description);
    }
    # Comps will inherit/copy the value of 007 from host:
    else { # Comp:
	if ( defined($field007{$tempo_host_id}) ) {
	    # TODO: Should 006 be here as well?
	    add_marc_field($marc_record_ref, '007', $field007{$tempo_host_id});
	}
	else {
	    die();
	}
    }

    
    # Field 006
    if ( !defined($tempo_host_id) ) { # Host:
	extract_field_006($marc_record_ref, $customID, $is_sacd, $tempo_record_id );
    }

    # Comps will inherit/copy the value of 007 from host:
    else {
	if ( defined($field006{$tempo_host_id}) ) { # Comp:
	    add_marc_field($marc_record_ref, '006', $field006{$tempo_host_id});
	}
    }


    if ( !${$marc_record_ref}->get_first_matching_field('007') ) {
	print STDERR "ERROR: Unable to determine the marc field 007 (comp, no host found)!\n";
	if ( !$robust ) {
	    die();
	}
    }

    # 008
    my $f008 = $default008;
    add_marc_field($marc_record_ref, '008', $f008);

    process_genre($prefix, $tempo_data_ref, $marc_record_ref);
    process_sub_genre($prefix, $tempo_data_ref, $marc_record_ref);

    fix_008_23($marc_record_ref);
    
    my @languages = get_languages($prefix, $tempo_data_ref, $marc_record_ref);

    my @ensembles = keyvals2vals(extract_keys("/$prefix/custom/ensemble", $tempo_data_ref));

    # UPDATE 008/37-37
    my $f008_35_37 = &languages_to_008_35_37(\@languages, \@ensembles, $marc_record_ref);
    ${$marc_record_ref}->update_controlfield_character_position('008', 35, $f008_35_37);

    ## 008/15-17 publication country
    # NB #1: Fono used fields 223 (publishing country) and 225 (republishing
    #        country). If latter existed, it was given preference.
    #        Haven't seen this with Tempo yet.
    # NB #2: In Fono, comps derived this value from host.
    #        However, with Tempo also comps seem to have relevant data.
    my $curr_key = "/$prefix/custom/recording_country";
    my ( $recording_country ) = keyvals2vals(extract_keys($curr_key, $tempo_data_ref));
    if ( defined($recording_country) ) {
	$recording_country = &normalize_location($recording_country);
    }
    
    $curr_key = "/$prefix/custom/publication_country";
    my ( $publication_country ) = keyvals2vals(extract_keys($curr_key, $tempo_data_ref));
    if ( defined($publication_country) ) {
	$publication_country = &normalize_location($publication_country);
    }
    
    my $f008_15_17 = undef;
    my $f008_15_17_source = undef;
    # Primary source: publication_country
    # (Fono has publication and republication country here)
    if ( defined($publication_country) ) {
	$f008_15_17 = country2place_of_publication_production_or_execution($publication_country, $marc_record_ref);
	$f008_15_17_source = 'publication country';
    }
    # Secondary source: recording country (~ production country?)
    # As per T.M.: Don't use!
    if ( 0 && !defined($f008_15_17) && defined($recording_country) ) {
	$f008_15_17 = country2place_of_publication_production_or_execution($recording_country, $marc_record_ref);
	$f008_15_17_source = 'recording country';
    }
	
    if ( defined($f008_15_17) ) {
	if ( $debug ) {
	    print STDERR "008/15-17 via $f008_15_17_source: '$f008_15_17'\n";
	}
	${$marc_record_ref}->update_controlfield_character_position('008', 15, $f008_15_17);
	$field008_15_17{$tempo_record_id} = $f008_15_17; # Cache me
    }
    elsif ( defined($tempo_host_id) ) { # Field 008/15-17 for comps:
	if ( defined($field008_15_17{$tempo_host_id}) ) {
	    ${$marc_record_ref}->update_controlfield_character_position('008', 15, $field008_15_17{$tempo_host_id});
	}
    }
    
    
    ${$marc_record_ref}->update_controlfield_character_position('008', 35, $f008_35_37);
    
    ### YEARS
    my ( $publication_year, $publication_year_specifier ) = get_year("/$prefix/custom/publication_year", $tempo_data_ref, $marc_record_ref);  # Fono's 222.
    my ( $recording_year, $recording_year_specifier ) = get_year("/$prefix/custom/recording_year", $tempo_data_ref, $marc_record_ref); # Fono's 112. Should be undef for hosts
    my ( $rerelease_year, $rerelease_year_specifier ) = get_year("/$prefix/custom/re_release_year", $tempo_data_ref, $marc_record_ref); # Fono's 224. Should be undef for hosts


    if ( defined($publication_year) && defined($rerelease_year) ) {
	# Historical specs: publication year goes to 534.
	# SYSHOI-4057: multi-year copyright goes to 500 instead.
	if ( $publication_year =~ /^\d+-\d+$/ ) {
	    add_marc_field($marc_record_ref, '500', "  \x1FaEsitykset julkaistu alun perin: $publication_year.");
	}
	else {
	    add_marc_field($marc_record_ref, '534', "  \x1FpAlun perin julkaistu:\x1Fn© $publication_year."); # TODO: CHECK is © still used/needed?
	}
    }
    
    my $main_year = undef;
    my $year_type = undef;
    my $year_specifier = undef;
    if ( $is_host && defined($rerelease_year) ) {
	$main_year = $rerelease_year;
	$year_type = 'rerelease';
	$year_specifier = $rerelease_year_specifier;
    }
    elsif ( !$is_host && defined($recording_year) ) {
	$main_year = $recording_year;
	$year_type = 'recording year';
	$year_specifier = $recording_year_specifier;
    }
    elsif ( defined($publication_year) && $publication_year) {
	$main_year = $publication_year;
	$year_type = 'publication_year';
	$year_specifier = $publication_year_specifier;
    }

    if ( defined($main_year) ) {
	if ( $debug ) {
	    print STDERR "DEBUG\tYEAR=$main_year\tSOURCE=$year_type\n";
	}
	# NB! Fono comp gets copied 008/07-10 from host
	${$marc_record_ref}->update_controlfield_character_position('008', 7, $main_year);
	# If we had year range we could do something like 008/06-14='q19901994' 

    }


    if ( !$is_host ) {
	## 024 FIELD, IND1=0, IND2=# (ISRC):
	extract_identifier("/$prefix/isrc", $tempo_data_ref, $marc_record_ref);
	# 024 FIELD, IND2=7 (ISWC) NEW!!
	extract_identifier("/$prefix/iswc", $tempo_data_ref, $marc_record_ref);
    }
    # 024 FIELD EAN
    if ( $is_host ) {
	extract_identifier("/$prefix/ean", $tempo_data_ref, $marc_record_ref);
    }

    # NB! 626b78291e01e1003369cbf2 contains Tempo's album ref "00602445823925".
    # Not sure whether this is a GTI code or not. If it is, it should
    # be converted to EAN and added to 024...
    
    my @album_refs2ean = grep(/^[0-9]{13}$/, @tempo_album_refs);
    if ( $#album_refs2ean > -1 ) {
	@tempo_album_refs = grep(! /^[0-9]{13}$/, @tempo_album_refs);

	print STDERR join("\n", @album_refs2ean);
	foreach my $ean ( @album_refs2ean ) {
	    add_marc_field($marc_record_ref, '024', "3 \x1Fa".$ean."\x1Fqextracted from Tempo record's album_ref");
	}
    }

    # 028
    my $label = undef;
    if ( $is_host ) {
	$label = &get_label($prefix, $tempo_data_ref, $marc_record_ref);

	#print STDERR "028028 '", join("', '", @tempo_album_refs), "'\n";

	my $tempo_album_ref = tempo_album_refs2tempo_album_ref(\@tempo_album_refs);

	
	
	# Add 028 (and corresponding comps' 773$o) only if both $a and $b exist
	# (As per TM's comments. Previously lone 028$b was possible.)
	if ( defined($label) && defined($tempo_album_ref) ) {
	    # NB! Theoretically Fono had some extra info that goes to 028$q.
	    # Not currently handled in Tempo.
	    my $content = "01\x1Fb".$label."\x1Fa".$tempo_album_ref;
	    my $o773 = $label . " " . $tempo_album_ref;

	    add_marc_field($marc_record_ref, '028', $content);	    
	    if ( defined($o773{$tempo_record_id}) ) {
		print STDERR "ERROR\tReject record\tReason: multiple 773\$o '$o773'\n";
		&add_REP_skip($marc_record_ref);
	    }
	    $o773{$tempo_record_id} = $o773;
	}
    }

    # FIELD 031: extract incipit from title
    if ( defined($tempo_title) ) {
	process_title_incipit(\$tempo_title, $marc_record_ref);
    }

    # 033 is done together with 518. Check it there


    if ( defined($tempo_record_id) ) {
	add_marc_field($marc_record_ref, '035', "  \x1Fa(FI-Yle)$tempo_record_id");
	add_marc_field($marc_record_ref, 'SID', "  \x1Fc$tempo_record_id\x1FbFI-Yle");
    }
    
    add_marc_field($marc_record_ref, '040', "  \x1FaFI-Yle\x1Fbfin\x1Ferda\x1FcFI-NLD");
    ## 041 FIELD
    process_language_codes(\@languages, $marc_record_ref);

    add_marc_field($marc_record_ref, '042', "  \x1Fafinbd");


    &process_composition_country($prefix, $tempo_data_ref, $marc_record_ref);

    # 045/046 (composition year)
    &process_composition_year($prefix, $tempo_data_ref, $marc_record_ref, $is_host);



    # MARC21-084 (FONO-210 for classical music)
    if ( $is_classical_music ) {
	&process_ensemble(\@ensembles, $marc_record_ref);
    }

    # MARC511
    my $field_511_content = '';
    if ( defined($desc_musicians) ) {
	$desc_musicians =~ s/([^\.])$/$1./;
	if ( $debug ) {
	    print STDERR "artist_notes => 511: $desc_musicians\n";
	}
	if ( $field_511_content ) {
	    print STDERR "ERROR\tReject record\tReason: desc musicians not empty '$desc_musicians'\n";
	    &add_REP_skip($marc_record_ref);
	}
	$field_511_content = "0 \x1Fa$desc_musicians";
    }
   
    # MARC21: 1X0, 7X0 (FONO: ... )
    &process_tempo_authors($prefix, $tempo_data_ref, $marc_record_ref, $is_classical_music, $is_host, \$field_511_content, $desc_additional_musicians);

    # MARC21: 245
    if ( defined($tempo_title) ) {
	&process_title($tempo_title, $tempo_data_ref, $marc_record_ref, \@languages, $tempo_record_id, $is_host, \%t773);
    }
    
    # MARC: 264
    if ( $is_host && $label && $main_year ) {
	#if ( !$main_year ) { die(); }
	#if ( !$label ) { die(); }
	#if ( $#tempo_album_refs != -1 )  { die(join(" -- ", @tempo_album_refs)); }
	
	# TODO: check [1234] brackets logic.
	my $ind2 = 1;
	add_marc_field($marc_record_ref, '264', " ${ind2}\x1Fb$label,\x1Fc[$main_year]");
	if ( $ind2 eq '1' ) {
	    $d773{$tempo_record_id} = "$label, [$main_year]";
	}
    }

    # MARC: 300
    if ( $is_host ) {
	extract_field_300($tempo_data_ref, $marc_record_ref, $customID, $is_sacd, $tempo_record_id, $physical_description, $media_as_per_title);
	&process_description2language_notes(\$description, $marc_record_ref, $is_host);  # May update (host) 041 and 300. May add 546. Do only after 300 has been created
    }

    
    
    # data/duration => 306
    if ( !$is_host ) {
	&process_duration($prefix, $tempo_data_ref, $marc_record_ref);
    }

    if ( 1 ) {
	# 336
	my $field = ${$marc_record_ref}->add_missing_336();
	if ( $debug && defined($field) ) {
	    print STDERR "ADD FIELD '", $field->toString(), "'\n";
	}
	# 337
	$field = ${$marc_record_ref}->add_missing_337();
	if ( $debug && defined($field) ) {
	    print STDERR "ADD FIELD '", $field->toString(), "'\n";
	}
	# 338
	$field = ${$marc_record_ref}->add_missing_338();
	if ( $debug && defined($field) ) {
	    print STDERR "ADD FIELD '", $field->toString(), "'\n";
	}
	# 347 (for verkkoaineisto):
	my $f338 = ${$marc_record_ref}->get_first_matching_field('338');
	if ( defined($f338) && $f338->{content} =~ /\x1Fbcr\x1F/ ) {
	    add_marc_field($marc_record_ref, '347', "  \x1Faäänitiedosto");
	}
    }

    if ( $is_host ) {
	&extract_field_344($marc_record_ref);
    }

    &process_origin($prefix, $tempo_data_ref, $marc_record_ref); # Marc21 field 386

    &process_work_notes($prefix, $tempo_data_ref, $marc_record_ref, $is_host); # Marc21 field 500, may also update 046

    # theme (fono 180) => Marc21 field 500
    &process_theme($prefix, $tempo_data_ref, $marc_record_ref);

    # $prefix/descriptions


    print STDERR "FÖRBÖR: '", $field_511_content, "'\n";
    
    &process_description($is_host, $prefix, $tempo_data_ref, $marc_record_ref, \$description, \$field_511_content);

    if ( $field_511_content ) {
	print STDERR "FÖRBÖR2: ", $field_511_content, "\n";
	add_marc_field($marc_record_ref, '511', $field_511_content);
    }
    
    ## 518 (and 033):
    # Primary source: recording_location_details
    &tempo_process_recording_location_details($prefix, $tempo_data_ref, $marc_record_ref, $is_classical_music);
    
    # Secondary source (used only if primary source didn't give info):
    # 033:
    if (${$marc_record_ref}->get_first_matching_field_index('033') == -1 ) {
	if ( defined($recording_year) ) {
	    print STDERR "RECYEAR: '$recording_year'\n";
	    if ( !$recording_year_specifier || $recording_year_specifier eq 'noin' ) {
		if ( $recording_year =~ /^\d+$/ ) {
		    add_marc_field($marc_record_ref, '033', "00\x1Fa${recording_year}----");
		}
		elsif ( $recording_year =~ /^(\d+) (\d+)/ ) {
		    my $yy1 = $1;
		    my $yy2 = $2;
		    add_marc_field($marc_record_ref, '033', "10\x1Fa${yy1}----\x1Fa${yy2}----");
		}
		else {
		    die("$recording_year");
		}
	    }
	    elsif ( $recording_year_specifier =~ /^\d+$/ ) {
		add_marc_field($marc_record_ref, '033', "20\x1Fa${recording_year}----\x1Fa${recording_year_specifier}----");	    
	    }
	    else {
		print STDERR "WARNING! SKIP '$recording_year $recording_year_specifier'\n";
	    }
	}
    }
    # secondary 518:    
    if (${$marc_record_ref}->get_first_matching_field_index('518') == -1 ) {
	my $o = 'Äänitys:'; # subfield 518$o
	my $d = undef;
	if ( defined($recording_year) ) {
	    if ( !defined($recording_year_specifier) ) {
		$d = $recording_year;
	    }
	    elsif ( $recording_year_specifier =~ /^\d+$/ ) {
		$d = $recording_year.'-'.$recording_year_specifier;
	    }
	}
	&marc_add_date_and_place_of_an_event_note($marc_record_ref, $o, $d, $recording_country, undef);
    }

    
    if ( $is_sacd ) {
	add_marc_field($marc_record_ref, '538', "  \x1FaHybridi SACD, toistettavissa myös CD-soittimella.")
    }

    
    # 773
    if  ( !$is_host ) {
	&process_host_item_entry($prefix, $tempo_data_ref, $marc_record_ref, $tempo_host_id);
    }

    &add_935($marc_record_ref, $is_host);

    # Check whether the record is a multipart.
    # HACK: Store the information to multipart-comp's ad hoc field 799$w
    my $multipart = get_single_entry("/$prefix/multipart", $tempo_data_ref);
    if ( defined($multipart) ) {
	add_marc_field($marc_record_ref, '799', "  \x1Fw$multipart")
    }
    
    

    postprocess_asteri_links($marc_record_ref);
    
    my @marc_record_array;
    $marc_record_array[0] = ${$marc_record_ref};
    if ( $is_host ) {
	my $nth_song = 0;
	my @song_data;
	print STDERR "PROCESS COMPS...\n";
	do {
	    my $key = "/album/tracks[$nth_song]/";
	    @song_data = extract_keys($key, $tempo_data_ref);
	    @{$tempo_data_ref} = grep { index($_, $key) != 0 } @{$tempo_data_ref};
	    if ( $#song_data > -1 ) {
		print STDERR "Process comp $nth_song\n";
		#print STDERR join("\n", @song_data), "\n";
		my ( $comp_record ) = process_tempo_data2("album/tracks[$nth_song]", 0, \@song_data, undef);
		#print STDERR $comp_record->toString();
		$marc_record_array[$#marc_record_array+1] = $comp_record;
	    }
	    $nth_song++;
	} while ( $#song_data > -1 );
    }

    my $header = " UNPROCESSED ".($is_host ? 'HOST' : 'NON-HOST' );
    print STDERR "REMAINING LEAF DATA AFTER PROCESSING:\n$header\t", join("\n$header\t", @{$tempo_data_ref}), "\n";    
    

    return @marc_record_array;
}


sub process_tempo_data {
    my @tempo_data = @_;    
    my $is_host = 0;
    my $prefix = undef;
    if ( grep(/^\/data\/album = '[0-9a-f]{24}'/, @tempo_data) ) {
	$is_host = 0;
	$prefix = 'data';
    }
    if ( grep(/^\/album\//, @tempo_data) ) {
	$is_host = 1;
	$prefix = 'album';
    }

    my @records = process_tempo_data2($prefix, $is_host, \@tempo_data, undef); 
    
    handle_multiparts(\@records);
    
    return @records;
}


sub process_tempo_file($) {
    my $filename = shift;
    my $file_as_string = &file2string($filename);
    $file_as_string =~ s/\&amp;/&/g;
    my @tempo_data = json2tempo_data_string_array($file_as_string); 


    return process_tempo_data(@tempo_data);
}
    

###########
## MAIN: ##
###########


&init_config();    

my @input_files;
if ( defined($input_directory) ) {
    if ( ! -e $input_directory ) {
	die("TODO: check $input_directory existence");
    }
    @input_files = glob($input_directory."/*.json");
    print STDERR $#input_files, " file(s) add from $input_directory.\n";
}
else {
    # At this point, ARGV should consist of only tempo input files:
    @input_files = grep(/\.json$/, @ARGV);
    # TODO: Remove non-existant files?
}

sub get_required_but_missing_directories($) {
    my $directory = shift;
    my @cands = ( $directory, "$directory/json", "$directory/marc" );
    my @missing_dirs;
    foreach my $cand_dir ( @cands ) {
	# -e: Must exist. -d: Must be a directory.
	if ( ! -e $cand_dir ) {
	    push(@missing_dirs, $cand_dir . ' (missing dir)');
	}
	elsif ( ! -d $cand_dir ) {
	    push(@missing_dirs, $cand_dir . ' (exists, not dir)');
	}
	elsif ( ! -w $cand_dir ) {
	    push(@missing_dirs, $cand_dir . ' (exists, non-writable)');
	}
    }

    return @missing_dirs; # --some-directory=0 might cause true/false issues.
}

# Check output directory:
if ( defined($output_directory) ) {
    my @missing_dirs = get_required_but_missing_directories($output_directory);
    if ( $#missing_dirs > -1 ) {
	# Should we create them dirs?
	print STDERR "Problematic output dir(s): ", join(", ", @missing_dirs), "\n";
	exit(-1);
    }
}

# Check error directory:
if ( defined($error_directory) ) {
    my @missing_dirs = get_required_but_missing_directories($error_directory);
    if ( $#missing_dirs > -1 ) {
	print STDERR "Problematic error dir(s): ", join(", ", @missing_dirs), "\n";
	exit(-1);
    }
}

if ( defined($error_directory) && defined($output_directory) &&
     $error_directory eq $output_directory ) {
    print STDERR "Options --error-directory and --output-directory must differ!\n";
    exit(-2);
}

if ( $#input_files == -1 ) {
    print STDERR "ERROR: No input files for whatever reason\n\n";
    usage();

    exit(-3);
}

sub output_dir_or_error_dir2target_dir($$$$) {
    my ( $marc_objects_ref, $filename, $target_directory, $error_directory, ) = @_;
    
    if ( $#{$marc_objects_ref} == -1 ) {
	print STDERR "ERROR: no record derived from file '$filename'\n";
	return $error_directory; # Not that this matters...
    }

    if ( reject_batch($marc_objects_ref) ) {
	print STDERR "ERROR: rejected records in '$filename'\n";
	return $error_directory;
    }

    print STDERR "Created ", ($#{$marc_objects_ref}+1), " output record(s) from '$filename'.\n";
    return $target_directory;

}
    
sub save_file($$) {
    my ( $filename, $data ) = @_;
    my $FH;
    open($FH, ">$filename") or die("$filename: $!");
    print $FH $data;
    close($FH);
    print STDERR "SAVE $filename\n";
    return;
}



sub get_comp_levy($) {
    my ( $field_content ) = @_;
    if ( $field_content =~ /\x1FgLevy (\d+)/ ) {
	return $1;
    }
    # Default:
    return 1;
}

sub get_comp_raita($) {
    my ( $field_content ) = @_;
    if ( $field_content =~ /\x1Fg[^\x1F]*?Raita (\d+)/i ) {
	return $1;
    }
    # Default (should this be a big bad number?):
    return 1;
}

sub compare_two_records($$) {
    my ( $a, $b ) = @_;
    my $a773 = $a->get_first_matching_field_content('773');
    my $b773 = $b->get_first_matching_field_content('773');

    my $a_levy = &get_comp_levy($a773);
    my $b_levy = &get_comp_levy($b773);
    if ( $a_levy < $b_levy ) { return -1; }
    if ( $a_levy > $b_levy ) { return 1; }

    my $a_raita = &get_comp_raita($a773);
    my $b_raita = &get_comp_raita($b773);
    if ( $a_raita < $b_raita ) { return -1; }
    if ( $a_raita > $b_raita ) { return 1; }

    return 0;
}



sub fix_300a($) {
    # Reported by T.M. via Slack on 2023-04-17:
    # Sometimes the host does not contain the number of CDs etc.
    # By default we use 300$a 1 CD-äänilevy there.
    # However, we can derive that information from comps...
    my ( $records_ref ) = @_;
    my @comps = @{$records_ref};
    if ( scalar(@comps) < 2 ) { return; }
    my $host = shift @comps; # remove host from comp array
    my $max_levy = 1;
    foreach my $curr_comp ( @comps ) {
	my $f773 = $curr_comp->get_first_matching_field_content('773');
	my $levy = &get_comp_levy($f773);
	if ( $levy > $max_levy ) { $max_levy = $levy; }
    }
    
    if ( $max_levy > 1 ) {
	my $host300 = $host->get_first_matching_field('300');
	if ( $host300->{content} =~ /\x1Fa(\d+)/ ) {
	    my $host_levy = $1;
	    if ( $host_levy < $max_levy ) {
		print STDERR "FIX300\$a:\n  ", $host300->toString(), " =>\n";
		if ( $host300->{content} =~ s/\x1Fa\d+ (C-kasettia|CD-äänilevyä|äänilevyä)/\x1Fa$max_levy ${1}/ ||
		     $host300->{content} =~ s/\x1Fa1 (CD-äänilevy)/\x1Fa$max_levy ${1}ä/ ) {
		    print STDERR "  ", $host300->toString(), "\n";
		    return;
		}
		die($host300);
	    }
	}
    }
}

    
sub create_host_field_505($) {
    my ( $records_ref ) = @_;
    my @comps = @{$records_ref};
    if ( scalar(@comps) < 2 ) { return; }
    my $host = shift @comps; # remove host from comp array

    my $f505 = $host->get_first_matching_field('505');
    if ( defined($f505) ) { return; } # No action required? Does this happen? (Added by multipart etc.?)

    my @songs;

    @comps = sort { compare_two_records($a, $b) } @comps;

    for (my $i=0; $i < scalar(@comps); $i++ ) {
    #for ( my $i=1; $i <= $#{$records_ref}; $i++ ) {
	
	#my $f245 = ${$records_ref}[$i]->get_first_matching_field('245');
	my $f245 = $comps[$i]->get_first_matching_field_content('245');

	if ( defined($f245) && $f245 =~ /\x1Fa([^\x1F]+)/ ) {
	    my $song_name = $1;
	    my $f773 = $comps[$i]->get_first_matching_field_content('773');
	    print STDERR "SORTED: ", ($i+1), "=", $song_name, "\t$f773\n";

	    $song_name =~ s/\.?( +[=\-\/:])?$//;
	    $songs[$#songs+1] = $song_name;
	}
    }
    my $value = join(' -- ', @songs);
    add_marc_field(\$host, '505', "0 \x1Fa".$value.".");  
}


# TM: 27.4.2023: "poikaset ovat multiparteja. Niihin ei ole tullut lainkaan tekijäkirjauksia. Emolla sellaiset kuitenkin on, joten voinee melko turvallisesti olettaa, että ne ovat samat poikasissa. Etenkin säveltäjä pitäisi kyllä saada poikasten 1XX:ään aina kun mahdollista ja toki muutkin tekijät 7XX:ään"

sub derive_missing_authors($) {
    my ( $records_ref ) = @_;
    my @comps = @{$records_ref};
    if ( scalar(@comps) < 2 ) { return; }
    my $host = shift @comps; # remove host from comp array
    
    my @host_author_fields = $host->get_all_matching_fields('[17][01]0');
    my @host_511 = $host->get_all_matching_fields('511');
    
    if ( scalar(@host_author_fields) == 0 ) { return; }

    for (my $i=0; $i < scalar(@comps); $i++ ) {
	my @comp_author_fields = $comps[$i]->get_all_matching_fields('[17][01]0');
	# Copy author fields from host:
	if ( scalar(@comp_author_fields) == 0 ) {
	    foreach my $author_field ( @host_author_fields ) {
		my $curr_tag = $author_field->{tag};
		if ( $author_field->{content} !~ /\x1Fesäveltäjä/ ) {
		    $curr_tag =~ s/^1/7/;
		}
		$comps[$i]->add_field($curr_tag, $author_field->{content});
	    }
	    foreach my $author_field ( @host_511 ) {
		$comps[$i]->add_field($author_field->{tag}, $author_field->{content});
	    }
	    $comps[$i]->add_field('588', "0 \x1FaTekijätiedot emotietueesta.");
	}

    }
}

print STDERR ($#input_files+1), " input files to be processed...\n";
     
for ( my $i=0; $i <= $#input_files; $i++ ) {
    my $filename = $input_files[$i];
    if ( ! -e $filename ) { die(); } # Add robustness?
    if ( $filename !~ /\.json$/ ) {
	print STDERR "WARNING\tUnexpected input file '$filename'. Skipping it...\n";
	next;
    }
    my @marc_objects = &process_tempo_file($filename);


    fix_300a(\@marc_objects);
    create_host_field_505(\@marc_objects);
    derive_missing_authors(\@marc_objects);
    
    # Final fixes: set certain indicators and sort fields:
    foreach my $record ( @marc_objects ) {
	$record->fix_245_ind1();
	$record->fix_nonfiling_character_fields(); # 245 IND2 etc
	$record->sort_fields();

	# Remove my hacky multipart links:
	my @fields = $record->get_all_matching_fields('799');
	foreach my $field ( @fields ) {
	    $record->remove_field($field);
	}
    }
    
    if ( $debug ) {
	foreach my $record ( @marc_objects ) {
	    # NB! Yle tracks are not necessary in the right order.
	    # TODO: Sort comps by 773$g if needed.
	    my $output = $record->toString();
	    print STDERR "DEBUG\tCONVERSION RESULT #$i:\n$output\n";
	}
    }


    
    my $target_directory = &output_dir_or_error_dir2target_dir(\@marc_objects, $filename, $output_directory, $error_directory); # Batch rejection is checked here:
    
    # Copy marc stuff 1st
    if ( $target_directory ) {
	foreach my $record ( @marc_objects ) {
	    my $id = get_tempo_id_from_marc_record(\$record);
	    if ( !$id ) { die(); }
	    save_file("$target_directory/marc/$id.xml", $record->toMarcXML());
	    save_file("$target_directory/marc/$id.mrc", $record->toISO2709());
	}

	my $target_subdir = $target_directory."/json";

	if ( $debug ) {
	    print STDERR "mv $filename $target_subdir\n";
	}
	File::Copy::move($filename, $target_subdir) or die("$!: $target_subdir");
	# File::Copy::copy($filename, $target_subdir) or die("$!: $target_subdir");

    }
    elsif ( $debug ) {
	print STDERR "Not moving $filename as target dir is undefined\n";
    }
}



if ( $#ARGV == -1 && $#input_files == -1 ) {
    usage();
}

# TODO: Fix 240 both in<dicators


# Talletusvuosi    FONO-112 recording_year      TODO
# Taltiontipaikka  FONO-120 recording_locat...  TODO, no values seen yet
# Sävellysmaa      FONO-161 publication_country N/A
# Sävellysvuosi    FONO-162 composition_year    046
#                  FONO-180 theme               500
# Performers       FONO-190 ???                 511
# Esityskokoonpano FON0-191 ???                 511

# Kokoonpanokoodi  FONO-210 assembly            084 (vain klassinen musiikki)
# Julkaisuvuosi    FONO-222 publication_year    (008,)
# Julkaisumaa      FONO-223 publication_country 008/15-17+(comp's 773 008/15-17)
# Uud.julkaisuv.   FONO-224 re_rerelease_year
# Uud.julkaisumaa  FONO-225 ???                 008/15-17+(comp's 773 008/15-17)
#                           description         500,511
# Fyysinen media   FONO-230 ???                 RODO300, 344
# Rec.comp/prodcode   FONO-240 
#                  FONO-303 ???                 024 (ind1=1 or 3)

# KYSSÄREITÄ:
#
# K: Jos EAN-koodi on 12-merkkinen, niin onko se oikeasti UPC-koodi?
#    Vai puuttuuko siitä alku-0 tms.?
#    Vastaan tullut tapaus oli virhe muuallakin:
#    https://fuga.fi/?sivu=detail&id=761195134023
#    Ja ton mukaan toi on nimen omaan UPC-koodi:
#    https://www.hbdirect.com/album_detail.php?pid=4111458
# -  Entäs jos EAN on 14-merkkinen, kuten Mikko / Pyhimys?
#    Ylimääräinen alkunolla?
#
# V: Viivakoodeista: meillä ei aikaisemmin ole ollut kuin yksi kenttä kaikentyyppisille viivakoodeille, ja se on Tempossa mäpätty Fonosta tuohon EAN-kenttään. Paras ratkaisu olisi kai ollut käyttää GTINiä ja lisätä etunollat kaikille, mutta koska tätä ei ollut Tempon tuotteessa saatavilla, kaikki Ylen viivakoodit ovat jatkossa tuossa EAN-kentässä (myös ne vanhan aikakauden viivakoodit jotka eivät ole UPC:tä eivätkä EAN:ää).
#
# TODO: 'aliases' might contains something remotely useful. (Aliases and pseudonums)

