use strict;
use tempo_utils;

my $robust = 0;
my $debug = 1;

my $dd_regexp = get_dd_regexp();
my $mm_regexp = get_mm_regexp();
my $yyyy_regexp = get_yyyy_regexp();

sub recording_location_details2other_event_information_and_tracks($$) {
    my ( $recording_location_details_ref, $is_classical_music ) = @_;

    my $event_information = 'Äänitys';
    my $tracks = undef;
    
    if ( ${$recording_location_details_ref} =~ s/^Äänitys: *// ) {
	$event_information = 'Äänitys';
    }
    
    if ( ${$recording_location_details_ref} =~ s/ \(live( \/[0-9\-]+)?\).?// ) {
	$tracks = $1;
	if ( !defined($event_information) ||
	     $event_information eq 'Äänitys' ) {
	    # TODO: Jos klassista, niin konserttitaltiointi 
	    $event_information = 'Livetaltiointi';
	}
	else {
	    die();
	}
    }

    if ( ${$recording_location_details_ref} =~ s/ \(konserttiäänitys \/live\).?// ) {
	if ( !defined($event_information) ||
	     $event_information eq 'Äänitys' ) {
	    $event_information = 'Konserttitaltiointi';
	}
	else {
	    die();
	}
    }

    # Educated guess: 'Livetaltiointi' + classical music = 'Konserttitaltiointi'
    if ( defined($event_information) && $event_information eq 'Livetaltiointi' ) {
	if ( $is_classical_music ) {
	    $event_information = 'Konserttitaltiointi';
	}
    }

    $tracks = &normalize_tracks($tracks);
    return ( $event_information, $tracks ); #default
}




sub recording_location_details2place_of_event2($) {
    my ( $recording_location_details_ref ) = @_;

    print STDERR "RLD2PoE: ", ${$recording_location_details_ref}, "\n";

    
    # This is ugly/hacky. Will think of generic solution when we have more
    # relevant Tempo cases.
    my $countries = "(?:Englanti|Hollanti|Ranska|Ruotsi|Suomi|UK)";

    if ( ${$recording_location_details_ref} =~ s/^(?:Äänitysmaat: )?($countries(, $countries)*)\.?$// ) {
	my $hits = $1;
	${$recording_location_details_ref} =~ s/^\.$//;
	return $hits;
    }
    if ( ${$recording_location_details_ref} =~ /^(\D+)$/ ) {
	my $location_part = ${$recording_location_details_ref};
	${$recording_location_details_ref} = '';
	return $location_part;
    }
    if ( ${$recording_location_details_ref} =~ s/^(\D+) ($yyyy_regexp($mm_regexp($dd_regexp)?)?)/$2/ ) {
	my $location_part = $1;
	return $location_part;
    }
    
    if ( $debug && ${$recording_location_details_ref} ) {
	print STDERR "WARNING\tFailed to extract location from '",  ${$recording_location_details_ref}, "'\n";
    }
        
    return undef;
}

sub recording_location_details2place_of_event($) {
    my ( $recording_location_details_ref ) = @_;
    my $location_part = recording_location_details2place_of_event2($recording_location_details_ref);

    $location_part =~ s/: /, /g;
    
    return $location_part;
}

sub recording_location_details2date_of_event($) {
    my ( $recording_location_details_ref ) = @_;
    print STDERR "Trying to extract date from ", ${$recording_location_details_ref}, "\n";
    if ( ${$recording_location_details_ref} =~ s/^($yyyy_regexp($mm_regexp($dd_regexp)?)?)\.?$// ) { # YYYY, YYYYMM YYYYMMDD
	return $1;
    }
    
    if ( ${$recording_location_details_ref} =~ s/^($yyyy_regexp$mm_regexp)($dd_regexp)-($dd_regexp)\.?$// ) { # YYYYMMDD-DD
	return $1.$2.'-'.$1.$3; # multiple dates
    }
    
    return undef;
}


sub recording_location_details2live($) {
    my ( $recording_location_details_ref ) = @_;
    if ( ${$recording_location_details_ref} =~ s/ \(live\)$// ) {
	return 'Livetaltiointi';
    }

    return ''; #default
}


sub split_record_location_details($) {
    my ( $location ) = @_;
    # In Fono we had to split there
    return ( $location );
}


sub marc_create_field_033($$$) {
    my ( $marc_record_ref, $other_event_information, $date_of_event) = @_;

    if ( $other_event_information eq 'Äänitys' ) { return; }
    
    if ( $other_event_information eq 'Konserttitaltiointi' ||
	 $other_event_information eq 'Livetaltiointi' ) {
	if ( $date_of_event =~ /^(${yyyy_regexp})$/ ) {
	    add_marc_field($marc_record_ref, '033', "00\x1Fa${date_of_event}----");
	}
	elsif ( $date_of_event =~ /^$yyyy_regexp$mm_regexp$/ ) {
	    add_marc_field($marc_record_ref, '033', "00\x1Fa${date_of_event}--");		    
	}
	elsif ( $date_of_event =~ /^$yyyy_regexp$mm_regexp$dd_regexp$/ ) {
	    add_marc_field($marc_record_ref, '033', "00\x1Fa${date_of_event}");		    
	}
	elsif ( $date_of_event =~ /^($yyyy_regexp$mm_regexp$dd_regexp)-($yyyy_regexp$mm_regexp$dd_regexp)$/ ) {
	    my $start = $1;
	    my $end = $2;
	    my $content = "20\x1Fa${start}\x1Fa${end}";
	    add_marc_field($marc_record_ref, '033', $content);
	    #die($content);
	}
	elsif ( $date_of_event ) {
	    die();
	}
	return;
    }
    die();
}


sub process_single_recording_location($$$) {
    my ( $curr_rld, $marc_recordP, $is_classical_music ) = @_;
    # Other event information goes to $o
    my ( $other_event_information, $tracks ) = &recording_location_details2other_event_information_and_tracks(\$curr_rld, $is_classical_music);
    
    my $place_of_event = &recording_location_details2place_of_event(\$curr_rld);
    
    my $date_of_event = &recording_location_details2date_of_event(\$curr_rld);

    if ( !$curr_rld ) { # Managed to extract all info
	# TODO: tracks go to $3
	&marc_create_field_033($marc_recordP, $other_event_information, $date_of_event);

	main::marc_add_date_and_place_of_an_event_note($marc_recordP, $other_event_information, $date_of_event, $place_of_event, $tracks);	
	
    }
    else {
	die($curr_rld);
    }
}

sub tempo_process_recording_location_details($$$$) {
    my ( $prefix, $tempo_dataP, $marc_recordP, $is_classical_music) = @_;
    my $recording_location_details = get_single_entry("/$prefix/custom/recording_location_details", $tempo_dataP);
    if ( defined($recording_location_details) ) {

	if ( $recording_location_details =~ s/; *(äänisuunnittelija: [^\.;:]+)(;|\.?$)/$2/ ) {
	    print STDERR "WARNING\tRemoved from recording_location_details: '$1'\n";
	}

	my @recording_location_details_array = &split_record_location_details($recording_location_details);
	foreach my $curr_rld ( @recording_location_details_array ) {
	    process_single_recording_location($curr_rld, $marc_recordP, $is_classical_music);
	}
    }
}
1;
