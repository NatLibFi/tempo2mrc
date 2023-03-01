#
# tempo_utils.pm -- various generic functions
#
# Copyright (c) 2021-2022 HY (KK). All Rights Reserved.
#
# Author(s): Nicholas Volk <nicholas.volk@helsinki.fi>
#

use strict;

our $dd_regexp = "(?:0[1-9]|[12][0-9]|3[01])";
our $mm_regexp = "(?:0[1-9]|1[012])";
our $yyyy_regexp = "(?:1[6-9][0-9][0-9]|20[0-1][0-9]|202[0-3])";


sub get_dd_regexp() {
    return $dd_regexp;
}


sub get_mm_regexp() {
    return $mm_regexp;
}


sub get_yyyy_regexp() {
    return $yyyy_regexp;
}


sub trim_ends($) {
    my $str = shift();
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}


sub trim_all($) {
    my $str = shift();
    $str =~ s/\s{2,}/ /g;
    return trim_ends($str);
}


sub trim_data_row($) {
    my $row = shift;
    $row =~ s/^\S+ = '// or die($row);
    $row =~ s/'\s*$// or die($row);
    return $row;
}


sub tempo_lc($) {
    my ( $str ) = @_;
    #$str = lc($str); # FFS: broke encoding in 653 näyttämömusiikki...
    $str =~ tr/A-Z/a-z/;
    $str =~ s/Å/å/g;
    $str =~ s/Ä/ä/g;
    $str =~ s/Ö/ö/g;
    return $str;
}


sub tempo_ucfirst_lcrest($) {
    my ( $str ) = @_;
    $str = tempo_lc($str);
    $str = ucfirst($str);
    $str =~ s/^å/Å/;
    $str =~ s/^ä/Ä/;
    $str =~ s/^ö/Ö/;
    return $str;
}


sub tempo_ucinitial_lcrest($) {
    my ( $str ) = @_;
    my $orig_str = $str;
    $str = tempo_lc($str);
    $str = ucfirst($str);
    $str =~ s/ ([a-z])/ \u$1/g;
    $str =~ s/(^| )å/${1}Å/g;
    $str =~ s/(^| )ä/${1}Ä/g;
    $str =~ s/(^| )ö/${1}Ö/g;
    return $str;
}


