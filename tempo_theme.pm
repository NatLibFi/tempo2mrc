use strict;
use tempo_utils;

sub process_entry_as_aihepiiri_note($$) {
    my ( $entry, $marc_record_ref ) = @_;
    add_marc_field($marc_record_ref, '500', "  \x1FaAihepiiri: ".$entry);
}


sub map_term_to_yso_id($) {
    my ( $term ) = @_;
    my $yso_id =  new_pref_label2unambiguous_id($term, 'yso', 'fin');
    if ( $yso_id ) { return ( $term, $yso_id ); }
    
    # Hacky singular => plural fallbacks by a cunning linguist.
    if ( $term =~ s/nen$/set/ ||
	 $term =~ s/kk([aeiouy]|ä|ö)$/k${1}t/ ||
	 $term =~ s/pp([aeiouy]|ä|ö)$/p${1}t/ ||
	 $term =~ s/tt([aeiouy]|ä|ö)$/t${1}t/ ||
	 $term =~ s/s$/kset/ ||
	 $term =~ s/([aeiouy]|ä|ö)$/${1}t/ ) {
	$yso_id =  new_pref_label2unambiguous_id($term, 'yso', 'fin');
	if ( $yso_id ) { return ( $term, $yso_id ); }
    }
    
    return ( $term, $yso_id );
}

sub process_theme_as_topical_term($$) {
    my ( $entry, $marc_record_ref ) = @_;
    # primary goal: marc field 650
    # secondary goal: mard field 500
    # $entry = &normalize_theme($entry);
    
    my $term = $entry;
    $term =~ s/^[^:]+: //;

    my $yso_id;
    ( $term, $yso_id ) = &map_term_to_yso_id($term); # NB! Term can change (mostly to plural)

    # Try to convert Theme into an YSO term:
    if ( $yso_id ) {
	my $content = " 7\x1Fa".$term."\x1F2yso/fin\x1F0http:\/\/www.yso.fi\/onto\/yso\/".$yso_id;
	add_marc_field($marc_record_ref, '650', $content);
	return;
    }
    
    print STDERR "WARNING\tUnhandled theme (500): '$entry'\n";
    process_entry_as_aihepiiri_note($entry, $marc_record_ref);
}


sub process_theme_geographic_name($$) {
    # Tempo's theme => Marc21 geogrqaphic name (fields 651 and 653)
    my ( $entry, $marc_record_ref ) = @_;
    $entry = main::normalize_location($entry);
    my $yso_id = new_pref_label2unambiguous_id($entry, 'yso-paikat', 'fin');
    # Try to convert Theme into an YSO term:
    if ( $yso_id ) {
	my $content = " 7\x1Fa".$entry."\x1F2yso/fin\x1F0http:\/\/www.yso.fi\/onto\/yso\/".$yso_id;
	add_marc_field($marc_record_ref, '651', $content);
    }
    # Fallback: Field 653 ind2=5:
    else {
	#add_marc_field($marc_record_ref, '653', " 5\x1Fa".$entry);
	process_entry_as_aihepiiri_note($entry, $marc_record_ref);
    }

}


sub process_theme_person($$) {
    my ( $entry, $marc_record_ref ) = @_;

    # 600-based solution is too iffy as we want only authirized (=containing $0)
    # thus we use the generic solution for now.
#    my $e = undef;
#    if ( 0 ) { 
#	if ( $entry =~ s/ \((.*)\)$// ) {
#	    $e = $1;
#	}
#	my $i1 = $entry =~ /^\S+, \S/ ? '1' : '0';
#	# muusikko/kirjailija, probably these should go to $c, not $e.
#	my $content = $i1 . "4\x1Fa$entry";
#	$content .= $e ? ",\x1Fc$e" : ".";
#	add_marc_field($marc_record_ref, '600', $content);
#    }

    process_entry_as_aihepiiri_note($entry, $marc_record_ref);
}


sub process_theme($$$) {
    my ( $prefix, $tempo_dataP, $marc_record_ref) = @_;
    my $path = "/$prefix/custom/theme";
    my $entrystr = get_single_entry($path, $tempo_dataP);

    if ( defined($entrystr) ) {
	# Use LHS as a term as well:
	$entrystr =~ s/^(kansalliset vähemmistöt|leivonnainen|urheilu|viikonpäivä): /$1 \/ /;
	
	my @entries = split(/ *[,\/] */, $entrystr); # Can't do /( \/ |, )/ ffs
	foreach my $entry ( @entries ) {
	    print STDERR "THEME: '$entry'\n";
	    if ( $entry =~ s/^henkilö: // ) {
		&process_theme_person($entry, $marc_record_ref);
	    }
	    elsif ( $entry =~ s/^(alue|kaupunginosa|kaupunki|maa|maakunta|maanosa|osavaltio): // ) {
		&process_theme_geographic_name($entry, $marc_record_ref);
	    }
	    elsif ( $entry =~ s/^(vuodenaika|vuorokauden aika): // ) {
		&process_theme_as_topical_term($entry, $marc_record_ref);
	    }
	    else {
		# Fallback: dump to 500 with the "whatever:" prefix:
		&process_theme_as_topical_term($entry, $marc_record_ref);
	    }
	}
    }
}


1;
