# nvolk_marc_record.pm
#
# Copyright (c) 2021-2023 HY (KK)
# All Rights Reserved.
#
# Author(s): <nicholas.volk@helsinki.fi>
#
# Contains classes nvolk_marc_record and nvolk_marc_field plus functions.
# This module is similar to the classic MARC::Record library, but better :D
# (I'm admittedly biased.)
# Main difference: subfields are not objects. In stead, $field->{content}
# contains the content/value of the whole field in an iso-2709-style string.
# This is way more efficient, and I also found easier to use (after one gets
# over the subfield separator character \x1F thing).

#
# \x1D  Record separator
# \x1E  Field separator
# \x1F  Subfield separator
#

use strict;
use nvolk_marc21 qw(marc21_record2leader_directory_fields marc21_dir_and_fields2arrays xml_get_first_instance only_contents remove_data_from_xml trim encoding_fixes );
#use nvolk_utf8 qw(html_escapes unicode_fixes2);
use nvolk_utf8 qw(html_escapes);


require kk_marc21_field;
#use Encode;


sub normalize_ldr4diff($) {
    my $ldr = shift;
    # Record length and base address data are meaningless at this point.
    $ldr =~ s/^...../#####/; # LDR/00-04: Record-length
    $ldr =~ s/^(.{12})...../$1     /; # LDR/12-16: Base address data
    
    return $ldr;
}
    

