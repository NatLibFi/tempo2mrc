# whatever files

sub string_number_of_substring_occurences($$) {
    my ( $string, $substring ) = @_;

    my $hits = 0;
    my $pos = 0;
    
    while ( 1 ) {
	$pos = index($string, $substring, $pos)+1;
	if ( !$pos ) { # miss
	    return $hits;
	}
	$hits++;
    }
}



1;
