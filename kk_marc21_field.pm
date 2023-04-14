package kk_marc21_field;

use strict;


require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(controlFieldToString dataFieldToString fieldToString getUnambiguousSubfield);


sub controlFieldToString($) {
    my ( $fieldAsString ) = @_;
    $fieldAsString =~ s/ /\#/g; # '^' is aleph-style, '#' is validish as well
    return $fieldAsString;
}

sub dataFieldToString($) {
    my ( $fieldAsString ) = @_;
    # Visible indicators:
    $fieldAsString =~ s/^ /#/;
    $fieldAsString =~ s/^(.) /${1}#/;
    # Subfield sepatators:
    $fieldAsString =~ s/\x1F(.)/ ‡$1 /g; 
    return $fieldAsString;
}
    
sub fieldToString($) {
    my ( $fieldAsString ) = @_;
    if ( index($fieldAsString, "\x1F") > -1 ) { # Has subfields
	return dataFieldToString($fieldAsString);
    }
    return controlFieldToString($fieldAsString);
}

sub getUnambiguousSubfield($$) {
    my ( $content, $subfield_code ) = @_;
    if ( $content =~ /\x1F${subfield_code}([^\x1F]+)/ ) {
	my $val = $1;
	if ( $content =~ /\x1F${subfield_code}.*\x1F${subfield_code}/ ) {
	    return undef;
	}
	return $val;
    }
    return undef;
}

sub sequentialToField($) {
    my ( $content ) = @_;

    my $tag;
    my $indicators;
    my $subfields;

    if ( $content =~ /^[0-9]{9} (...)(..) L (.*)$/ ) {
	# NB! Don't send LDR here... It turns into a field...
	$tag = $1;

	$indicators = $2;
	$subfields = $3;
    }
    else { die($content); }

    my $new_content = '';
    if ( $tag !~ /^00/ ) {
	$new_content .= $indicators;
    }
    # Convert legal subfields or all subfields:
    if ( 1 ) {
	$subfields =~ s/\$\$([a-z0-9])/\x1F$1/g; # legal subfields
    }
    else {
	$subfields =~ s/\$\$/\x1F/g; # all subfields
    }
    $new_content .= $subfields;

    return $new_content;
}

sub getSubfield6TagAndIndex($) {
    my ( $content ) = @_;
    if ( $content =~ /^..\x1F6([0-9][0-9][0-9])-([0-9][0-9])($|-|\x1F)/ ) {
	return ( $1, $2 );
    }
    return ( undef, undef );
}

sub getSubfield6Index($) {
    my ( $content ) = @_;
    my ( $tag, $index ) = getSubfield6TagAndIndex($content);
    return $index;
}

sub getSubfield6Tag($) {
    my ( $content ) = @_;
    my ( $tag, $index ) = getSubfield6TagAndIndex($content);
    return $tag;
}


1;
