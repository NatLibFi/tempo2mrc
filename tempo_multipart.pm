use strict;

use tempo_utils;

my $BIG_BAD_NUMBER = 666;

sub get_multipart_id($) {
    my ( $marc_record_ref ) = @_;
    my @f799 = ${$marc_record_ref}->get_all_matching_fields('799', undef);
    if ( $#f799 > 0 ) { die(); }
    if ( $#f799 == -1 ) { return 0; }
    if ( $f799[0]->{content} =~ /^  \x1Fw(.*)$/ ) {
	return $1;
    }
    die($f799[0]->{content});
    return 0;
}

sub g2score($) {
    my $g = shift;
    if ( defined($g) ) {
	if ( $g =~ /^Raita ([1-9][0-9]*)$/ ) {
	    return $1;
	}
	if ( $g =~ /^Levy ([1-9][0-9]*), raita ([1-9][0-9]*)$/ ) {
	    return "$1.$2";
	}
	die();
    }
    die();
    return $BIG_BAD_NUMBER;
}
    
sub compare_773g {
    my $ag = g2score($a->get_first_matching_subfield('773', 'g'));
    my $bg = g2score($b->get_first_matching_subfield('773', 'g'));
    if ( $ag != $bg ) {

	## return $ag <=> $bg; would fail since 2.2 > 2.12
	if ( $ag =~ /^(\d+)\.(\d+)$/ ) {
	    my $alhs = $1;
	    my $arhs = $2;
	    if ( $bg =~ /^(\d+)\.(\d+)$/ ) {
		my $blhs = $1;
		my $brhs = $2;
		if ( $alhs == $blhs ) {
		    return $arhs <=> $brhs;
		}
		return $alhs <=> $blhs;
	    }
	    die();
	}
	if ( $bg =~ /^(\d+)\.(\d+)$/ ) { die(); }
	return $ag <=> $bg;
    }
	
    if ( $ag == $BIG_BAD_NUMBER ) {
	die();
    }
    return 0;
}

sub sort_multiparts_by_773g($) {
    my ( $record_array_ref ) = @_;
    my @array = sort compare_773g @{$record_array_ref};
    return @array;
}

sub human_readable_seconds($) {
    my ( $f306a ) = @_;
    $f306a =~ s/^0+(\d)/$1/; # leaves last 0 if needed
    print STDERR "306: $f306a\n";
    my $min = int($f306a/60);
    my $s = $f306a%60;

    #if ( $min > 59 ) { die(); } # should we use hours?
    
    if ( $min || $s ) {
	my $entry = ' (';
	if ( $min ) {
	    $entry .= $min . ' min';
	    if ( $s ) { $entry .= ' '; }
	}
	$entry .= $s. ' s)';
	return $entry;
   }
    return '';
}


sub list_multipart_records_for_505($) {
    my ( $record_array_ref ) = @_;

    my @list = ();
    for (my $i=0; $i <=$#{$record_array_ref}; $i++ ) {
	my $curr_record = ${$record_array_ref}[$i];

	my $f245a = $curr_record->get_first_matching_subfield('245', 'a');
	my $f245b = $curr_record->get_first_matching_subfield('245', 'b');
	my $f306a = $curr_record->get_first_matching_subfield('306', 'a');

	my $entry = '';
	#if ( !defined($f245a) ) { die(); }
	if ( defined($f245a) ) {
	    if ( defined($f245b) ) {
		$f245a .= " ".$f245b;
	    }
	    $f245a =~ s/(\.|:| \/)$//; # handle punctuation (quick'n'dirty)
	    $entry = $f245a; # ($i+1) . '. '.$f245a. ' '; # Index number is apparently in title
	}
	else {
	    # die(); # seen on 6281e96d1e01e100339cdc04 parts
	}
	
	if ( defined($f306a) ) {
	    $entry .= &human_readable_seconds($f306a);
	}

	$entry = trim_ends($entry);
	if ( $entry ) {
	    #$list[$i] = $entry;
	    $list[$#list+1] = $entry;
	}
	else {
	    print STDERR "WARNING\tMultipart part: no name nor length!\n";
	}
    }
    if ( $#{$record_array_ref} != $#list ) {
	# Some multipart parts are nameless
	print STDERR "WARNING\tSize mismatch between N multiparts and N 505\$a elements.\n";
    }
    return @list;
}


sub get_multipart_ids_from_record_array_ref($) {
    my ( $marc_record_array_ref ) = @_;
    my %multipart_ids;

    # Gather all multipart ids in comps:
    foreach my $record ( @{$marc_record_array_ref} ) {
	my $multipart_id = get_multipart_id(\$record);
	if ( $multipart_id ) {
	    $multipart_ids{$multipart_id} = 1;
	}
    }
    return sort keys %multipart_ids;
}

sub copy_multipart_isrc($$) {
    my ( $base_record_ref, $marc_record_array_ref) = @_;

    # Sometimes the order of tracks is not the same as the order of ISRCs,
    # Thus we have to do this in two steps (1: gather and sort, 2: add to base).

    # Gather:
    my @content = ();
    my $nth = 1;
    foreach my $curr_record ( @{$marc_record_array_ref} ) {
	my @f024 = $curr_record->get_all_matching_fields('024', undef);
	# Should we copy other identifiers?
	my $seen=0;
	foreach my $isrc_field ( @f024 ) {
	    #die($#f024);
	    if ( $isrc_field->{content} =~ /^0/ ) {
		if ( $seen ) { die(); }
	 	my $new_content = $isrc_field->{content};
		$new_content .= "\x1FqOsa $nth";
		push @content, $new_content;
		$seen++;
	    }
	}
	$nth++;
    }
    # Sort:
    @content = sort(@content);
    # Add:
    foreach my $value ( @content ) {
	add_marc_field($base_record_ref, '024', $value);
    }
    
}

sub multipart_records2field_773_content($$) {
    my ( $base_record_ref, $relevant_records_ref ) = @_;

    my @f773 = map { $_->get_first_matching_field('773', undef) } @{$relevant_records_ref};

    my @f773g = map { $_->get_first_matching_subfield('g') } @f773;

    my %result;

    foreach my $g ( @f773g ) {
	my $index;
	my $key;
	if ( $g =~ /^Raita (\d+)$/ ) {
	    $index = $1;
	    $key = 'DEFAULT';
	}
	elsif ( $g =~ /^Levy (\d+), raita (\d+)$/ ) {
		$index = $2;
		$key = $1;
	}
	else {
	    die();
	}
	
	if ( !defined($result{$key}) ) {
	    $result{$key} = $index;
	}
	else {
	    $result{$key} .= ", ".$index;
	}
    }
    
    my @keys = sort keys %result;
    my $new_g = '';

    for ( my $i=0; $i <= $#keys; $i++ ) { # "1, 2, 3" => "1-3"
	$result{$keys[$i]} = normalize_tracks($result{$keys[$i]});
    }
    
    if ( $#keys == 0 ) {
	if ( $keys[0] eq 'DEFAULT' ) {
	    $new_g = $result{$keys[0]};
	}
	else {
	    if ( !$new_g ) {
		$new_g = "Levy " . $keys[0] . ', '.$result{$keys[0]};
	    }
	    else {
		die();
	    }
	}
    }
    else {
	foreach my $key ( @keys ) {
	    if ( $key eq 'DEFAULT' ) { die(); } # Raita 1?
	    if ( !$new_g ) {
		$new_g = "Levy " . $key . ', '.$result{$key};
	    }
	    else {
		$new_g .= " ; Levy " . $key . ', '.$result{$key};
	    }
	}
    }

    if ( !$new_g ) { die(); }
    $new_g =~ s/, Rai/, rai/;
    
    my $f773_content = $f773[0]->{content};
    $f773_content =~ s/\x1Fg[^\x1F]+/\x1Fg$new_g/;

    # Remove old 773 field(s) from the surviving multipart:
    @f773 = ${$base_record_ref}->get_all_matching_fields('773', undef);
    foreach my $field ( @f773 ) {
	print STDERR "REMOVE ", $field->toString(), "\n";
	${$base_record_ref}->remove_field($field);
    }
    # Add new field:
    add_marc_field($base_record_ref, '773', $f773_content);
}

	
sub get_multipart_records_from_record_array_ref($$) {
    my ( $marc_record_array_ref, $multipart_id ) = @_;
    
    my @records2merge = grep { get_multipart_id(\$_) eq $multipart_id } @{$marc_record_array_ref };

    @records2merge = sort_multiparts_by_773g(\@records2merge);
    
    if ( $#records2merge < 1 ) { die(); } # sanity check
    print STDERR ($#records2merge+1), " records(s) to be merged to $multipart_id...\n";    
    return @records2merge;
}



sub create_multipart_505($$) {
    my ( $base_record_ref, $records2merge_ref ) = @_;
    
    my @f505 = list_multipart_records_for_505($records2merge_ref);
    
    if ( $#f505 > 0 ) {
	my $content = "0 \x1FaOsat: ". join(' -- ', @f505);
	$content =~ s/([^\.])$/$1./; # Add '.' if needed.
	#${$base_record_ref}->toString();
	add_marc_field($base_record_ref, '505', $content);	    
	#die("505 for ".$multipart_id.': '.$content);
    }
    # Bit funny, but theoretically possible with empty names:
    elsif ( $#f505 == 0 ) { die(); }
}

sub get_base_record_ref($$) {
    my ( $marc_record_array_ref, $multipart_id ) = @_;
    for ( my $i=0; $i <= $#{$marc_record_array_ref}; $i++ ) {
	my $curr_record = ${$marc_record_array_ref}[$i];
	if ( get_tempo_id_from_marc_record(\${$marc_record_array_ref}[$i]) eq $multipart_id ) {
	    return \${$marc_record_array_ref}[$i]
	}
    }
    return undef;
}
    
sub handle_multiparts($) {
    my ( $marc_record_array_ref ) = @_;

    my @mids = get_multipart_ids_from_record_array_ref($marc_record_array_ref);

    foreach my $multipart_id ( @mids ) {
	print STDERR "Processing multipart id $multipart_id\n";


	# Get base record (there should always be exactly one appr 035$a)...
	my $base_record_ref = get_base_record_ref($marc_record_array_ref, $multipart_id);

	if ( !defined($base_record_ref) ) { die(); }
	
	# Get multiparts
	my @records2merge = get_multipart_records_from_record_array_ref($marc_record_array_ref, $multipart_id);
	

	# Copy isrcs (field 024)
	&copy_multipart_isrc($base_record_ref, \@records2merge);	
	
	# Create a 505 field
	create_multipart_505($base_record_ref, \@records2merge);

	# Create a 773 field for base, $g merges all multipart $gs
	multipart_records2field_773_content($base_record_ref, \@records2merge);

	
	
	#my $f773g = $curr_record->get_first_matching_subfield('773', 'g');

	# Remove multiparts
	@{$marc_record_array_ref} = grep { get_multipart_id(\$_) ne $multipart_id } @{$marc_record_array_ref };
    }
}



1;