sub get_single_entry($$) {
    my ( $key, $arr_ref ) = @_;
    my @keyvals = grep { index($_, $key) == 0 } @{$arr_ref};
    if ( $#keyvals == -1 ) {
	#die("?? ".join("\n?? ", @{$arr_ref}). "\nKEY: $key"); 
	return undef;
    }
    @{$arr_ref} = grep { index($_, $key) != 0 } @{$arr_ref}; # remove ref
    if ( $#keyvals > 0 ) { die("Multiple (N=".($#keyvals+1).") hits for $key in ".$ARGV[0]. "\n".join("\n", @keyvals)); } # Flaw in design?
    my $val = trim_data_row($keyvals[0]);
    return $val;
}


sub get_array_entry($$) {
    my ( $key, $arr_ref ) = @_;
    my @keyvals = grep(/^\Q$key\E\[[0-9]+\] = '/, @{$arr_ref});
    if ( $#keyvals == -1 ) {
	my $single_entry = get_single_entry($key, $arr_ref);
	if ( defined($single_entry) ) {
	    $keyvals[0] = $single_entry;
	}
	return @keyvals;
    }
    # Remove references:
    @{$arr_ref} = grep(! /^\Q$key\E\[[0-9]+\] = '/, @{$arr_ref});
    
    return map { trim_data_row($_); } @keyvals;
}


sub key_match($$) {
    my ( $line, $key ) = @_;
    my $key_len = length($key);
    my $head = substr($line, 0, $key_len);
    if ( $head ne $key ) { return 0; }
    my $tail = substr($line, $key_len);

    if ( $key =~ /\/$/ ) { return 1; } # branch
    
    if ( $tail =~ /^(\[\d+\])? = / ) { # leaf
	return 1;
    }
    if ( $tail =~ /^\// ) { # branch
	return 1;
    }
    if ( $tail =~ /^[_a-z]/ ) { # diffenent leaf/branch
	return 0;
    }
    die("LINE: '$line'\nKEY:  '$key'\nHEAD: '$head'\nTAIL: '$tail'");
    return 0;
}


sub extract_keys($$) {
    my ( $key, $tempo_dataP ) = @_;
    #print STDERR "EK1 '$key' in\n";

    # Was not OK, since recording_country is a subset of recording_country_estimated
    if ( 0 ) {
	my @results = grep { index($_, $key) == 0 } @{$tempo_dataP};
	if ( $#results > -1 ) { # remove results from tempo data:
	    print STDERR "EK2 '$key' in\n";
	    print STDERR join("\n", @results), "\n";
	    my $n = $#{$tempo_dataP};
	    @{$tempo_dataP} = grep { index($_, $key) != 0 } @{$tempo_dataP};
	    #@{$tempo_dataP} = grep { index($_, $key.'[') != 0 || index($_, $key.' ') != 0 } @{$tempo_dataP};
	    my $n2 = $#{$tempo_dataP};
	    if ( $n == $n2 ) { die($key); }
	    #print "EK2 out\n";
	}
    }

    my @results = grep { key_match($_, $key) } @{$tempo_dataP};
    if ( $#results > -1 ) { # remove results from tempo data:
	print STDERR "EK2 '$key' in\n";
	print STDERR join("\n", @results), "\n";
	my $n = $#{$tempo_dataP};
	@{$tempo_dataP} = grep { !key_match($_, $key) } @{$tempo_dataP};
	my $n2 = $#{$tempo_dataP};
	if ( $n == $n2 ) { die($key); }
	#print "EK2 out\n";
    }
	
    return @results;
}


sub get_max_track($) {
    my $val = shift;
    if ( $val =~ /^\d+$/ ) {
	return $val;
    }
    if ( $val =~ /^\d+-(\d+)$/ ) {
	return $1;
    }
    die();
}

sub get_min_track($) {
    my $val = shift;
    if ( $val =~ /^\d+$/ ) {
	return $val;
    }
    if ( $val =~ /^(\d+)-\d+$/ ) {
	return $1;
    }
    die();
}

sub merge_consecutive_track_indexes($$) {    
    my ( $lhs, $rhs ) = @_;
    $lhs = get_min_track($lhs);
    $rhs = get_max_track($rhs);
    return $lhs.'-'.$rhs;
}

sub collapse_tracks($) {
    # convert "1, 2, 3" to "1-3"
    my ( $tracks ) = @_; 

    my @track_array = split(", ", $tracks);

    if ( $#track_array > 0 ) {
	for ( my $i=0; $i < $#track_array; $i++ ) {
	    my $curr = $track_array[$i];
	    my $next = $track_array[$i+1];
	    # print STDERR "COMPARING $curr vs $next\n";
	    my $curr_max = get_max_track($curr);
	    my $next_min = get_min_track($next);
	    if ( $next_min - $curr_max == 1 ) { # merge
		$track_array[$i] = merge_consecutive_track_indexes($curr, $next);
		# print STDERR "MERGED TO '", $track_array[$i], "'\n";
		splice(@track_array, $i+1, 1);
		$i--;

	    }
	}
	return join(", ", @track_array);
    }
    return $tracks;
}


sub normalize_tracks($) {
    my ( $tracks ) = @_;

    if ( !defined($tracks) ) {
	return undef;
    }
    $tracks =~ s/^ +\///;
    if ( $tracks !~ /^\d+(-\d+)?(, \d+(-\d+)?)*$/ ) {
	die($tracks);
    }
    if ( $tracks =~ /^\d+$/ ) {
	return "Raita ".$tracks;
    }
    $tracks = &collapse_tracks($tracks);
    return "Raidat ".$tracks;
}


1;