sub compare_two_marc_records($$$) {
    my ( $record1, $record2, $mode ) = @_;

    $mode = $mode || 'diff'; # comm? other?
    
    # 1. get tags from both records:
    my $curr_field;
    my %seen_tags;
    foreach $curr_field ( @{$record1->{fields}}, @{$record2->{fields}} ) {
	$seen_tags{$curr_field->{tag}} = 1
    }

    # LEADER:
    if ( $mode eq 'diff' ) {
	my $ldr1 = normalize_ldr4diff($record1->{leader});
	my $ldr2 = normalize_ldr4diff($record2->{leader});
	if ( $ldr1 ne $ldr2 ) {
	    print STDERR "+\tLDR     ", $ldr1, "\n";
	    print STDERR "-\tLDR     ", $ldr2, "\n";
	}
    }
    
    # FIELDS:
    my $curr_tag;
    #print STDERR "ALL TAGS: ", join(", ", sort keys %seen_tags), "\n";

    # This ain't perfect, it assumes that tags are sorted, eg. 245 comes after
    # 100. We won't notice if it ain't so. But good enough, I guess...
    foreach $curr_tag ( sort keys %seen_tags ) { # TODO: sorting of alphabetical fields
	
	my @fields1 = $record1->get_all_matching_fields($curr_tag);
	my @fields2 = $record2->get_all_matching_fields($curr_tag);

	# Remove identical rows from the end:
	if ( $mode eq 'diff' ) {
	    while ( $#fields1 > -1 && $#fields2 > -1 &&
		    $fields1[$#fields1] eq $fields2[$#fields2] ) {
		pop(@fields1);
		pop(@fields2);
	    }
	}

	my $max = $#fields1;
	if ( $max < $#fields2 ) { $max = $#fields2; }

	if ( $mode eq 'diff' ) {
	    my $cache_out = '';
	    my $cache_in = '';
	    for ( my $i=0; $i <= $max; $i++ ) {
		if ( !defined($fields1[$i]) ) {
		    $cache_out .= "+\t" . $fields2[$i]->toString . "\n";
		}
		elsif ( !defined($fields2[$i]) ) {
		    $cache_in .= "-\t" . $fields1[$i]->toString . "\n";
		}
		else {
		    my $str1 = $fields1[$i]->toString();
		    my $str2 = $fields2[$i]->toString();
		    if ( $str1 eq $str2 ) {
			#print STDERR "\t", $str1, "\n";
			print STDERR $cache_in;
			print STDERR $cache_out;
			$cache_out = '';
			$cache_in = '';
		    }
		    else {
			$cache_in  .= "-\t" . $fields1[$i]->toString . "\n";
			$cache_out .= "+\t" . $fields2[$i]->toString . "\n";
		    }
		}
	    }
	    print STDERR $cache_in;
	    print STDERR $cache_out;
	}
    }
}


package nvolk_marc_field;
use strict;
use nvolk_utf8 qw(html_escapes unicode_fixes2);

require kk_marc21_field;


sub new {
    my $class = shift;
    my $tag = shift;
    my $content = shift;

    # HACK: Handle atypical input (Aleph sequential line):
    if ( !defined($content) &&$tag =~ /^[0-9]{9} (...)(..) L (.*)$/ ) {
	# NB! Don't send LDR here... It turns into a field...
	my $tmp_tag = $1;
	$content = kk_marc21_field::sequentialToField($tag);
	$tag = $tmp_tag;
#	my $indicators = $2;
#	my $subfields = $3;
#	my $new_content = '';
#	if ( $tag !~ /^00/ ) {
#	    $new_content .= $indicators;
#	}
#	# Convert legal subfields or all subfields:
#	if ( 1 ) {
#	    $subfields =~ s/\$\$([a-z0-9])/\x1F$1/g; # legal subfields
#	}
#	else {
#	    $subfields =~ s/\$\$/\x1F/g; # all subfields
#	}
#	$new_content .= $subfields;
#	$content = $new_content;
    }
    
    if ( length($tag) != 3 ) { die("Illegal tag '$tag'"); }
    # We could do all kinds of content/tag related sanity checks here...
    my $self = { 'tag' => $tag, 'content' => $content };

    bless $self, $class;
    return $self;    
}

sub get_first_matching_subfield($$) {
    my ( $self, $subfield_code ) = @_;
    if ( $self->{content} =~ /\x1F${subfield_code}([^\x1F]+)/ ) {
	return $1;
    }
    return undef;
}

sub fix_composition($) {
    my ( $self ) = @_;
    if ( $self->{tag} =~ /^[0-9]+$/ && index($self->{content}, "\x1F") > -1 ) {
	my @subfields = split(/\x1F/, $self->{content});
	my $threshold = scalar(@subfields);
	for ( my $i=1; $i < $threshold; $i++ ) {
	    $subfields[$i] = main::unicode_fixes2($subfields[$i], 1);

	    # LRM /\x1FE2\x1F80\x1F8E/
	    $subfields[$i] =~ s/ \x1FE2\x1F80\x1F8E/ /g && die();
	    $subfields[$i] =~ s/\x1FE2\x1F80\x1F8E($| )/$1/g && die();
	    $subfields[$i] =~ s/\x1FE2\x1F80\x1F8E//g && die();
	    
	}
	$self->{content} = join("\x1F", @subfields);
    }
}


sub get_first_matching_subfield_without_punctuation($$) {
    my ( $self, $subfield_code ) = @_;
    my $content = $self->{content};
    # Oops: no subfield:
    if ( $content !~ s/^.*?\x1F$subfield_code// ) { return undef; }
    $content =~ s/\x1F(.).*$//;
    my $next_subfield_code = $1;
    if ( $self->{tag} =~ /^[1678]00$/ ) {
	if ( $next_subfield_code =~ /^[bcde]$/ ) { $content =~ s/,$//; }
}
    if ( $content !~ /([a-zA-Z0-9\)\]])$/ &&
	 $content !~ / [A-Z]\.$/ ) {
	print STDERR "WARNING: might need some cleanup: ", $self->{tag}, "\$$subfield_code '$content'\n";
    }
    return $content;    
}



sub get_nonfiling_indicator_position($) {
    my $self = shift;
    if ( $self->{tag} =~ /^(130|630|730|740)$/ ) { return 1; }
    if ( $self->{tag} =~ /^(222|240|242|243|245|830)$/ ) { return 2; }
    return 0;
}
    
    
sub get_parent_id_from_X73w($) {
    my $self = shift;
    unless ( $self->{tag} eq '773' || $self->{tag} eq '973' ) {
	return 0;
    }
    # Return first ID that looks like a Melinda ID:
    if ( $self->{content} =~ /\x1Fw(?:\(FI-MELINDA\)|FCC|\(FIN01\))(0[0-9]{8})($|\x1F)/ ) {
	return $1;
    }
    print STDERR "WARNING\tfield->get_parent_id_from_X73w() contains only crap: '", $self->toString, "'\n";
    return 0;
    
}

sub has_introductory_nonfiling_character($) {
    my $self = shift;
    if ( $self->{content} =~ /\x1Fa([\"\'\(\[]|“|¡|¿)/ ) {
	return 1;
    }
    return 0;
}

sub has_subfield($$$) {
    my ( $self, $subfield_code, $value ) = @_;
    # $subfield_code is required, and it can be a regexp, eg. [a-z].
    # $value is a string, not a regexp.
    # Undefined $value means that we only check subfield's presence.
    # $value == '' means that subfield exists, but is empty.
    if ( $self->{content} !~ /\x1F${subfield_code}/ ) { return 0; }
    if ( !defined($value) || $self->{content} =~ /\x1F${subfield_code}\Q$value\E($|\x1F)/ ) { return 1; }
    return 0;
}

sub is_identical($$) {
    my ( $self, $field ) = @_;
    if ( $self->{tag} eq $field->{tag} ) {
	#print STDERR "IDENTICAL?\n '", $self->toString(), "' vs\n '", $field->toString(), "'\n";
	
	if ( $self->{content} eq $field->{content} ) {
	    #print STDERR "SUCCESS!\n";
	    return 1;
	}
	if ( $self->{tag} =~ /^00/ ) {
	    print STDERR "FAIL!\n  ", $self->toString(), " vs\n  ", $field->toString(), "\n";
	}
    }
    return 0;
}

sub set_value($$) {
    my ( $self, $content ) = @_;
    # Raison d'etrê: sanity checks!
    if ( $self->{tag} =~ /^(0[1-9]|[1-9])/ ) {
	if ( $content !~ /^([0-9 ])/ ) {
	    die("Illegal IND1: '$1'");
	}
	if ( $content !~ /^.([0-9 ])/ ) {
	    die("Illegal IND2: $1");
	}
	if ( $content !~ /^..\x1F/ ) {
	    die("Unexpected 3rd char: '$content'");
	}
	if ( $content =~ /\x1F([^a-z0-9])/ ) {
	    die("Illegal subfield: '$1'");
	}
    }
    
    $self->{content} = $content;
    
}
sub remove_identical_subfields {
    # NB! Not wise enough to handle punctuation.
    my ( $self, $legal_subfields ) = @_;
    my @subfields = split(/\x1F/, $self->{content});
    my %seen;
    my $hits = 0;
    my $new_content = $subfields[0];
    for ( my $i=1; $i <= $#subfields; $i++ ) {
	my $value = $subfields[$i];
	# Defined skippable subfields:
	my $skip = 0;
	if ( !defined($legal_subfields) ) {
	    if ( defined($seen{$value}) ) {
		$skip = 1;
	    }
	}
	else { # only interested in certain subfields
	    my $subfield_code = substr($value, 0, 1);
	    if ( index($legal_subfields, $subfield_code) > -1 ) {
		if ( defined($seen{$value}) ) {
		    $skip = 1;
		    #die("SF=$subfield_code VAL='$value' TARGET='$legal_subfields'");
		}	

	    }

	}
	# Store non-skippable subfield content:
	if ( !$skip ) {
	    $new_content .= "\x1F".$value;
	    $hits++;
	}
	
	$seen{$value} = 1;
    }
    if ( !$hits ) { return; }

    $self->{content} = $new_content;
}



sub has_kk_subfield9($) {
    my ( $self ) = @_;
    if ( $self->{content} =~ /\x1F9(FENNI|FIKKA|VIOLA)<KEEP>/ ) {
	return 1;
    }
    return 0;
}

sub content_requires_replication($$) {
    my ( $self, $content ) = @_;
    if ( $content ) {
	if ( $content =~ /\x1F9(FENNI|FIKKA|VIOLA)<KEEP>/ ||
	     $self->has_kk_subfield9() ) {
	    return 1;
	}
	# Added FI-Vapaa on 2021-12-16:
	if ( $content =~ /\x1F5(FENNI|FIKKA|FI-Vapaa|VIOLA)/ ||
	     $self->{content} =~ /\x1F5(FENNI|FIKKA|FI-Vapaa|VIOLA)/ ) {
	    return 1;
	}
    }
    return 0;    
}

sub tag_requires_replication($$) {
    my ( $self, $tag ) = @_;
    if ( !$tag || $self->{tag} eq '901' ) {
	return 0;
    }
    
    if ( $self->content_requires_replication($self->{content}) ) {
	return $self->{tag} ne $tag;
    }
    return 0;
}


sub field_requires_replication {
    my ( $self, $new_content, $new_tag ) = @_;

    # Removing dot from keep does not trigger requiredness
    # (A temporary hack that can be removed after cleaning Melinda.)
#    my $tmp = $self->{content};
#    if ( $tmp =~ s/<KEEP>\.($|\x1F)/<KEEP>$1/ &&
#	 #die("'$tmp' vs '$new_content'") &&
#	 $tmp eq $new_content ) {
#	return 0;
#    }

    # Content does not matter here:
    if ( $self->{tag} eq '901' ) {
	return 0;
    }
    
    if ( $self->content_requires_replication($new_content) ||
	 $self->tag_requires_replication($new_tag) ) {
	return 1;
    }
    return 0;
}


my $order773 = '67iatpsbdmhkxyzuogqw';
my %default_subfield_order = ( '028' => '6baq',
			       '100' => '6abcqde059',
			       '110' => '6ae059',
			       '600' => '6abcqde059',
			       '610' => '6ae059',
			       '700' => '6abcqde059',
			       '710' => '6ae059',
			       # 773$i, 773$b...
			       '773' => "$order773",
			       '800' => '6abcqde059',
			       '810' => '6ae059',
			       '973' => "$order773" );


sub swap_subfields {
    my ( $self, $order ) = @_;
    my $tmp = $self->toString();
    # Get default value if $order is not defined:
    if ( !defined($order) ) {
	if ( defined($default_subfield_order{$self->{tag}}) ) {
	    $order = $default_subfield_order{$self->{tag}};
	}
	else {
	    #print STDERR "WARNING\tswap subfields(): No specs for ", $self->{tag}, "\n";
	    return;
	}
    }
    
    #print STDERR "swap_subfield($order): ", $self->toString(), "\n";

    # Sort subfields:
    while ( $order =~ s/^(.)(.+)$/$2/ ) {
	my $curr_subfield_code = $1;
	my $other_subfield_codes = $2;
	if ( index($other_subfield_codes, $curr_subfield_code) > -1 ) { die(); }
	my $group = '['.$other_subfield_codes.']';
	#print STDERR "  Trying to swap '$curr_subfield_code' and '$group'. . .\n";
	while ( $self->{content} =~ s/(\x1F$group[^\x1F]*)(\x1F${curr_subfield_code}[^\x1F]*)/$2$1/ ) {
	    print STDERR "  Swap '$1' <=> '$2'\n";
	}
    }

    # Hack: $9 ^^ should always come first:
    if ( $order =~ /9/ && $self->{content} =~ /\x1F9\^\^?($|\x1F)/ ) {
	while ( $self->{content} =~ s/(\x1F[^9][^\x1F]*)(\x1F9\^\^?)($|\x1F)/$2$1$3/ ) { die($self->{content}); } # untested
    }
}


sub update_controlfield_character_position {
    my $self = shift;
    my @args = @_;

    my $original_value = $self->toString();

    if ( $self->{content} !~ /\x1F/ ) {
	my $tmp = $self->{content};
	
	#print STDERR " substr('", $tmp, "', ", join(", ", @args), ")\n";

	
	#substr($self->{content}, @args); # does not work!
	if ( $#args == 1 ) {
	    substr($self->{content}, $args[0], length($args[1]), $args[1]);
	    my $new_value = $self->toString();
	    if ( $new_value ne $original_value ) {
		print STDERR " '$original_value' =>\n '$new_value'\n";
	    }
	}
	else {
	    die();
	}

    }
}

sub tag2val {
    my $self = shift;
    my $tag = $self->{tag};
    my $content = $self->{content};
    # SORT ORDER...
    if ( $tag eq 'LDR' ) { return 0; }

    if ( $tag =~ /^[1-9][0-9][0-9]$/ ) {
	if ( $tag =~ /^(648|650|651|655)$/ ) {
	    if ( $content =~ /^.([012356])/ ) {
		$tag += (0.1 * $1);
	    }
	    elsif ( $content =~ /^.4/ ) {
		$tag += 0.8;
	    }
	    elsif ( $content =~ /^.7/ ) {
		$tag += 0.7;
		# $2 order:
		if ( $content =~ /\x1F2yso\/fin/ ) {
		    if ( $content =~ /\x1F9FENNI<KEEP>/ ) {
			# best
		    }
		    else {
			$tag += 0.001;
		    }
		}
		elsif ( $content =~ /\x1F2yso\/swe/ ) {
		    $tag += 0.005;
		}
		elsif ( $content =~ /\x1F2slm\/fin/ ) {
		    if ( $content =~ /\x1F9FENNI<KEEP>/ ) {
			$tag += 0.010;
		    }
		    else {
			$tag += 0.011;
		    }
		}
		elsif ( $content =~ /\x1F2slm\/swe/ ) {
		    $tag += 0.015;
		}
		else {
		    $tag += 0.095;
		}
	    }
	    else {
		$tag += 0.9;
	    }
	}
	return $tag;
    }

    if ( $tag =~ /^0([1-9][0-9])$/ ) { return $1; }
    if ( $tag =~ /^00([1-9])$/ ) { return $1; }

    # Tail is aleph tags (excluding LDR), in randomish order, except
    # LOW comes very last, and CAT is second last.
    # Also CAT fields are sorted internally based on timestamp
    if ( $tag eq 'CAT' ) { # The later the date, the later the field should come
	my $base = '9998';
	if ( $content =~ /\x1Fc(\d+)/ ) { 
	    $base .= '.'.$1; # Add day
	    if ( $content =~ /\x1Fh(\d+)/ ) { # hours
		$base .= $1; # Add hour
	    }
	}
	return $base;
    }
    if ( $tag eq 'LOW' ) { return 9999; }
    return 1000; 
}

sub toMarcXML() {
    my $self = shift();
    my $content = $self->{content};
    # Fields 001-009
    if ( $self->{tag} =~ /^00[1-9]$/ ) {
	$content =~ s/\^/ /g; # Normalize Aleph notation
	return "  <controlfield tag=\"".$self->{tag}."\">".$content."</controlfield>\n";
    }
    # Rest of the fields:
    if ( $content =~ /..\x1F/ ) {
	my @subs = split(/\x1F/, $self->{content});
	my $ind1 = substr($subs[0], 0, 1);
	my $ind2 = substr($subs[0], 1, 1);
	my $output = "  <datafield tag=\"".$self->{tag}."\" ind1=\"$ind1\" ind2=\"$ind2\">\n";

	shift @subs; # remove indicator part

	for ( my $i=0; $i <= $#subs; $i++ ) {
	    my $sf = $subs[$i];
	    my $sf_code = substr($sf, 0, 1);
	    my $sf_data = substr($sf, 1);
	    if ( $sf_data eq '' ) {
		$output .= "   <subfield code=\"$sf_code\"/>\n";
	    }
	    else {
		$output .= "   <subfield code=\"$sf_code\">".main::html_escapes($sf_data)."</subfield>\n";
	    }	    
	}
	$output .= "  </datafield>\n";
	return $output;
    }
    # Corrupted data. Trouble. Whatever.
    die();
}


sub toOAIXML() {
    my $self = shift();

    # Fields 001-009
    if ( $self->{tag} =~ /^00[1-9]$/ ) {
	return "        <fixfield id=\"".$self->{tag}."\">".$self->{content}."</fixfield>\n";
    }
    # Rest of the fields:
    if ( $self->{content} =~ /..\x1F/ ) {
	my @subs = split(/\x1F/, $self->{content});
	my $ind1 = substr($subs[0], 0, 1);
	my $ind2 = substr($subs[0], 1, 1);
	my $output = "        <varfield id=\"".$self->{tag}."\" i1=\"$ind1\" i2=\"$ind2\">\n";

	shift @subs; # remove indicator part

	
	for ( my $i=0; $i <= $#subs; $i++ ) {
	    my $sf = $subs[$i];
	    my $sf_code = substr($sf, 0, 1);
	    my $sf_data = substr($sf, 1);
	    if ( $sf_data eq '' ) {
		$output .= "          <subfield label=\"$sf_code\"/>\n";
	    }
	    else {
		$output .= "          <subfield label=\"$sf_code\">".main::html_escapes($sf_data)."</subfield>\n";
	    }	    
	}
	$output .= "        </varfield>\n";
	return $output;
    }
    # Corrupted data. Trouble. Whatever.
    die();
}



sub toString($) {
    my $self = shift();

    my $string = $self->{tag} . "  ";

    return $string . kk_marc21_field::fieldToString($self->{content});

    # Make content human readable:
    my $content = $self->{content};
    if ( $content =~ /\x1F/ ) { # has subfield(s) === non-control-field
	# Visible indicators:
	$content =~ s/^ /#/;
	$content =~ s/^(.) /$1#/;
	# Subfield sepatators:
	$content =~ s/\x1F(.)/ ‡$1 /g; 
    }
    else { # control-field
	$content =~ s/ /\#/g; # '^' is aleph-style, '#' is validish as well
    }
    $string .= $content;
    return $string;
}


##########################
package nvolk_marc_record;
##########################
## TODO: fix main::some_sub() stuff...
use strict;


sub new {
    my $class = shift;
    my $data = shift;
    my $self;
    $self->{leader} = "     n?? a22     4i 4500";
    my @array;
    $self->{fields} = \@array;

    bless $self, $class;

    # TODO: check LDR/17=4
    # New record: create only LDR
    if ( !defined($data) || $data eq '' ) {
	
    }
    elsif ( $data =~ /^</ ) {
	if ( $self->_is_marcxml($data) ) {
	    
	    $self->_process_marcxml($data);
	}
	else {
	    #print STDERR "Record is not marcxml, trying OAI...\n";
	    if ( !$self->_process_oai_marc($data) ) {
		die();
		return undef;
	    }
	}
    }
    # Convert Marc21 in iso-2709 format into a data struct:
    elsif ( $data =~ /^[0-9]{5}[a-z].{14}4500(...[0-9]{9})*\x1E/ ) {
	# TODO: Parse marc21 within eval...
	my ( $leader, $directory, $fields ) = main::marc21_record2leader_directory_fields($data);
	my ( $tags_ref, $contents_ref ) = main::marc21_dir_and_fields2arrays($directory, $fields);
	my @tags = @$tags_ref;
	my @contents = @$contents_ref;

	$self->{leader} = $leader;
	for ( my $i=0; $i <= $#tags; $i++ ) {
	    $self->add_field($tags[$i], $contents[$i]);
	}
    }
    elsif ( $data =~ /^[0-9]+ (FMT|LDR).. L / ) { # Aleph sequential
	my @lines = split(/\n/, $data);
	for ( my $i=0; $i <= $#lines; $i++ ) {
	    my $curr_line = $lines[$i];
	    if ( $curr_line =~ /^[0-9]{9} (...).. L (.*)/ ) {
		my $tag = $1;
		my $content = $2;
		if ( $tag eq 'FMT' ) {
		    # Do nothing
		}
		elsif ( $tag eq 'LDR' ) {
		    if ( length($content) != 24 ) { die("Unexpected length for LDR '$content'"); }
		    $content =~ s/\^/ /g;
		    $self->{leader} = $content;
		}
		else {
		    $self->add_field($curr_line, undef);
		}
	    }
	}
    }
    # Marc record as per KB's Libris
    elsif ( $data =~ /^\{"fields":/ ) { # Json
	# Load JSON::Parse only when required
	eval {
	    require JSON::Parse;
	} or do {
	    die("JSON input requires JSON::Parse module"); # Damn, this requires manual installation,
	};


	my $struct = JSON::Parse::parse_json($data);
	my %json = %{$struct};
	$self->{leader} = $json{'leader'};
	#print STDERR "LEADER: '", $self->{leader}, "'\n";
	my @fields = @{$json{'fields'}};
	foreach my $field ( @fields ) {
	    my %field_hash = %{$field};

	    foreach my $tag ( sort keys %field_hash ) { # There's only one key
		#print STDERR "FIELD $tag...\n";
		my $value = $field_hash{$tag};
		if ( $tag !~  /^00/ ) {
		    my %contents = %{$value};
		    $value = $contents{'ind1'}.$contents{'ind2'};
		    my @subfields = @{$contents{'subfields'}};
		    foreach my $sf ( @subfields ) {
			my %subfield_hash = %{$sf};
			foreach my $code ( sort keys %subfield_hash ) { # There's only one key
			    $value .= "\x1F$code".$subfield_hash{$code};
			}
		    }
		    
		}
		$self->add_field($tag, $value);
	    }
	}
    }
    else {
	print STDERR "ERROR\tUnhandled/unrecognized input type!\n$data\n";
	return undef;
    }


    return $self;
}

sub _is_marcxml($$) {
    my ( $self, $xml ) = @_;
    my $record = main::xml_get_first_instance($xml, 'record');
    if ( !defined($record) ) {
	return 0;
    }
    my $ldr = main::xml_get_first_instance($record, 'leader');
    if ( !$ldr ) {
	return 0;
    }
    
    return 1;
}

sub _process_marcxml($$) {
    my ( $self, $data ) = @_;
    # NB! Return but one (first) record
    # FFS! XML::XPath converts perfectly valid utf-8 (bytes) to a "string".
    # NB! Makes too many assumptions with regexps... Needs improveing!
    my $xml = $data;
    
    my $record = main::xml_get_first_instance($xml, 'record');
    if ( !defined($record) ) {
	print STDERR "Input is not marcxml (does not contain <record>).\n";
	return 0;
    }
    $record = main::only_contents($record);
    #print STDERR "GOT RECORD '$record'\n";
    # PROCESS LEADER:
    my $ldr = main::xml_get_first_instance($record, 'leader');
    if ( $ldr ) {
	$record = main::remove_data_from_xml($record, $ldr);
	$ldr = main::only_contents($ldr);
	$ldr =~ tr/#/ /; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
	$ldr =~ tr/^/ /;
	$self->{leader} = $ldr;
    }
    else {
	print STDERR "  Input is not marcxml (does not contain <leader>).\n";
	#print STDERR "ERROR\tUnhandled/unrecognized XML input type!\n"; # $record\n";
	return undef;
    }
    
    my $proceed = 1;
    while ( $proceed ) {
	$record = main::trim($record);
	$proceed = 0;
	if ( $record =~ s/^<controlfield tag=\"(...)\">([^<]+)<\/controlfield>\s*//s ) {
	    my $tag = $1;
	    my $content = $2;
	    
	    $content =~ s/(\#|\^)/ /g; # '#': TAV2-data, Mintun bugiraportti, Melinda 7322871:
	    #print STDERR "GOT CONTROLFIELD $tag: '$content'\n";
	    $self->add_field($tag, $content);
	    $proceed = 1;
	}
	elsif ( $record =~ /^<datafield tag=\"(...)\" ind1=\"(.)\" ind2=\"(.)\">/ ) {
	    my $tag = $1;
	    my $ind1 = $2;
	    my $ind2 = $3;
	    my $str = '';
	    my $datafield = main::xml_get_first_instance($record, 'datafield');
	    
	    #print STDERR "GOT DATAFIELD $tag i1 '$ind1' i2 '$ind2'\n";
	    #print STDERR "DF v1 '$datafield'\n";
	    $record = main::remove_data_from_xml($record, $datafield);
	    $datafield = main::only_contents($datafield);
	    #print STDERR "DF v2 '$datafield'\n";
	    my $proceed2 = 1;
	    while ( $proceed2 ) {
		$datafield = main::trim($datafield);
		#print STDERR "DATAFIELD: '$datafield'\n";
		$proceed2 = 0;
		if ( $datafield !~ /\S/ ) { }
		elsif ( $datafield =~ s/^<subfield code=\"(.)\">(.*?)<\/subfield>\s*// ) {
		    my $sfcode = $1;
		    my $sfvalue = $2;
		    $str .= "\x1F${sfcode}${sfvalue}";
		    #print STDERR "IS NOW '$str'\n";
		    $proceed2 = 1;
		}
		else {
		    die($datafield);
		}
	    }
	    if ( $str ne '' ) {
		$str = main::encoding_fixes($str);
		#print STDERR "NVV $tag $ind1 $ind2 '$str'\n";
		$self->add_field($tag, "$ind1$ind2$str");
		$proceed = 1;
	    }
	    else {
		die();
	    }
	    
	}
    }
    
    if ( !defined($self->{leader}) || length($record) ) {
	die("TODO\tCONVERT XML INPUT TO A DATA STRUCT\nREMAINS:\n'$record'");
    }
    return 1;
}

sub _process_oai_marc($$) {
    my ( $self, $data ) = @_;
    # FFS! XML::XPath converts perfectly valid utf-8 (bytes) to a "string".
    # NB! Makes too many assumptions with regexps... Needs improving!
    my $xml = $data;

    my $record = main::xml_get_first_instance($xml, 'record');
    $record = main::xml_get_first_instance($record, 'oai_marc');
    $record = main::only_contents($record);

    my $proceed = 1;
    my $seen_ldr = 0;
    while ( $proceed ) {
	$record = main::trim($record);
	$proceed = 0;
	#print STDERR "  proceeding\n$record\n\n";
	if ( $record =~ s/^<fixfield id=\"LDR\">([^<]+)<\/fixfield>\s*//s ) {
	    if ( $seen_ldr ) {
		print STDERR "MULTIPLE LEADERS! 2ND LDR: '$seen_ldr'\n";
		print STDERR $data, "\n";
		die($self->{leader});
	    }
	    my $leader = $1;
	    $leader =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
	    $leader =~ tr/^/ /;
	    if ( length($leader) != 24 ) { die("LDR lenght is not 24!"); }
	    
	    $self->{leader} = $leader;
	    #print STDERR "Add leader '$leader'\n"; die();
	    $seen_ldr = 1;
	    $proceed = 1;
	}
	elsif ( $record =~ s/^<fixfield id=\"(...)\">([^<]+)<\/fixfield>\s*//s ) {
	    my $tag = $1;
	    my $content = $2;
	    $content =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871
	    $content =~ tr/^/ /;
	    if ( $content =~ /(\^|\#)/ ) { die($content); }
	    $self->add_field($tag, $content);
	    $proceed = 1;
	}
	elsif ( $record =~ s/^<varfield id=\"(...)\" i1=\"(.)\" i2=\"(.)\">\s*<\/varfield>\s*//s ) {
	    print STDERR "TAG $1 has no content. Not bringing it along...\n";
	    $proceed = 1;
	}
	elsif ( $record =~ /^<varfield id=\"(...)\" i1=\"(.)\" i2=\"(.)\">/ ) {
	    my $tag = $1;
	    my $ind1 = $2;
	    my $ind2 = $3;
	    my $str = '';
	    my $varfield = main::xml_get_first_instance($record, 'varfield');
	    $record = main::remove_data_from_xml($record, $varfield);
	    
	    $varfield = main::only_contents($varfield);

	    my $proceed2 = 1;
	    while ( $proceed2 ) {
		$varfield = main::trim($varfield);
		$proceed2 = 0;
		$varfield =~ s|^(<subfield label="(.)")/>|$1></subfield>|;
		    
		if ( $varfield !~ /\S/ ) { }
		elsif ( $varfield =~ s/^<subfield label=\"(.)\">(.*?)<\/subfield>\s*// ) {
		    my $sfcode = $1;
		    my $sfvalue = $2;
		    
		    $str .= "\x1F${sfcode}${sfvalue}";
		    $proceed2 = 1;
		}
		else {
		    die($varfield);
		}
	    }
	    
	    if ( $str ne '' ) {
		$str = main::encoding_fixes($str);
		$str = "$ind1$ind2$str";
		my $field = $self->add_field($tag, $str);
		#print STDERR "ADD FIELD $tag: '$str'\n";
		#print STDERR $field->toString($field), "\n";
		$proceed = 1;
	    }
	    else {
		die("TAG $tag\n$record\nTAG $tag");
		#die($record);
	    }
	}
	elsif ( $record =~ /\S/ ) {
	    die("Unhandled stuff: ".$record);
	}
    }
	

    if ( !$seen_ldr || length($record) ) {
	die("TODO\tCONVERT XML INPUT TO A DATA STRUCT\nREMAINS:\n'$record'");
    }
    return 1;
    
}

sub insert_field($$) {
    my ( $self, $new_field ) = @_;
    # Check data field content:
    if ( $new_field->{tag} =~ /^(0[1-9]|[1-9][0-9])[0-9]$/ ) {
	# This crashes on purpose, so that programming errors
	# won't cause terrible damage.
	# However, this means that some corrupted data needs to be fixed
	# manually.
	unless ( $new_field->{content} =~ /^[a-z0-9 ]{2}\x1F/ ) {
	    die($new_field->toString());
	}
    }
    push(@{$self->{fields}}, $new_field);
    return $new_field;

}

sub add_field($$$) {
    my ( $self, $tag, $content ) = @_;
    my $new_field = new nvolk_marc_field($tag, $content);
    return $self->insert_field($new_field);
}

sub add_unique_field($$$) {
    my ( $self, $tag, $content) = @_;
    if ( $self->containsFieldWithValue($tag, $content) ) {
	return undef; # Already seen, no need to add
    }
    return $self->add_field($tag, $content);
}

sub containsFieldWithValue($$$) {
    my ( $self, $tag, $value ) = @_;
    my @fields = $self->get_all_matching_fields($tag);
    for ( my $i=0; $i <= $#fields; $i++ ) {
	if ( defined($value) ) {
	    if ( $fields[$i]->{content} eq $value ) {
		return $fields[$i];
	    }
	}
	else {
	    return $fields[$i];
	}
    }
    return 0;
}

sub has_LOW($$) {
    my ( $self, $LOW ) = @_;
    return $self->containsFieldWithValue('LOW', "  \x1Fa".$LOW);
}
    
sub containsSubfieldWithValue($$$$) {
    my ( $self, $tag, $subfield_code, $value ) = @_;
    
    my @fields = $self->get_all_matching_fields($tag);
    for ( my $i=0; $i <= $#fields; $i++ ) {
	#print STDERR "containsSubfieldWithValue($tag, $subfield_code, $value) against '", $fields[$i]->toString(), "'\n";
	if ( $fields[$i]->{content} =~ /\x1F\Q${subfield_code}$value\E($|\x1F)/ ) {
	    return $fields[$i];
	}
    }
    return 0;
}
    

sub modify_fields_through_callback($$$) {
    my ( $self, $tag, $callback ) = @_;
    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;
    my $mods = 0;
    for ( my $i=0; $i <= $#fields; $i++ ) {
	my $curr_field = $fields[$i];
	#print STDERR "MFTC ('$tag'): '",$curr_field->{tag}, ": ",$curr_field->{content},"\n";
	if ( $callback && $curr_field->{tag} =~ /^$tag$/ ) {
	    #print STDERR "MFTC2: '",$curr_field->{tag}, ": ",$curr_field->{content},"\n";
	    my $tmp = &$callback($curr_field->{content});
	    if ( $tmp ne $curr_field->{content} ) {
		print STDERR "OLD ", $curr_field->{tag}, ": '", @{$fieldsP}[$i]->{content}, "'\n";
		print STDERR "NEW ", $curr_field->{tag}, ": '$tmp'\n";

		@{$fieldsP}[$i]->{content} = $tmp;
		#die();
		$mods++;
	    }
	}
    }
    return $mods;
}

sub get_first_matching_field_index($$) {
    my ( $self, $tag ) = @_;

    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;
    #print STDERR "DEBUG: marc record has ", ($#fields+1), " fields.\n";
    for ( my $i=0; $i <= $#fields; $i++ ) {
	my $curr_field = $fields[$i];
	if ( $curr_field->{tag} =~ /^$tag$/ ) {
	    return $i;
	}
    }
    return -1;
}

sub get_first_matching_field($$) {
    my ( $self, $tag ) = @_;

    my $index = $self->get_first_matching_field_index($tag);
    if ( $index == -1 ) { return undef; }
    return $self->{fields}[$index];
}

#sub get_first_matching_field_content($$) {
#    my ( $self, $tag ) = @_;
#
#    my $index = $self->get_first_matching_field_index($tag);
#    if ( $index == -1 ) { return undef; }
#    my $field = $self->{fields}[$index];
#    return $field->{content};
#}

sub get_first_matching_field_content($$) {
    my ( $self, $tag ) = @_;
    my $field = $self->get_first_matching_field($tag);
    if ( !defined($field) ) { return undef; }
    return $field->{content};
}


sub get_first_matching_subfield($$$) {
    my ( $self, $tag, $subfield_code ) = @_;
    # Shouldn't we get all fields here?
    my $index = $self->get_first_matching_field_index($tag);
    if ( $index == -1 ) { return undef; }
    # Is this correct? What if first field does not contains given subfield,
    # but second field does? FIX!
    return $self->{fields}[$index]->get_first_matching_subfield($subfield_code);
}

sub get_all_matching_subfields($$$) {
    my ( $self, $tag, $subfield_code ) = @_;

    my @full_fields = $self->get_all_matching_fields($tag);
    my @arr;
    for ( my $i=0; $i <= $#full_fields; $i++ ) {
	my $curr_field = $full_fields[$i];
	my $subfield_data = $curr_field->get_first_matching_subfield($subfield_code);
	if ( defined($subfield_data) ) {
	    $arr[$#arr+1] = $subfield_data;
	}
    }
    return @arr;
}

sub get_all_matching_subfields_without_punctuation($$$) {
    my ( $self, $tag, $subfield_code ) = @_;

    my @full_fields = $self->get_all_matching_fields($tag);
    my @arr;
    for ( my $i=0; $i <= $#full_fields; $i++ ) {
	my $curr_field = $full_fields[$i];
	my $subfield_data = $curr_field->get_first_matching_subfield_without_punctuation($subfield_code);
	if ( defined($subfield_data) ) {
	    $arr[$#arr+1] = $subfield_data;
	}
    }
    return @arr;
}



sub get_all_matching_fields($$) {
    my ( $self, $tag ) = @_;
    return grep { $_->{tag} =~ /^$tag$/ } @{$self->{fields}};
}


sub get_all_matching_field_contents($$) {
    my ( $self, $tag ) = @_;
    my @fields = $self->get_all_matching_fields($tag);
    return map { $_->{content} } @fields;
}

sub get_id($) {
    my ( $self ) = @_;
    my $f003 = $self->get_first_matching_field_content('003');
    my $f001 = $self->get_first_matching_field_content('001');
    if ( defined($f003) ) {
	return "($f003)$f001";
    }
    return $f001;
}


sub remove_field($$) {
    my ( $self, $field ) = @_;
    #print STDERR "try to remove_field('", $field->toString(), "')...\n";


    
    # NB! This last identical field is removed. So this does not necessarily
    # remove the $field object.
    # Risky with $8 and $9 at least...
    for ( my $i = $#{$self->{fields}}; $i >= 0 ; $i-- ) {
	# Remove first tag+content match (from the end):
	if ( ${$self->{fields}}[$i]->is_identical($field) ) {
	    splice(@{$self->{fields}}, $i, 1);
	    #print STDERR "Removal should be ok.\n";
	    return 1;
	}
    }
    print STDERR "ERROR\tNo field '", $field->toString(), "' removed...\n";
    return 0;
}

#sub remove_duplicates($$) {
#    my ( $self, $tag ) = @_;
#    my @fields = @{$self->{fields}};
#    my %seen;
#    for ( my $i = 0; $i <= $#fields ; $i++ ) {
#	my $curr_field = $fields[$i];
#	# Skip $6-, $8- and $9-chains ('^' is related to $9 chain) 
#	if ( $curr_field->{tag} =~ /^${tag}$/ && $curr_field->{content} !~ /\x1F(6|8|9\^)/ && $curr_field->{content} =~ /\^($|\x1F)/ ) {
#	    my $str = $curr_field->toString();
#	    if ( !defined($seen{$str}) ) {
#		$seen{$str} = 1;
#	    }
#	    else {
#		print STDERR "REMOVE '$str'\n";
#		print STDERR "REASON: Duplicate field\n";
#		$self->remove_field($curr_field);
#
#		#die(); # still untested
#	    }
#	}
#    }
#
#    # TODO: Remove $6, $8 and $9 chains
#}

sub update_controlfield_character_position {
    my $self = shift;
    my $tag = shift;
    my @args = @_;
    my $index = $self->get_first_matching_field_index($tag);
    if ( $index > -1 ) {
	#print STDERR " rsc(): ", join(", ", @args), "\n";
	$self->{fields}[$index]->update_controlfield_character_position(@args);
    }
    
}

sub sort_fields {
    my $self = shift;

    my $fieldsP = $self->{fields};

    my @fields = @{$fieldsP};

    my $upper_limit = $#fields;
    for ( my $j = 0; $j < $upper_limit; $upper_limit-- ) {
	for ( my $i=0; $i < $upper_limit; $i++ ) {
	    if ( $fields[$i]->tag2val() > $fields[$i+1]->tag2val() ) {
		my $tmp = $fields[$i];
		$fields[$i] = $fields[$i+1];
		$fields[$i+1] = $tmp;
		#print STDERR "SWAP at $i: '", $tmp->toString(), "' vs '", $fields[$i]->toString(), "'\n";
	    }
	}
    }
    
    $self->{fields} = \@fields;
}


sub toAlephSequential($$) {
    my ( $self, $prefix ) = @_;
    my $field = $self->get_first_matching_field('001');
    if ( !defined($prefix) ) {
	if ( !defined($field) ) {
	    die("FATAL\tRecord has no 001");
	}
	$prefix = $field->{content};
    }

    $prefix = sprintf("%09d", $prefix);

    # Q: Should we add a missing 001
    # Q: What if prefix and 001 mismatch? Should we change 001? 
    # Q: Should we check that length is exactly 9 chars?
    # A: No. All three are Someone Else's Problems.

    # NB! No FMT field is created! (And it's a feature.)
    
    # Create Leader:
    my $ldr = $self->{leader};
    $ldr =~ s/ /\^/g;
    my $result = "$prefix LDR   L $ldr\n";
    # Create data:
    my $fields_ref = $self->{fields};
    my @fields = @{$fields_ref};
    for ( my $i=0; $i <= $#fields; $i++ ) {
	#print STDERR "FIELD $i/", ($#Fied
	my $curr_field = $self->{fields}[$i];
	my $content = $curr_field->{content};
	$result .= $prefix.' '.$curr_field->{tag};
	if ( $curr_field->{tag} =~ /^00[1-9]$/ ) {
	    $content =~ s/ /\^/g;
	    $result .= "   L ".$content."\n";
	}
	else {
	    $content =~ s/^(..)//;
	    $result .= $1.' L ';
	    $content =~ s/\x1F/\$\$/g;
	    $result .= $content."\n";
	}
    }
    return $result;
}

sub toMarc21($) {
    my $self = shift();
    return $self->toISO2709();
    
}
sub toISO2709($) {
    my $self = shift();
    my $marc21_string = '';

    my $starting_pos;
    # Create Leader:
    my $leader = $self->{leader};
    my $directory = '';
    my $fields = '';
    
    # Create data:
    my $fields_ref = $self->{fields};
    my @fields = @{$fields_ref};
    for ( my $i=0; $i <= $#fields; $i++ ) {
	my $curr_field = $self->{fields}[$i];
	my $content = $curr_field->{content} . "\x1E";

	## Add 12-char directory entry to directory:

	# set flen:
	my $flen = length($content);
	if ( $flen > 9999 ) { die(); }
	$flen = sprintf("%04s", $flen);
	# set strarting_pos
	my $starting_pos = length($fields);
	if ( $starting_pos > 99999 ) { die(); }
	$starting_pos = sprintf("%05s", $starting_pos);
	# combine them:
	my $dir_row = $curr_field->{tag} . $flen . $starting_pos;
	# ...and finally add:
	$directory .= $dir_row;

	# Add field's content to fields:	
	$fields .= $content;
    }

    my $new_record = $leader . $directory . "\x1E" . $fields . "\x1D";
    ## Update record length:
    # Update LDR/00-04:
    my $l = length($new_record);
    $l = sprintf("%05s", $l);
    $new_record =~ s/^...../$l/; # substr would be faster...
    # Update LDR/12-16:
    $new_record =~ /\x1E/ or die();
    my $tmp = $`; # $tmp contains everything before first \x1E field separator
    $l = length($tmp)+1; # +1 is for the \x1E separator
    $l = sprintf("%05s", $l);
    $new_record =~ s/^(.{12})(.....)/$1$l/;
    #print STDERR "WARNING\tMarc21 results haven't been tested yet!\n";
    return $new_record;
}

sub alephify($) {
    my ( $self ) = @_;
    $self->{leader} =~ s/#/\^/g; # Hack corrupted data. (Is this still needed?)
    $self->{leader} =~ s/ /\^/g;

    my $tmpsub = sub {
	my $tmp = shift;
	if ( $tmp =~ s/ /\^/g ) { die(); } # test whether this happens...
	return $tmp;
    };
    
#    $self->modify_fields_through_callback('00.', $tmpsub);
}

sub toOAIXML($) {
    my ( $self ) = @_;
    # Header:
    my $output = '<?xml version = "1.0" encoding = "UTF-8"?>
<find-doc 
  xmlns="http://www.loc.gov/MARC21/slim" 
  xmlns:slim="http://www.loc.gov/MARC21/slim" 
  xmlns:oai="http://www.openarchives.org/OAI/1.1/oai_marc">
  <record>
    <metadata>
      <oai_marc>
	';
    $output .= "        <fixfield id=\"LDR\">" . $self->{leader} . "</fixfield>\n";    
    # Main stuff:
    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;
    for ( my $i=0; $i <= $#fields; $i++ ) {
	my $curr_field = $fields[$i];
	$output .= $curr_field->toOAIXML();
    }
    
    # Tailer:
    $output .= "      </oai_marc>
    </metadata>
  </record>
</find-doc>
";
    return $output;
}


sub toMarcXML() {
    my ( $self ) = @_;
    ## Header:
    # NB! The xmlns attribute is needed by marc2bibframe2
    my $output = '<record xmlns="http://www.loc.gov/MARC21/slim">
';
    my $leader = $self->{leader};
    $leader =~ s/\^/ /g; # Normalize Aleph notation
    $output .= " <leader>" . $leader . "</leader>\n";    
    # Main stuff:
    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;
    for ( my $i=0; $i <= $#fields; $i++ ) {
	my $curr_field = $fields[$i];
	$output .= $curr_field->toMarcXML();
    }
    
    # Tailer:
    $output .= "</record>\n";

    return $output;
}



sub toString() {
    my $self = shift();

    my $tmp_ldr = $self->{leader};
    $tmp_ldr =~ s/ /\#/g; # '^' was Aleph style
    my $string = "LDR  " . $tmp_ldr . "\n";

    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;
    # print STDERR "DEBUG: marc record has ", ($#fields+1), " fields.\n";
    for ( my $i=0; $i <= $#fields; $i++ ) {
	my $curr_field = $fields[$i];
	$string .= $curr_field->toString()."\n";
    }
    return $string;
}



sub update_leader_character_position {
    my $self = shift;
    my @args = @_;

    #substr($self->{content}, @args); # does not work!
    if ( $#args == 1 ) {
	substr($self->{leader}, $args[0], length($args[1]), $args[1]);
    }
    else {
	die();
    }

    if ( length($self->{leader}) != 24 ) { die(); }
}


sub replicate_field_to_LOW($$$) {
    # Returns a 901 field
    my ( $self, $tag, $LOW ) = @_;
    print STDERR "Trying to add 901 $tag $LOW...\n";

    my @f901 = $self->get_all_matching_fields('901');    

    if ( $LOW !~ /^[A-Z]+$/ ) { die(); }

    for ( my $i=0; $i <= $#f901; $i++ ) {
        my $content = $f901[$i]->{content};
        if ( $content =~ /^  \x1Fb([0-9]{3}(,[0-9]{3})*)\x1FcX\x1F5${LOW}$/ ) {
            my $b = $1;
	    ## Tag is already listed: abort
            if ( $b =~ /(^|,)$tag($|,)/ ) {
                #print STDERR "  901: no need to add $tag:\t'$content'\n";
                return $f901[$i];
            }
	    ## Add to the "right" position:
            my @b = split(/,/, $b);
	    $b[$#b+1] = $tag;
	    @b = sort @b;
            $b = join (",", @b);
	    #print STDERR "B: $b\n"; # die();
            $content =~ s/\x1Fb[^\x1F]+/\x1Fb$b/;
	    if ( $content eq $f901[$i]->{content} ) { die(); }
	    $f901[$i]->{content} = $content;
	    print STDERR "UPDATE 901 to '$content'\n";
	    return $f901[$i];
        }
        elsif ( $content =~ /\x1FcX/ ) { die($content); }
    }
    # No existing relevat 901 found. Add one:
    my $new_content = "  \x1Fb$tag\x1FcX\x1F5${LOW}";
    print STDERR " ADD 901\t'$new_content'\n";
    return $self->add_field('901', $new_content);
}

sub swap_all_subfields($) {
    my ( $self ) = @_;

    my @fields = @{$self->{fields}};
    foreach my $field ( @fields ) {
	my $orig_value = $field->toString();
	my $subfield_codes = undef;
	my $skip = 0;
	if ( $self->is_mu() && $field->{tag} =~ /^[97]73$/ ) {
	    # Field 773 subfield order depends on type of record. Music uses
	    # different order from other materials, ffs.
	    # We handle this anomaly here...

	    $subfield_codes = '67wiatpsbdmhkxyzuogq';
	    $skip = 1;
	}
	if ( !$skip ) {
	    $field->swap_subfields($subfield_codes);
	    my $new_value = $field->toString();
	    if ( $orig_value ne $new_value ) {
		print STDERR "SORT SUBFIELDS:\n  '$orig_value' =>\n  '$new_value'\n";
	    }
	}
    }
}

sub punctuate_subfields($$) {
    my ( $self, $tag ) = @_;

    my @fields = $self->get_all_matching_fields($tag);    
    foreach my $field ( @fields ) {
	my $orig_value = $field->toString();
	$field->punctuate_subfields();
	my $new_value = $field->toString();
	if ( $orig_value ne $new_value ) {
	    print STDERR "PUNCTUATE SUBFIELDS:\n  '$orig_value' =>\n  '$new_value'\n";
	}
    }
}


sub delete_record() {
    my ( $self ) = @_;
    # The third deletion method, "DEL $a Y", would wipe out the record too
    # completely...
    # Don't use: # $self->add_field('DEL', "  \x1FaY"); 
    $self->{leader} =~ s/^(.....)./${1}d/; # LDR/05=d

    # The sanity check was added when I cleaned up LOW tags from
    # certain deleted records. (Trying to fix some replication issues.)
    if ( !$self->containsFieldWithValue('STA', "  \x1FaDELETED") ) {
	$self->add_field('STA', "  \x1FaDELETED");
    }
    # Delete LOW tags as well, so that replication will handle them...
    my @LOW_stack = $self->get_all_matching_fields('LOW');
    foreach my $field ( @LOW_stack ) {
	$self->remove_field($field);
    }
    

}

sub is_deleted() {
    my ( $self ) = @_;
    ## Check LDR/05:
    # 'd' is valid for every record type (bib, holding and auth):
    if ( $self->{leader} =~ /^.....d/ ) { return 1; } 
    # Note that an authority record has more deleted values for LDR/05.
    # (Check LDR/06 for auth-ness as well (untested))
    # (What would LDR/05=s mean for bib...)
    if ( $self->{leader} =~ /^.....[sx]z/ ) { die(); return 1; }

    # 001234567 STA    L $$aDELETED 
    if ( $self->containsSubfieldWithValue('STA', 'a', 'DELETED') ) {
	return 1;
    }

    # 001234567 DEL    L $$awhatever (untested)
    my $DEL = $self->get_first_matching_field('DEL');
    if ( defined($DEL) ) {
	die();
	return 1;
    }

    return 0;
}

sub isDeleted($) {
    # Just to offer same function names as a certain JS library:
    my $self = shift;
    return $self->is_deleted();
}

sub is_component_part() {
    my ( $self ) = @_;
    if ( $self->{leader} =~ /^.{7}[abd]/ ) { # LDR/07 = a, b or d
	return 1;
    }
    # Does having 773 field make record a component part?
    return 0;
}

sub is_auth($) {
    my ( $self ) = @_;
    if ( substr($self->{leader}, 6, 1) eq 'z' ) {
	die(); # untested
	return 1;
    }
    return 0;
}

sub is_bib($) {
    my ( $self ) = @_;
    if ( $self->{leader} =~ /^.{6}[acdefgijkmoprt]/ ) {
	return 1;
    }
    return 0;
}

sub is_holding($) {
    my ( $self ) = @_;
    if ( $self->{leader} =~ /^.{6}[uvxy]/ ) {
	die(); # untested
	return 1;
    }
    return 0;
}


sub is_bk($) {
    my ( $self ) = @_;
    if ( $self->{leader} =~ /^......[at][^bis]/ ) { return 1; }
    return 0;
}

sub is_audiobook($) { # definition from MELKEHITYS-1975, might not be perfect
    my ( $self ) = @_;
    if ( $self->{leader} !~ /^.{6}i/ ) {
	return 0;
    }
    my @f336 = $self->get_all_matching_field_contents('336');
    if ( grep(/\x1Fbspw\x1F2rdacontent/, @f336) ) {
	die();
	return 1;
    }
    return 0;
}

sub is_cr($) { # countinuing resource, serial
    my ( $self ) = @_;
  if ( $self->{leader} =~ /^......[at][bis]/ ) { return 1; }
  return 0;
}

sub is_vm($) { # visual material
    my ( $self ) = @_;
    # "Käytetään tietueissa, joissa nimiö/06 koodi on g, k, o tai r.
    if ( $self->{leader} !~ /^......[gkor]/ ) {
	return 0;
    }
    # "Jos nimiö/07 sisältää jonkin koodeista b, i tai s,
    # tietueessa pitää olla myös 006/00 koodi s."
    if ( $self->{leader} !~ /^.......[bis]/ ) { return 1; }
    my @f006 = $self->get_all_matching_fields('006');
    foreach my $field ( @f006 ) {
	if ( $field->{content} =~ /^s/ ) {
	    return 1;
	}
    }
    return 0;
}

sub is_mu() {
    my ( $self ) = @_;
    if ( $self->{leader} =~ /^......[^cdij]/ ) { # LDR/06 po. cdij
	return 0;
    }
    # LDR/06 is c/d/i/j
    if ( $self->{leader} =~ /^.......[^bis]/ ) {
	return 1;
    }

    # LDR/07=b/i/s requires further inspections:
    my @f006 = grep(/^s/, $self->get_all_matching_fields('006'));
    if ( $#f006 > -1 ) {
	die();
	return 1;
    }
    return 0;
}

sub is_rda($) {
    my ( $self ) = @_;
    my $f264 = $self->get_first_matching_field_content('264');
    if ( defined($f264) ) { return 1; }
    return 0;
}

sub replicate_field_to_fikka($$) {
    my ( $self, $tag ) = @_;
    return $self->replicate_field_to_LOW($tag, 'FIKKA');
}

sub get_language_code_from_008($) {
    my $self = shift;
    my $f008content = $self->get_first_matching_field_content('008');
    if ( !defined($f008content) || length($f008content) < 38 ) { return undef; }
    return substr($f008content, 35, 3);
}

sub get_cataloging_language($) {
    my $self = shift;
    my $f040 = $self->get_first_matching_field_content('040');
    if ( !defined($f040) ) { return undef; }
    if ( $f040 =~ /\x1Fb([^\x1F]+)$/ ) {
	
    }
    return undef;
}

sub is_kk_record($) {
    my $self = shift;
    my $f040 = 0;
    my $f042 = 0;
    my $LOW = 0;

    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;

    foreach my $field ( @fields ) {
## These's are not really trustworthy:
#	if ( $field->{tag} eq '040' ) {
#	    if ( $field->{content} =~ /\x1F[ad]FI-NL/ ) {
#		$f040 = 1;
#	    }
#	}
#	if ( $field->{tag} eq '042' ) {
#	    if ( $field->{content} =~ /\x1Fafinb/ ) {
#		$f042 = 1;
#	    }		    
#	}
	if ( $field->{tag} eq 'LOW' ) {
	    if ( $field->{content} =~ /\x1Fa(FENNI|FIKKA|VIOLA)/ ) {
		$LOW = 1;
	    }		    
	}
    }
    
    return $f040 + $f042 + $LOW;    
}

sub is_prepublication($) {
    my $self = shift;
    if ( $self->{leader} =~ /^.{17}8/ ) { return 1; }
    return 0;
}

sub is_prepublicationish($) {
    my $self = shift;
    my $fieldsP = $self->{fields};
    my @fields = @$fieldsP;

    foreach my $field ( @fields ) {
	if ( $field->{content} =~ /\x1F.ENNAKKOTIETO/ ) {
	    return 1;
	}
    }
    return 0;
}



sub add_missing_336($) {
    # Written for Tempo. Lacks everything not needed by Tempo.
    my ( $self ) = @_;
    my $f336 = $self->get_first_matching_field('336');
    if ( defined($f336) ) { return $f336; }

    if ( $self->{leader} =~ /^......j/ ) {
	return $self->add_field('336', "  \x1Faesitetty musiikki\x1Fbprm\x1F2rdacontent");
    }
    die();
}


sub add_missing_337($) {
    # Written for Tempo. Lacks everything not needed by Tempo.
    my ( $self ) = @_;

    my $f337 = $self->get_first_matching_field('337');
    if ( defined($f337) ) { return $f337; }

    my $f007 = $self->get_first_matching_field('007');
    if ( !defined($f007) ) { return undef; } # Maybe field 300 could help?

    if ( substr($f007->{content}, 0, 1) eq 's' ) {
	return $self->add_field('337', "  \x1Faaudio\x1Fbs\x1F2rdamedia");
    }
    
    if ( substr($f007->{content}, 0, 1) eq 'c' ) { # Seen in Fono. How about Tempo?
	#if ( substr($f007->{content}, 0, 2) eq 'cr' ) { # Seen in Fono. How about Tempo?
	return $self->add_field('337', "  \x1Fatietokonekäyttöinen\x1Fbc\x1F2rdamedia");
	#}
    }
    
    die();
}

sub add_missing_338($) {
    # Written for Tempo. Lacks everything not needed by Tempo.
    my ( $self ) = @_;

    my $f338 = $self->get_first_matching_field('338');
    if ( defined($f338) ) { return $f338; }

    # Comps just don't get it:
    if ( $self->{leader} =~ /^.{7}[abd]/ ) { return undef; }

    my $f007 = $self->get_first_matching_field('007');
    if ( !defined($f007) ) { return undef; } # maybe 300$a might help?
    
    if ( substr($f007->{content}, 0, 1) eq 'c' ) {
	if ( $f007->{content} =~ /^cr/ ) {
	    return $self->add_field('338', "  \x1Faverkkoaineisto\x1Fbcr\x1F2rdacarrier");
	    
	}
	# Very iffy educated guess for Tempo:
	if ( $self->{leader} =~ /^.{6}j/ ) {
	    return $self->add_field('338', "  \x1Faäänilevy\x1Fbsd\x1F2rdacarrier");
	}
	
    }
    
    if ( substr($f007->{content}, 0, 1) eq 's' ) {
	if ( $f007->{content} =~ /^sd/ ||
	     $f007->{content} =~ /^s..[a-f]/ ) {
	    return $self->add_field('338', "  \x1Faäänilevy\x1Fbsd\x1F2rdacarrier");
	}
	if ( $f007->{content} =~ /^ss/ ) {
	    return $self->add_field('338', "  \x1Faäänikasetti\x1Fbss\x1F2rdacarrier");
	}
	if ( $f007->{content} =~ /^s\|+$/ ) {
	    return undef;
	}
	die("TODO: Handle 007->338 using '".$f007->{content}."'");
	# https://www.kiwi.fi/pages/viewpage.action?pageId=51282054#id-3XXFyysisenkuvailunjne.kent%C3%A4t-338 support äänikasettim äänikela and muu as well.
    }
    die("Failed to add missing 338...");
}



sub get_unambiguous_host_id($) {
    my ( $self ) = @_;
    my @host_item_entry_fields = $self->get_all_matching_fields('[79]73');
    # what about 973?
    unless ( $#host_item_entry_fields == 0 && $host_item_entry_fields[0]->{tag} eq '773' ) {
	return 0;
    }
    return $host_item_entry_fields[0]->get_parent_id_from_X73w();
}

sub get_host_id_hash($) {
    my ( $self ) = @_;
    my @host_item_entry_fields = $self->get_all_matching_fields('[79]73');
    my %host_ids = ();
    foreach my $field ( @host_item_entry_fields ) {    
	my $id = $field->get_parent_id_from_X73w(); 
	if ( $id ) {
	    if ( defined($host_ids{$id}) ) {
		$host_ids{$id} += 1;
	    }
	    else {
		$host_ids{$id} = 1;
	    }
	}
    }
    return %host_ids;
}
sub get_all_host_ids($) {
    my ( $self ) = @_;
    my %hash = $self->get_host_id_hash();
    return sort keys %hash;
}


sub belongs_to_arto($) {
    my ( $self ) = @_;
    my @f960 = $self->get_all_matching_field_contents('960');
    foreach my $content ( @f960 ) {
	if ( $content =~ /\x1FaARTO($|\x1F)/ ||
	     $content eq "  \x1FaAleksi\x1F5ARTO") {
	    return 1;
	}
    }
    return 0;
}



sub is_abandoned($) {
    my ( $self ) = @_;
    my @owner_tags = ('LOW', '960', '850', '852', '856');

    foreach my $tag ( @owner_tags ) {
	my @fields = $self->get_all_matching_fields($tag);
	if ( $#fields > -1 ) {
	    return 0;
	}
    }
    return 1;
}

sub is_translation($) {
    my ( $self ) = @_;
    my $f041 = $self->get_first_matching_field('041');
    if ( defined($f041) && $f041->{content} =~ /^1/ ) {
	return 1;
    }
    return 0;
}


sub mark_record_as_deleted($) {
    my ( $self ) = @_;
    $self->{leader} =~ s/^(.....)./${1}d/;
    $self->add_unique_field('STA', "  \x1FaDELETED");
}

## Fixes only after this point

sub fix_245_ind1($) {
    my ( $self ) = @_;
    my $f245 = $self->get_first_matching_field('245');
    if ( !defined($f245) ) {
	return;
    }
    my $f1XX = $self->get_first_matching_field('1..');
    if ( defined($f1XX) ) {
	$f245->{content} =~ s/^./1/;
    }
    else {
	$f245->{content} =~ s/^./0/;
    }
}

sub fix_nonfiling_character_field($$) {
    my ( $self, $field) = @_;

    if ( !defined($field) ) { return; }
    
    ## Skip irrelevant fields:
    my $nonfiling_indicator_position = $field->get_nonfiling_indicator_position();
    if ( !$nonfiling_indicator_position ) {
	return;
    }
    # Default to '0':
    if ( $nonfiling_indicator_position == 1 ) {
	$field->{content} =~ s/^[^0-9]/0/;
    }
    elsif ( $nonfiling_indicator_position == 2 ) {
	$field->{content} =~ s/^(.)[^0-9]/${1}0/;
    }
    
    # Typically initial nonfiling chars such as ", ' and ( are not counted!
    # https://www.loc.gov/marc/marbi/1998/98-16.html says:
    # "It is also common for some types of introductory characters
    # (diacritics or punctuation marks) not to be identified as nonfiling
    # characters with the expectation that they will be ignored by the
    # software and for others to be omitted by the cataloger."
    # Finnish: https://marc21.kansalliskirjasto.fi/ohitus.htm
    # Nonfiling indicator value '1' seems to be wrong always. Change it to '0'.
    if ( $field->has_introductory_nonfiling_character() ) {
	if ( $nonfiling_indicator_position == 1 ) {
	    $field->{content} =~ s/^1/0/;
	}
	elsif ( $nonfiling_indicator_position == 2 ) {
	    $field->{content} =~ s/^(.)1/${1}0/;
	}
    }

    my $f041 = $self->get_first_matching_field('041');
    # In no language is given, stop here:
    if ( !defined($f041) ) {
	return;
    }
    
    my @languages = $f041->{content} =~ /\x1F[ad]([^\x1F]+)/;
    print STDERR "NFC: Languages: ", join(", ", @languages), "\n";
    foreach my $lang ( @languages ) {
	my $n = main::number_of_nonfiling_characters_in_given_language($field->{content}, $lang); # -1 means no value here
	
	## Add value to the relevant indicator:
	# However, don't overwrite any other value with '0'
	if ( $n > 0 ) {
	    #print STDERR $field->toString(), " =>\n";
	    if ( $nonfiling_indicator_position == 1 ) {
		$field->{content} =~ s/^(.)/$n/;
	    }
	    elsif ( $nonfiling_indicator_position == 2 ) {
		$field->{content} =~ s/^(.)./$1$n/;
	    }
	    #print STDERR $field->toString(), "\n";
	    return;
	}
    }
}
    
sub fix_nonfiling_character_fields($) {
    my ( $self ) = @_;

    foreach my $curr_field ( @{$self->{fields}} ) {
	$self->fix_nonfiling_character_field($curr_field);
    }
}

sub get_publisher_field($) {
    my ( $self ) = @_;

    my @cand_fields = $self->get_all_matching_fields('264');
    foreach my $cand_field ( @cand_fields ) {
	if ( $cand_field->{content} =~ /^.1/ ) {
	    return $cand_field;
	}
    }

    # NB! this might be undef:
    return $self->get_first_matching_field('260');
}


sub get_unprocessed_place_of_publication($) {
    my ( $self ) = @_;

    # Field 264 = Post-RDA-conversion:
    my @cand_fields = $self->get_all_matching_fields('264');
    foreach my $cand_field ( @cand_fields ) {
	if ( $cand_field->{content} =~ /^.1/ ) {
	    return $cand_field->get_first_matching_subfield('a');
	}
    }
    
    # Field 260 = Pre-RDA-conversion:
    my $place_of_pub = $self->get_first_matching_subfield('260', 'a');
    if ( defined($place_of_pub) && $place_of_pub =~ /\S/ ) {
	return $place_of_pub;
    }
        
    return undef;
}

sub find_subfield6_pair($$) {
    my ( $self, $field ) = @_;
    my ( $tag, $index ) = kk_marc21_field::getTagAndIndex($field->{content});

    if ( !defined($tag) || $index eq '00' ) { return undef; }
	
    if ( $field->{tag} ne '880' && $tag ne '880' ) {
	die(); # Breakpoint for testing
	return undef; 
    }
    if ( $field->{tag} eq '880' && $tag eq '880' ) {
	die(); # Breakpoint for testing
	return undef;
    }

    my @cand_fields = $self->get_all_matching_fields($tag);

    my @hits = ();
    for my $cand_pair ( @cand_fields ) {
	my ( $cand_tag, $cand_index ) = kk_marc21_field::getTagAndIndex($cand_pair->{content});
	if ( $cand_tag eq $field->{tag} && $index eq $cand_index ) {
	    # return $cand_pair; # nah, check amount as well, since Helmet is crappy
	    push(@hits, $cand_pair);
	}
    }
    if ( scalar(@hits) == 0 ) {
	return undef;
    }
    if ( scalar(@hits) == 1 ) {
	return $hits[0];
    }
    # This means there's an error in the record.
    # I have die() here, so that record can be fixed manually...
    die(); 
    return undef;
}

sub get_place_of_publication() {
    my ( $self ) = @_;

    # Get place of publication:
    my $place_of_pub = $self->get_unprocessed_place_of_publication();

    # Process value:
    if ( defined($place_of_pub) ) {
	$place_of_pub =~ s/( *:|,) *$//;
	# TODO: We should really
	if ( $place_of_pub !~ /(tuntematon|\[s\.l)/i || $place_of_pub !~ /\S/ ) {
	    return $place_of_pub;
	}
    }

    return undef;
}

sub fix_composition($) {
    my ( $self ) = @_;
    my @fields = @{$self->{fields}};
    foreach my $field ( @fields ) {
	$field->fix_composition();
    }
}
    

sub get_publication_year_008($) {
    my ( $self ) = @_;
    my $f008 = $self->get_first_matching_field('008');
    if ( defined($f008) ) {
	# 008/06 sanity checks:
	if ( $f008->{content} !~ /^......[cdeikmnpqrstu]/ ) { return 'uuuu'; }
	return substr($f008->{content}, 7, 4);
  }
  return 'uuuu';
}

sub get_publication_year_260($) {
    my ( $self ) = @_;
    my $year_field = $self->get_first_matching_field('260');
    if ( defined($year_field) && $year_field->{content} =~ /\x1Fc([^\x1F]+)/ ) {
	my $f260c = $1;
	if ( $f260c =~ /^\D*([0-9]{4})\D*$/ ) {
	    my $year = $1;
	    die($year_field->toString().": $year");
	    return $year;
	}
    }
    return 'uuuu';
}

sub get_publication_year_264($) {
    my ( $self ) = @_;
    my @ind2_try_order = ('1', '4');
    my @year_fields = $self->get_all_matching_fields('264');
    foreach my $ind2 ( @ind2_try_order ) {
	foreach my $f264 ( @year_fields ) {
	    if ( $f264->{content} =~ /^.${ind2}/ && $f264->{content} =~ /\x1Fc([^\x1F]+)/ ) {
		my $cand = $1;
		if ( defined($cand) && $cand =~ /^\D*([0-9]{4})\D*$/ ) {
		    my $year = $1;
		    return $year;
		}
	    }
	}
    }
    return 'uuuu';
}

sub get_publication_year($) {
    my ( $self ) = @_;

    # 1st try: 008/07-10
    my $year008 = $self->get_publication_year_008();
    if ( $year008 =~ /^[0-9]{4}$/ ) {
	return $year008;
    }
    
    # 2nd try 260 (264 is better but slower check)
    my $year = $self->get_publication_year_260();
    if ( $year =~ /^[0-9]{4}$/ ) {
	return $year;
    }
    
    # 3rd try: 264 fields
    $year = $self->get_publication_year_264();
    if ( $year =~ /^[0-9]{4}$/ ) {
	return $year;
    }

    # Fallback to 008/07-10
    return $year008;
}
 

    
   
sub create_035_from_001_003($) {
    my ( $self ) = @_;
    if ( !$self->is_bib() ) {
	# Not yet supported. Think through + implement when we have a real case
	die();
    }

    my $f001 = $self->get_first_matching_field('001');
    if ( !defined($f001) ) { die(); } # some serious corruption
    
    my $f003 = $self->get_first_matching_field('003');

    # Define $prefix:
    my $prefix = '';
    if ( !defined($f003) ) {
	$prefix = '(FI-MELINDA)';
    }
    else {
	# Need to think about this as well eventually.
	# Currently just a brutal break point here :-/
	die();
    }

    if ( $prefix ) {
	my $new_field = $self->add_field('035', "  \x1Fa$prefix".$f001->{content});
	print STDERR $new_field->toString(), "\n";
    }
    # TODO: Test
}


1;
