#!/usr/bin/perl -w
#
# nvolk_marc21.pm - Library for manipulation MARC21 input, mainly records
#
# Copyright (c) 2011-2019 Kansalliskirjasto/National Library of Finland
# All Rights Reserved.
#
# Author(s): Nicholas Volk (nicholas.volk@helsinki.fi)
#
# TODO:
# o Add a (MIT?) license
# o Add object-oriented alternative alternative (then composing and
#   decomposing the MARC21 string would need to be done only at the
#   beginning and the end => way faster)
# o Move validation part to a separate file
#
# Yet another Marc21 processor. The main advantage with this version is that
# one can delete fields and subfields from a record pretty easily.
#
# Used by:
# - marc2dc2.pl (Marc21 -> DublinCore) converter (todo: test latest version)
#   (removes "used up" components from the record, so that we'll know what
#    parts (if any) of the input were not converted.)
# - viola_auktoriteet.perl (auktoriteettikonversioskripti)
# - Fono-konversio (voyager/viola/scripts/fono/)
# - multiple other scripts by Nicholas and Leszek..
#
# NB! There are various other conversion tools out there as well...
#
# TODO: Object Oriented approach...
# We could just convert each record to header + array for tag names
# + array for tag contents
#
# TODO: wrapper (get field + change indicator(s) + put back)
# for indicator manipulation.
#
# KK version control (SVN): stored under voyager/viola/scripts/fono/
# Will move to Github eventually...
#
# 2015-04-27: initial Melinda/Aleph support, not all alphabetical tags yet supported...
#
# NB! XML::XPath and XML::XPath::XMLParser do evil things to input string!
# Bad because of \x1F etc:
#  my $original_size = bytes::length(Encode::encode_utf8($record));
#  my $original_size = bytes::length($record);
# For parsing oai_marcxml

#use XML::XPath;
#use XML::XPath::XMLParser;

use Encode;
use strict;

use nvolk_generic;
use nvolk_utf8;

my $debug = 0;

#########################################


sub marc21_field_get_subfield($$) {
  my ( $field, $subfield ) = @_;
  if ( $field =~ /\x1F${subfield}([^\x1D\x1E\x1F]*)/ ) {
    return $1;
  }
  # return ''; # there can be subfields with no content so this must be undef...
  return undef;
}


sub marc21_field_remove_subfield_once($$) {
  # "_once" as there may be multiple instances of same subfield
  my ( $field, $subfield ) = @_;
  $field =~ s/\x1F${subfield}([^\x1D\x1E\x1F]+)//;
  # This was the only subfield, so dump the whole field:
  if ( bytes::length($field) == 2 ) {
    return '';
  }
  return $field;
}

sub marc21_field_remove_subfields($$) {
  my ( $field, $subfield ) = @_;
  $field =~ s/\x1F${subfield}([^\x1D\x1E\x1F]+)//g;
  if ( bytes::length($field) == 2 ) {
    return '';
  }
  return $field;
}


# convert directory into three arrays...
sub marc21_directory2tag_len_pos($) {
  my $directory = $_[0];
  my @tag = ();
  my @len = ();
  my @pos = ();
  while ( $directory ) {
    if ( $directory =~ s/^(...)(....)(.....)// ) {
      my $t = $1; # keeps the inital zeroes: "008", "045"
      my $l = $2;
      my $p = $3;
      $l =~ s/^0+(\d)/$1/; # leave the final 0
      $p =~ s/^0+(\d)/$1/; # leave the final 0
      push(@tag, $t);
      push(@len, $l);
      push(@pos, $p);
    }
    else {
      die("critical error: directory: '$directory'\n");
    }
  }
  return (\@tag, \@len, \@pos );
}

sub marc21_reset_record_length($) {
  my $record = $_[0];
  ## Update the leader 0-4 (record length)
  #my $length = bytes::length(Encode::encode_utf8($record));
  my $length = marc21_length($record);
  while ( length($length) < 5 ) { $length = "0$length"; }
  #$length = ( (5-length($length)) x '0' ) . $length;
  #$length = sprintf("%.5d", $length);
  $record =~ s/^(.....)/$length/;
  ## Update the leader 12-16 (base address of data)
  my $tmp = $record;
  $tmp =~ s/\x1e.*$/\x1e/s; # säilytetään itse erotin

  # $length = bytes::length(Encode::encode_utf8($tmp));
  $length = marc21_length($tmp);
  #$length = ( (5-length($length)) x '0' ) . $length;
  while ( length($length) < 5 ) { $length = "0$length"; }
  #$length = sprintf("%.5d", $length);
  $record =~ s/^(.{12})(.....)/$1$length/;
  return $record;
}

sub marc21_dir_and_fields2arrays($$) {
  my $directory = $_[0];
  my $cfstr = $_[1];

  my ($tag_ref, $len_ref, $pos_ref) = marc21_directory2tag_len_pos($directory);
  #print STDERR " DAF1\n$cfstr\n";
  my @tag = @$tag_ref;
  my @len = @$len_ref;
  my @pos = @$pos_ref;

  my $i;
  my @contents;
  my $tmp;
  for ( $i=0; $i <= $#tag; $i++ ) {
    #print STDERR "POS $pos[$i] LEN $len[$i]\n";
    $tmp = bytes::substr($cfstr, $pos[$i], $len[$i]);
    #print STDERR "$tmp\n";
    $tmp =~ s/\x1e$//; # vai lyhennetäänkö yhdellä?
    push(@contents, $tmp); # NB! includes \x1f
  }
  return(\@tag, \@contents);
}



#sub marc21_get_directory($) { # probably unused by all
#  my $record = $_[0];
#  $record =~ s/^.{24}//;
#}

sub marc21_get_leader($) { # name: drop 21, add record_ before "get"
  $_[0] =~ /^(.{24})/;
  if ( $1 ) { return $1; }
  return "";
}



# get a single record from <>
sub marc21_read_record_from_stdin() {
  my $tmp = $/;
  $/ = "\x1D";
  my $record = <>; # TODO: name has stdin ja this uses <>...
  $/ = $tmp;
  return $record;
}


# Split records in the same input string into an array of records.
# This may use loads of memory depending on the input string
sub marc21_get_record_array($) {
  my @array = split(/\x1D/, $_[0]);
  return @array;
}

# Split a given record into 3 parts: leader, directory and fields
sub marc21_record2leader_directory_fields($) {
  my $record = $_[0];
  my $leader = '';
  my $directory = '';
  my $fields = '';

  $record =~ s/\x1D$//; # remove separator

  my $i = index($record, "\x1E");
  if ( $i >= 24 ) { # 1st \x1E comes after directory
    # 2015-11-16: removed $' and $` stuff which seemed to perform unexpectedly
    # with  utf8::is_utf8(). Anyway, this is more effective as well.
    $directory = substr($record, 0, $i);
    $fields = substr($record, $i+1);
    # separate leader and directory
    $directory =~ s/^(.{24})// or die();
    $leader = $1;
    return ( $leader, $directory, $fields );
  }
  elsif ( $i == -1 && length($record) == 24 ) { # only directory (future new record?)
    return ( $record, '', '' );
  }
  
  print STDERR "ERROR: No delimeter found within record:\n'$record'!\n";
  return ();
}

sub marc21_leader_directoryarr_fieldsarr2record($$$) {
  my ( $leader, $dir_ref, $field_ref ) = @_;
  # 20151118: force tail ( removed parameter)

  my @contents = @$field_ref;
  my @tags = @$dir_ref;

  my $starting_pos = 0;
  my $new_dir = '';
  #my $new_fields = '';
  my $new_cfstr = '';
  my $i;
  for ( $i=0; $i <= $#contents; $i++ ) {
    # sometimes tags are actually full 12 char long entries
    if ( $tags[$i] =~ s/^(...)(.+)/$1/ ) { # make this more robust
      #print STDERR "Omitted suffix $1/$2 from tag #$i\n";
    }
    my $data = $contents[$i];
    if ( $data !~ /\x1e$/ ) { # add field separator when necessary
      $data .= "\x1e";
    }

    ## Directory:
    #my $flen = bytes::length(Encode::encode_utf8($data));
    #my $flen = bytes::length($data);
    my $flen = marc21_length($data);

    #$starting_pos = bytes::length(Encode::encode_utf8($new_cfstr));
    #$starting_pos = bytes::length($new_cfstr);
    $starting_pos = marc21_length($new_cfstr);

    #my $row = $tags[$i] . sprintf("%.4d", $flen) . sprintf("%.5d", $starting_pos);
    #print STDERR "REBUILDING $tags[$i]\t'$contents[$i]'\t$tags[$i]\t$starting_pos\t$flen\n";
    while ( length($flen) < 4 ) { $flen = "0$flen"; }
    while ( length($starting_pos) < 5 ) { $starting_pos = "0$starting_pos"; }
    my $row = $tags[$i] . $flen . $starting_pos;
    $new_dir .= $row;

    ## Contents:
    $new_cfstr .= $data;



  }
  # rebuild the record string
  my $new_record = $leader . $new_dir . "\x1E" . $new_cfstr . "\x1D";
  $new_record = &marc21_reset_record_length($new_record);

  return $new_record;
  # TODO: a lot...
}

# Split the fields string into an array of fields
sub marc21_record2fields($) {
  my $record = $_[0];
  my @fields = split(/\x1e/, $record);
  shift(@fields); # 1st is leader+dir (rubbish here)
  return @fields;
}

# For validation only (we could this better)...
sub marc21_initial_field_to_leader_and_directory($) {
  my $data = $_[0];
  my @array = ();
  $data =~ s/^(.{24})//;
  push(@array, $1);
  while ( $data =~ s/^(.{12})// ) {
    push(@array, $1);
  }
  return @array;
}


sub marc21_check_field_008($) { # Validation-only
  my $f008 = $_[0];
  if ( length($f008) != 40 ) {
    return 0;
  }
  return 1;
}


sub marc21_record_remove_duplicate_fields($$) {
  my ( $record, $tag ) = @_;
  my ( $i, $j );
  my @fields = marc21_record_get_fields($record, $tag, '');
  for ( $i=$#fields-1; $i >= 0; $i-- ) {
    my $field = $fields[$i];
    for ( $j=$#fields; $j > $i; $j-- ) {
      if ( $field eq $fields[$j] ) {
	$record = marc21_record_remove_nth_field($record, $tag, '', $j);
	# splice() would probably be fine, but just to be on the safe side:
	@fields = &marc21_record_get_fields($record, $tag, undef);
      }
    }
  }
  return $record;
}


sub marc21_sanity_check_record($) {
  my $record = $_[0];

  # 1. Check size
  my $size = 0;
  if ( $record =~ /^(\d{5})/ ) {
    $size = $1;
    $size =~ s/^0+//;
    #if ( $size != bytes::length(Encode::encode_utf8($record)) ) { return 0; }
    if ( $size != bytes::length($record) ) { return 0; }
  }
  my @fields = marc21_record2fields($record);
  my @directory = marc21_initial_field_to_leader_and_directory($fields[0]);
  my $leader = shift(@directory);
  ## ... N-1. There are multiple other tests that should be included...
}

sub marc21_get_control_fields($$$) {
    if ( $debug ) { print STDERR "marc21_get_control_fields()\n"; }
  my ( $directory, $fields, $id ) = @_;
  my @result = ();
  while ( $directory =~ s/^(\d{3}|CAT|COR|DEL|FMT|LID|LKR|LOW|OWN|SID|TPL)(\d{4})(\d{5})// ) {
    my $tag = $1;
    my $flen = $2;
    my $start = $3;
    $tag =~ s/^0+(\d)/$1/; # leave the final 0
    $flen =~ s/^0+//;
    $start =~ s/^0+(\d)/$1/; # leave the final 0
    if ( $id == $tag ) {
      #if ( bytes::length(Encode::encode_utf8($fields)) >= $start+$flen-1 ) {
      if ( bytes::length($fields) >= $start+$flen-1 ) {
	# 1. get the data from fields
	# ($flen-1 omits the \x1E delimiter)
	my $hit = bytes::substr($fields, $start, $flen-1);
	# 2. push it into @result;
	push(@result, $hit);
      }
      else {
	#print STDERR "Problematic sizes: " . bytes::length(Encode::encode_utf8($fields)) . " vs $start+$flen\n";
	print STDERR "Problematic sizes: " . bytes::length($fields) . " vs $start+$flen\n";
      }
    }
  }
  #if ( $#result >= 0 ) { print STDERR  "$id; ", ($#result+1), " hit(s)\n"; }
  return @result;
}

sub marc21_get_control_field($$$) {
  if ( $debug ) { print STDERR "marc21_get_control_field()\n"; }
  my @result = marc21_get_control_subfields($_[0], $_[1], $_[2], "");
  # sanity checks:
  if ( $#result == -1 ) {
    if ( $debug ) { print STDERR "Warning: $_[2] not found!\n"; }
    return ();
  }
  if ( $#result > 0 ) {
    print STDERR "Warning: $_[2] has multiple values, return only one of them!\n";
  }
  if ( $result[0] =~ s/(\x1E.*)$// ) {
    print STDERR "\\x1E found within a field (field position and size based on the directory): $result[0]$1\n";
  }
  return $result[0];
}

sub marc21_get_control_subfields($$$$) {
  if ( $debug ) { print STDERR "marc21_get_control_subfields()\n"; }
  my @result = ();
  my @fields = marc21_get_control_fields($_[0], $_[1], $_[2]);
  my $subfield;
  my $field;

  if ( $_[3] eq "" ) { return @fields; }

  foreach $field ( @fields ) {
    my @subfields = split(/\x1F/, $field);
    foreach $subfield ( @subfields ) {
      if ( $subfield =~ s/^$_[3]// ) {
	if ( $subfield =~ /\S/ ) {
	  push(@result, $subfield);
	}
      }
    }
  }
  return @result;
}


sub marc21_get_control_subfield($$$$) {
  if ( $debug ) { print STDERR "marc21_get_control_subfield()\n"; }
  my @result = marc21_get_control_subfields($_[0], $_[1], $_[2], $_[3]);
  # sanity checks:
  if ( $#result == -1 ) {
    if ( $debug ) { print STDERR "Warning: $_[2]$_[3] not found!\n"; }
    return @result;
  }
  if ( $#result > 0 ) {
    print STDERR "Warning: $_[2]$_[3] has multiple values, return only one of them!\n";
  }
  return ( $result[0] );
}

sub marc21_directory2array($) {
  my $directory = $_[0];
  my $original = $directory;
  # TODO: length(directory)%12 sanity check
  my @array = ();
  while ( $directory =~ s/^(.{12})// ) {
    my $hit = $1;
    #print STDERR ".: '$hit'\n";
    push(@array, $hit);
    #print STDERR "=: '$array[$#array]'\n";
  }
  if ( $directory ne "" ) {
    return ();

  }
  #print STDERR "\n";
  return @array;
}

# splice can be used to add elements to an array:
#
#  splice(@array,$i,0,"New value");

sub marc21_fields2array($) {
  my $cfstr = $_[0];
  $cfstr =~ s/^\x1E//;
  $cfstr =~ s/\x1E$//;
  return split(/\x1E/, $cfstr);
}



sub marc21_record_get_fields($$$) {
  my ( $record, $field, $subfield ) = @_;
  # TODO: modernize this (compare with marc21_record_add_field()
  $record =~ s/(\x1D)$//;
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  if ( defined($subfield) && length($subfield) > 1 ) {
    die("Overlong subfield: '$subfield'\n");
  }
  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my @results = ();
  my $i;
  my $pos = 0;
  for ( $i=0; $i <= $#tags; $i++ ) {
    if ( $field eq $tags[$i] ) {

      my $fc = $contents[$i];
      if ( !defined($subfield) || $subfield eq '' ) { # The whole field
	$results[$pos] = $fc;
      }
      else { # Subfield only
	my $sf = &marc21_field_get_subfield($fc, $subfield);
	#print STDERR "$field vs $tags[$i]\n";
	#print STDERR " $subfield: '$sf'\n";
	$results[$pos] = $sf;
      }
      $pos++;
    }
  }
  return @results;
}

sub normalize_tag($) {
  # Korjaa esmes joku virheellinen  "24"-kenttä "024":ksi:
  my $tag = $_[0];
  if ( $tag =~ /^\d$/ ) {
    return "00$tag";
  }
  if ( $tag =~ /^\d\d$/ ) {
    return "0$tag";
  }
  return $tag;
}

sub marc21_record_get_nth_field($$$$) {
  my ( $record, $field, $subfield, $skip ) = @_;

  $field = &normalize_tag($field);


  my @array = marc21_record_get_fields($record, $field, $subfield);
  if ( defined($array[$skip]) ) {
    return $array[$skip];
  }
  return undef; # 20161124: replace original ''...
}

sub marc21_record_get_field($$$) {
  return marc21_record_get_nth_field($_[0], $_[1], $_[2], 0);
}




sub marc21_record_has_1XX($) {
    my $record = shift;
    my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
    my @darr = marc21_directory2array($directory);
    for ( my $i=0; $i <= $#darr; $i++ ) {
	if ( $darr[$i] =~ /^(1..)/ ) {
	    return $1;
	}
    }
    return undef;
}

sub marc21_to_sequential($$) {
  my ( $record, $prefix ) = @_;
  if ( !defined($prefix) ) {
    $prefix = marc21_record_get_field($record, '001', '');
  }
  print STDERR "Processing $prefix\n";

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;
  my ($i, $j);

  $leader =~ s/ /\^/g;
  my $seq = "$prefix LDR   L " . $leader. "\n";

  #for ( $i=$#tags; $i <= $#tags; $i++ ) {
  for ( $i=0; $i <= $#tags; $i++ ) {
    my $line = '';

    $line .= "$prefix ";
    $line .= $tags[$i];
    if ( 1 ) { # jos 1, niin isot menee sellaisenaan..
    }
    # Aleph ei syö liian isoja kenttiä, ks.
    # https://knowledge.exlibrisgroup.com/Aleph/Knowledge_Articles/Long_MARC_Fields%2C_Limits_and_Splitting
    # (Standardi sallis 9999 pituuden)

    elsif ( length($contents[$i]) > 1900 ) {
      if ( $contents[$i] =~ /^((..).{1000,1200}[\.:;]) ([A-Z0-9]|Å|Ä|Ö)/ ||
	   $contents[$i] =~ /^((..).{1000,1200}(?: \-\-?| \/| :)|,) ([a-zA-Z0-9]|Å|Ä|Ö)/ ||
	   # Seuraavan alku:
	   $contents[$i] =~ /^((..).{1000,1200}(\S)) (\(|\[|\-\-)/ ||
	   $contents[$i] =~ /^((..).{1000,1200}) ([a-z0-9A-Z])/ ||
	   # desperate: välilyönti ja mitä tahansa:
	   $contents[$i] =~ /^((..).{1000,1200}) ()/ ||
	   # kiinaa tai jotain muuta outoa, splittaa nyt vaan jossakin...
	   $contents[$i] =~ /^((..).{1000,1200}[^\x1D\x1E\x1F]{2})([^\x1D\x1E\x1F])/
	 ) {
	# 1: koko vanha osa, 2: indikaattorit, 3: uusi osa
	my $l = $1."^";
	my $rhead = $2."\x1F9^^";
	my $rtail = $3.$'; # '
	$l =~ /(\x1F[a-z0-9])[^\x1F]+$/ or die(); # ota vika osakenttäkoodi
	my $sf = $1;
	my $r = $rhead . $sf . $rtail;
	print STDERR "$prefix\tsplit overlong line\n";
	$contents[$i] = $l;
	splice(@contents, $i+1, 0, $r);
	splice(@tags, $i+1, 0, $tags[$i]);
      }
      else {
	print STDERR "$prefix SKIPPED\tHAS OVERLONG FIELD!\n";
	print STDERR $contents[$i], "\n";
	return '';
      }
    }

    my @sf = split(/\x1F/, $contents[$i]);
    if ( $#sf > 0 ) {
      $line .= $sf[0]; # indicaattorit
      $line .= ' L ';
      for ( $j=1; $j<=$#sf; $j++ ) {
	$line .= "\$\$$sf[$j]";
      }
    }
    else {
      if ( $tags[$i] =~ /^00/ ) {
	$contents[$i] =~ s/ /\^/g;
      }
      $line .= '  ';
      $line.= ' L ';
      $line .= $contents[$i];
    }
    $line .= "\n";
    $seq .= $line;
    #if ( $i == $#tags ) { return $line; } # tilapäinen bugikorjaushack: palauta vain vika rivi
  }
  return $seq;
}


sub marc21_field2string($) {
    # Convert to more human-readable form
    my $field = shift();
    if ( $field =~ s/\x1F(.)/ ‡$1 /g ) {
	$field =~ s/^ /#/;
	$field =~ s/^(.) /$1#/;
	return $field;
    }
    $field =~ s/ /#/g;
    return $field;
}

sub marc21_field_get_subfields($$) {
  my ( $field, $sf_code ) = @_;

  my @subfields = split(/\x1F/, $field);
  shift(@subfields); # skip $subfields[0], which contains indicators
  if ( !defined($sf_code) || $sf_code eq '' ) {
    return @subfields
  }
  my @sf2 = ();
  my $i;
  for ( $i = 0; $i <= $#subfields; $i++ ) {
      my $sf = $subfields[$i];
      if ( $sf =~ s/^$sf_code// ) { # removes subfield code, should it?
	  push(@sf2, $sf);
      }
  }
  return @sf2;
}

sub marc21_rebuild($) {
  print STDERR "marc21_rebuild(\$record)\n";
  my $record = shift();

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  # my $i; for ( $i=0; $i <= $#tags; $i++ ) { print STDERR "$tags[$i]\t'$contents[$i]'\n"; }

  my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

  return $new_record;
}

sub tag2val($$) {
    my ( $tag, $content ) = @_;
    # SORT ORDER...
    if ( $tag =~ /^[1-9][0-9][0-9]$/ ) {
	# Special ordering for 65X fields (terms and keywords)
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
    if ( $tag eq 'LDR' ) { return 0; }
    return 1000;
}

sub marc21_record_sort($) {
    # print STDERR "marc21_record_sort(\$record)\n";
  my $record = shift();

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  
  my $upper_limit = $#tags;
  for ( my $j=0; $j < $upper_limit; $upper_limit-- ) {
      for ( my $i=0; $i < $upper_limit; $i++ ) {
	  my $tag1 = $tags[$i];
	  my $tag2 = $tags[$i+1];
	  my $val1 = tag2val($tag1, $contents[$i]);
	  my $val2 = tag2val($tag2, $contents[$i+1]);
#	  if ( $upper_limit == $#tags ) {
#	      print STDERR "$i\t$val1\t$tag1 ", $contents[$i], "\n";
#	  }
	  #print STDERR "SORT at $i: $tag1 '$val1' vs $tag2 '$val2'\n";
	  # Should this handle adding of 006?
	  if ( $val1 >= 10 && $val1 <= 1000 &&
	       $val2 >= 10 && $val2 <= 1000 ) {
	      #print STDERR "SORT at $i: $tag1 '$val1' vs $tag2 '$val2'\n";
	      if ( $val1 > $val2 ) {
		  if ( $tag1 =~ /^\d+$/ && $tag2 =~ /^\d+$/ ) {
		      #print STDERR "SWAP at $i: $tag1 '$val1' '", $contents[$i], "' vs $tag2 '$val2' '", $contents[$i+1], "'\n";
		      #print STDERR "SWAP FIELDS $val1 and $val2\n";
		  }
		  my $tmp = $tags[$i];
		  $tags[$i] = $tags[$i+1];
		  $tags[$i+1] = $tmp;
		  $tmp = $contents[$i];
		  $contents[$i] = $contents[$i+1];
		  $contents[$i+1] = $tmp;
	      }
	  }
      }
  }
  
  my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

  return $new_record;
}


# TODO: nth

  




sub marc21_record_add_field_after($$$$) {
  # Meillä on bugi, jos tietueella ei ole utf-8-lippua päällä (vaikka siellä
  # olisi utf-8:aa), mutta uudella kentällä on, niin ylikonvertointia tapahtuu..
  my ( $original_record, $new_tag, $new_data, $preceding_data ) = @_;

  if ( $debug ) {
    print STDERR "marc21_record_add_field_after(record, $new_tag, '$new_data', )\n";
  }

  # Älä lisää samaa kenttää kahdesti...
  if ( $new_tag ne '952' ) { # 952 on koha-spesifi kikkare/poikkeus
    # (jota tuskin tarvitaan enää)
    if ( marc21_record_has_field($original_record, $new_tag, undef, $new_data) ) {
      print STDERR "NB: no need to add field $new_tag: duplicate '$new_data'!\n";
      return $original_record;
    }
  }

  # print STDERR "$original_record\n\n";

  #my $original_size = bytes::length(Encode::encode_utf8($original_record));
  #my $original_size = bytes::length($original_record);
  my $original_size = marc21_length($original_record);

  my $record = $original_record;

  $new_data =~ s/\x1e$//;

  my $added_len = 0;
  if ( $new_tag ne '' ) {
    #$added_len = bytes::length(Encode::encode_utf8($new_data))+12+1; # 1 is for the (new) \x1e
    #$added_len = bytes::length($new_data)+12+1; # 1 is for the new \x1E
    $added_len = marc21_length($new_data)+12+1; # 1 is for the new \x1E
    if ( $added_len > 9999 ) { # TOO LONG
      print STDERR "Overlong content...\n";
      $new_data = substr($new_data, 0, (9999-12-1-3));
      $new_data =~ s/[ .]*$/.../;
      $added_len = marc21_length($new_data)+12+1; # 1 is for the new \x1E
    }
  }
  else {
    # Mikä idiotismi tuo ehto oli=
    die();
  }

  if ( $original_size == 24 ) {
    # $record has only directory, so it will get a \x1e as well:
    $added_len++;
  }


  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);

  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;


  ## Determine the location of the new tag
  ## (often the new tag goes after identical tags)
  my $i;
  if ( $new_tag ne '' ) {
      my $new_position = -1;
      if ( defined($preceding_data) ) {
          for ( my $i=0; $i <= $#tags && $new_position == -1; $i++ ) {
              if ( $tags[$i] eq $new_tag ) {
                  if ( $contents[$i] eq $preceding_data ) {
                      $new_position = $i + 1;
                  }
              }
          }
          if ( $new_position == -1 ) {
              print STDERR "Failed to add $new_tag $new_data after $preceding_data.\n";
              print STDERR "  Adding it to the normal position.\n";
	      
          }
          
      }

      my $val = tag2val($new_tag, $new_data);
      if ( $new_position == -1 ) {
	  $new_position = $#tags+1; # the end
	  for ( my $i=$#tags; $i >= 0 ; $i-- ) {
	      my $old_tag = $tags[$i];
	      my $old_content = $contents[$i];
	      my $old_val = tag2val($old_tag, $old_content);
	      if ( $val < $old_val ) {
		  $new_position = $i;
	      }
	      else { $i = -1; } # break da loop
	  }
      }

      if ( $new_position == $#tags+1 ) {
          $tags[$new_position] = $new_tag;
          $contents[$new_position] = $new_data;
      }
      else {
          splice(@tags, $new_position, 0, $new_tag);
          splice(@contents, $new_position, 0, $new_data);
      }
  }



  # DEBUG:
  if ( 0 ) {
    print STDERR "NRE LEADER '$leader'\n";
    for ( $i=0; $i <= $#tags || $i <= $#contents; $i++ ) {
      print STDERR "$i\t$tags[$i]\t$contents[$i]\n";
    }
  }
  # update directory and contents:
  my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);

  

  # print STDERR "NEW TEST\n$new_record\n\n";

  #my $length = bytes::length(Encode::encode_utf8($new_record));
  #my $length = bytes::length($new_record);
  my $length = marc21_length($new_record);
  if ( $length != $original_size + $added_len ) {
    print STDERR "WARNING: size $original_size + $added_len != $length (12+length('$new_data'))\n";
    print STDERR "\n### raf ORIG\n'$original_record'\n### raf NEW\n'$new_record'\n###\n";
    print STDERR "TAGS 1+$#tags CONTENTS 1+$#contents\n";

    #print STDERR marc21_debug_record($original_record, "ORIGINAL RECORD");
    #print STDERR "\n\n";
    #print STDERR marc21_debug_record($new_record, "NEW RECORD");
    #print STDERR "\n\n";

    die("DOOM");
  }
  return $new_record;
}

sub marc21_record_add_field($$$) {
  my ( $original_record, $new_tag, $new_data ) = @_;
  return marc21_record_add_field_after($original_record, $new_tag, $new_data, undef);
}



sub marc21_record_replace_nth_field($$$$) {
    my ( $record, $field, $new_data, $nth ) = @_;
    if ( !defined($new_data) || $new_data eq '' ||
         # Viimeinen osakenttä poistettu
         ( $field =~ /^[0-9][0-9][0-9]$/ && $field !~ /^00.$/ &&
           length($field) == 2 ) ) {
        return marc21_record_remove_nth_field($record, $field, '', $nth);
    }
    #my $original_size = length($record);
    
    # Validate new field (well, almost)
    if ( $new_data !~ /\x1e$/ ) { $new_data .= "\x1e"; }

    my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
    my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);
    my @tags = @$tags_ref;
    my @contents = @$contents_ref;
    
    my $new_position = $#tags+1; # last
    my $i = 0;
    for ( $i=0; $i<$new_position; $i++ ) {
        if ( $tags[$i] eq $field ) {
            if ( $nth > 0 ) {
                $nth--;
            }
            else {
                if ( $debug ) {
                    print STDERR " replace $field '$contents[$i]' with '$new_data'\n";
                }
                $contents[$i] = $new_data;
                my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
                
                return $new_record;
            }
        }
    }
    
    print STDERR "Warning! No replacement done for $field ('$new_data').\n";
    die();
    return $record;
}


sub marc21_fix_composition($) {
  my ( $record ) = @_;

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);
  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $changes = 0;
  for ( my $i=0; $i <= $#tags; $i++ ) {
    my $tmp = unicode_fixes2($contents[$i], 1);
    if ( $tmp ne $contents[$i] ) {
      $changes++;
      $contents[$i] = $tmp;
    }
  }
  if ( $changes ) {
    $record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
  }
  
  return $record;
}

sub marc21_record_replace_field($$$) {
  my ( $record, $new_field, $new_data ) = @_;
  return marc21_record_replace_nth_field($record, $new_field, $new_data, 0);
}


# remove nth $field or part of it
sub marc21_record_remove_nth_field($$$$) {
  my ( $record, $field, $subfield, $nth) = @_;

  #print STDERR "Removing $field$subfield from\n$record\n";

  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $carry_on = 1;
  my $i;
  for ( $i = 0; $carry_on && $nth >= 0 && $i <= $#tags; $i++ ) {
    #print STDERR "'$field' vs '$tags[$i]', $nth\n";
    if ( $tags[$i] eq $field ) {
      #print STDERR "HIT $field vs $tags[$i], $nth\n";
      if ( $nth == 0 ) {
	if ( $subfield ) {
	  # remove the subfield
	  if ( $contents[$i] =~ s/(\x1F$subfield[^\x1F\x1E]+)// ) {


	    # if it is the last subfield, remove the whole field
	    if ( $contents[$i] !~ /\x1F/ ) {
	      if ( $debug ) { print STDERR "Removing $field from the record\n"; }
	      splice(@contents, $i, 1);
	      splice(@tags, $i, 1);
	    }
	    else {
	      # 2013-02-07: due to a deletion, remove the now-unneeded ','
	      # (This is probably way more generic, but I need for only f400
	      # now). Mayve there should be a '.' instead?
	      if ( $field eq '400' ) {
		$contents[$i] =~ s/[, ]+$//;
	      }
	      if ( $debug ) {
		print STDERR "Removing subfield $field|$subfield ('$1'), now: '$contents[$i]'\n";
	      }
	    }

	    $carry_on = 0;
	  }
	}
	else { # remove whole field
	  if ( $debug ) { print STDERR "Removing $field from the record (no subfield)\n", $tags[$i], "\t'", $contents[$i], "'\n"; }
	  splice(@contents, $i, 1);
	  splice(@tags, $i, 1);
	  $carry_on = 0;
	}
      }
      $nth--;
    }
  }
  if ( !$carry_on ) {
    my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
    return $new_record;
  }

  return $record;
}



sub marc21_record_remove_field($$$) {
    # 20180131: added support from deletion by content
    my ( $record, $tag, $subfield_code_or_content) = @_;
    # Handle removal by content:
    if ( defined($subfield_code_or_content) &&
         ( $tag =~ /^00[1-9]$/ || $subfield_code_or_content =~ /.\x1F/ ) ) { # content
        my @fields = marc21_record_get_fields($record, $tag, undef);
        for ( my $i=0; $i <= $#fields; $i++ ) {
            #print STDERR "TEST '$subfield_code_or_content' vs '$fields[$i]'\n";
            if ( $fields[$i] eq $subfield_code_or_content ) {
                return marc21_record_remove_nth_field($record, $tag, undef, $i);
            }
        }
        #print STDERR "Failed to remove $tag '$subfield_code_or_content'\n";
        return $record;
    }
    # Handle removal by subfield code (if any):
    else {
        return marc21_record_remove_nth_field($record, $tag, $subfield_code_or_content, 0);
    }
}

sub marc21_record_move_field($$$$) {
  my ( $original_record, $from_tag, $to_tag, $content) = @_;
  if ( $from_tag eq $to_tag ) {
    return $original_record;
  }

  my $record = marc21_record_remove_field($original_record, $from_tag, $content);
  
  if ( $record eq $original_record ) { # removal failed, don't add either
    return $original_record;
  }
  my $record2 = marc21_record_add_field($record, $to_tag, $content);
  if ( $record eq $record2 ) {
    return $original_record;
  }
  return $record2;
}


sub marc21_record_remove_fields($$$) {
  my ( $record, $field, $subfield ) = @_;

  my @fields = marc21_record_get_fields($record, $field, '');
  my $i;
  # NB! Removal of fields begins from the last!
  for ( $i=$#fields; $i >= 0; $i-- ) {
    if ( !defined($subfield) || $subfield eq '' ) {
      $record = marc21_record_remove_nth_field($record, $field, undef, $i);
    }
    else {
      my $fieldata = $fields[$i];
      $fieldata = marc21_field_remove_subfields($fieldata, $subfield);
      if ( $fieldata ne $fields[$i] ) {
	$record = marc21_record_replace_nth_field($record, $field, $fieldata, $i);
	if ( $debug ) {
	  print STDERR " SUBFIELD MAGIC: '$fields[$i]' => '$fieldata'\n";
	}
      }
    }
  }
  return $record;
}


sub marc21_is_utf8($) { # po. is_utf8
  use bytes;
  my ($val, $msg ) = @_;
  my $original_val = $val;
  my $i = 1;
  while ( $i ) {
    $i = 0;
    if ( $val =~ s/^[\000-\177]+//s ||
         $val =~ s/^([\300-\337][\200-\277])+//s ||
         $val =~ s/^([\340-\357][\200-\277]{2})+//s ||
         $val =~ s/^([\360-\367][\200-\277]{3})+//s ) {
       $i=1;
    }
  }
  no bytes;
  if ( $val eq '' ) {
    return 1;
  }
#  #if ( $val !~ /^([\000-\177\304\326\344\366])+$/s ) {
#  my $reval = $val;
#  $reval =~ s/[\000-177]//g;
#  unless ( $reval =~ /^[\304\326\344\366]+$/ ) {
#    $i = ord($val);
#    my $c = chr($i);
#    #print STDERR "$msg: UTF8 Failed: '$c'/$i/'$val'\n$original_val\n";
#
#  }
  return 0;
}

sub marc21_length($) {
  my $data = $_[0];

  return length($data);

#  my $l = $data =~ tr/\x1D\x1E\x1F//d;
#  return $l + bytes::length(Encode::encode('UTF-8', $data));

##  if ( length($data) !=  bytes::length($data) ) {
##    print STDERR "\nCHECK LENGTHS...\n$data\n", "LEN\t", length($data), "\tLEN B\t", bytes::length($data), "\n\n";
##  }
##  return $l + bytes::length($data);
  
}

sub string_replace($$$) {
  my ( $string, $find, $replace ) = @_;
  my $pos = index($string, $find);

  while($pos > -1) {
    substr($string, $pos, length($find), $replace);
    $pos = index($string, $find, $pos + length($replace));
  }
  return $string;
}


sub unicode_strip_diacritics($) {
  my $str = $_[0];

  $str =~ s/́//g;
  $str =~ s/̆//g;   $str =~ s/̌//g;


  $str =~ s/̂//g;
  $str =~ s/̀//g;
  $str =~ s/̈//g; $str =~ s/̈//g;
  $str =~ s/̊//g;

  $str =~ s/̄//g;

  $str =~ s/̧//g;
  $str =~ s/̣//g;

  $str =~ s/̃//g;

  return $str;
}


sub marc21_mark_record_as_deleted($) {
  my $record = shift();
  $record =~ s/^(.....)./${1}d/;
  $record = marc21_record_add_field($record, 'STA', "  \x1FaDELETED");
  return $record;
}

sub marc21_record_is_deleted($) {
  my $record = shift();
  if ( $record =~ /^.....[dsx]/ ) {
    # NB! 's' and 'x' are auth-specific (more specific than the usual 'd')
    return 1;
  }
  # Aleph-specific stuff:
  my @sta = marc21_record_get_fields($record, 'STA', 'a');
  for ( my $i=0; $i <= $#sta; $i++ ) {
    if ( defined($sta[$i]) && $sta[$i] eq 'DELETED' ) {
      return 1;
    }
  }
  my @del = marc21_record_get_fields($record, 'DEL', undef);
  if ( $#del > -1 ) {
    return 1;
  }

  return 0;
}

sub nvolk_marc212oai_marc($) {
  my $record = shift();
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $n_tags = $#tags + 1;
  if ( $n_tags == 0 ) { die(); }

  my $clean_up_marc = ( $record =~ /[\x00-\x08\x0B\x0C\x0E-\x1C]/ ? 1 : 0 );
  my $clean_up_xml = ( $record =~ /[<>&]/ ? 1 : 0 );

  # Hmm.. Oliskohan ratkaisu, jossa stringit talletetaan @output-taulukkoon
  # ja lopuksi $output = join('', @output) parempi?
  # Nyt nuo kootaan $output-muuttujaan...
  my $output = "<record xmlns=\"http://www.loc.gov/MARC21/slim\">\n<leader>$leader</leader>\n";

  my $id = '???'; # marc21_record_get_field($record, '001', undef);

  for ( my $i=0; $i < $n_tags; $i++ ) {
    my $tag = $tags[$i];
    my $content = $contents[$i];
    if ( $tag =~ /^00[1-9]$/ ) {
      if ( $tag eq "001" ) { $id = $content; }
      if ( $content =~ /[\x00-\x08\x0B\x0C\x0E-\x1F]/ ) {
	print STDERR "WARNING: Removing wierd characters from '$content' (record: $id, tag: $tag) \n";
	$content =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
	$clean_up_marc = 1;
      }
      # Normalisoidaanko entiteetit, ei niitä pitäisi olla, mutta
      # toisaalta kiinteämittaisia kenttiä on niin vähän, ettei tehojutut
      # haittaa...
      if ( $clean_up_xml ) {
	$content = html_escapes($content);
	$clean_up_marc = 1;
      }
      $output .= "<controlfield tag=\"$tag\">$content</controlfield>\n";
    }
    else {
      my $sep = substr($content, 2, 1);
      if ( $sep eq "\x1F" ) {
	my $i1 = substr($content, 0, 1);
	my $i2 = substr($content, 1, 1);
	# TODO: indicator sanity checks?
	$content = substr($content, 3); # the rest: subfield contents

	# Tee osakentät:
	my $subfield_contents = '';
	my @subs = split(/\x1F/, $content);
	my $n_subs = $#subs+1;

	for ( my $j=0; $j < $n_subs; $j++ ) {
	  my $sf = $subs[$j];
	  if ( length($sf) ) {
	    # I assume that my earlier /^(.)(.*)$/ was way slower than
	    # the substr()-based solution below:
	    my $sf_code = substr($sf, 0, 1); # first char: subfield code
	    if ( $sf_code =~ /^[a-z0-9]$/ ) {
	      my $sf_data = substr($sf, 1); # the rest: subfield contents
	      if ( $sf_data =~ /[\x00-\x08\x0B\x0C\x0E-\x1F]/ ) {
		print STDERR "WARNING: Removing wierd characters from '$sf_data' (record: $id, tag: $tag$sf_code)\n";
		$sf_data =~ s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g;
	      }
	      if ( $clean_up_xml ) {
		$sf_data = html_escapes($sf_data);
	      }
	      $subfield_contents .= " <subfield code=\"$sf_code\">".$sf_data."</subfield>\n";
	    }
	    else {
	      $clean_up_marc = 1;
	      my $prefix = get_record_type($record);
	      print STDERR "WARNING: Skipping subfield '$sf_code' ($prefix-$id)\n";
	    }
	  }
	}
	if ( length($subfield_contents) ) {
	  $output .= "<datafield tag=\"$tag\" ind1=\"$i1\" ind2=\"$i2\">\n" .
	    $subfield_contents .
	    "</datafield>\n";
	}
      }
      else {
	print STDERR "WARNING: Skipping subfield '$content' due to erronous marc21 (record $id)\n";
	$clean_up_marc = 1;
      }
    }
  }

  $output .= "</record>\n";
  # Pitääkö nämä klaarata täällä vai missä?
  $output =~ s/'/&#39;/g;
  return $output;
}


sub nvolk_marc212aleph($) {
  # TODO: optimize the code here as well, see nvolk_marc212oai_marc($).
  my $record = shift();
  $record = marc21_record_target_aleph($record);
  my ( $leader, $directory, $cfstr ) = marc21_record2leader_directory_fields($record);
  my ( $tags_ref, $contents_ref ) = marc21_dir_and_fields2arrays($directory, $cfstr);

  my @tags = @$tags_ref;
  my @contents = @$contents_ref;

  my $output = '<?xml version = "1.0" encoding = "UTF-8"?>
<find-doc 
  xmlns="http://www.loc.gov/MARC21/slim" 
  xmlns:slim="http://www.loc.gov/MARC21/slim" 
  xmlns:oai="http://www.openarchives.org/OAI/1.1/oai_marc">
  <record>
    <metadata>
      <oai_marc>
';

  $output .= "        <fixfield id=\"LDR\">" . $leader . "</fixfield>\n";
  my $i;
  for ( $i=0; $i <= $#tags; $i++ ) {
    my $tag = $tags[$i];
    my $content = $contents[$i];
    if ( $tag =~ /^00[1-9]$/ ) {
      $output .= "        <fixfield id=\"$tag\">$content</fixfield>\n";
    }
    elsif ( $content =~ s/^(.)(.)\x1F// ) {
      my $i1 = $1;
      my $i2 = $2;
      $output .= "        <varfield id=\"$tag\" i1=\"$i1\" i2=\"$i2\">\n";
      my @subs = split(/\x1F/, $content);
      for ( my $j=0; $j <= $#subs; $j++ ) {
	my $sf = $subs[$j];
	$sf =~ /^(.)(.*)$/;
	my $sf_code = $1;
	my $sf_data = $2;
	if ( $sf_data eq "" ) {
	  $output .= "          <subfield label=\"$sf_code\"/>\n";
	}
	else {
	  $output .= "          <subfield label=\"$sf_code\">".html_escapes($sf_data)."</subfield>\n";
	}
      }
      $output .= "        </varfield>\n";
    }
    else {
      print STDERR marc21_debug_record($record, "RECORD");
      die("$tag\t'$content'");
    }
  }
  if ( $i == 0 ) { die(); }
  $output .= "      </oai_marc>
    </metadata>
  </record>
</find-doc>
";
  return $output;
}

sub nvolk_oai_marc2marc21($) {
  # FFS! XML::XPath converts perfectly valid utf-8 (bytes) to a "string".
  # NB! Makes too many assumptions with regexps... Needs improving!
  my $xml = shift();

  my $leader1 = undef;
  my @tags1 = ();
  my @contents1 = ();


  if ( 1 ) {
    my $record = &xml_get_first_instance($xml, 'record');
    $record = &xml_get_first_instance($record, 'oai_marc');
    $record = &only_contents($record);
    my $proceed = 1;
    while ( $proceed ) {
      $record = &trim($record);
      $proceed = 0;

      if ( !defined($leader1) && $record =~ s/^<fixfield id=\"LDR\">([^<]+)<\/fixfield>\s*//s ) {
	$leader1 = $1;
	$leader1 =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
	$leader1 =~ tr/^/ /;
	$proceed = 1;
      }
      elsif ( $record =~ s/^<fixfield id=\"(...)\">([^<]+)<\/fixfield>\s*//s ) {
	my $tag = $1;
	my $content = $2;
	$content =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
	$content =~ tr/^/ /;
	push(@tags1, $tag);
	push(@contents1, $content);
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
	my $varfield = &xml_get_first_instance($record, 'varfield');
	$record = &remove_data_from_xml($record, $varfield);

	$varfield = &only_contents($varfield);

	my $proceed2 = 1;
	while ( $proceed2 ) {
	  $varfield = &trim($varfield);
	  $proceed2 = 0;
	  $varfield =~ s|^(<subfield label="(.)")/>|$1></subfield>|;

	  if ( $varfield !~ /\S/ ) { }
	  elsif ( $varfield =~ s/^<subfield label=\"(.)\">(.*?)<\/subfield>\s*// ) {
	    my $sfcode = $1;
	    my $sfvalue = $2;
	    if ( !marc21_is_utf8($sfvalue) ) {
	      print STDERR "Encoding '$sfvalue' to ";
	      die();
	      $sfvalue = Encode::encode('UTF-8', $sfvalue);
	      print STDERR "'$sfvalue'\n";
	    }

	    $str .= "\x1F${sfcode}${sfvalue}";
	    $proceed2 = 1;
	  }
	  else {
	    die($varfield);
	  }
	}

	if ( $str ne '' ) {
	    $str = &encoding_fixes($str);
	    push(@tags1, $tag);
	    push(@contents1, "$ind1$ind2$str");
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

    if ( $leader1 && $#tags1 > -1 ) {
      for ( my $i=0; $i <= $#tags1; $i++ ) {
	if ( $tags1[$i] =~ /\&/ ) {
	  $tags1[$i] =~ s/\&#39;/'/g;
	  # $tags1[$i] =~ s/\&#39;/'/g;
	}
      }
      my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader1, \@tags1, \@contents1);
      return $new_record;
    }
    print STDERR "$leader1\n$#tags1 tags\n";
    die("TODO: TEST");
  }
  
  die("KESKEN");

  my $xp = XML::XPath->new( $xml );
  my $nodeset = $xp->find('/present/record/metadata/oai_marc');
  my $leader = undef;
  my @tags = ();
  my @contents = ();

  my %skipped;

  foreach my $node ( $nodeset->get_nodelist ) {

    my $contents = XML::XPath::XMLParser::as_string($node);
    # print "FOO: $contents";
    my $xpp = XML::XPath->new($contents);
    my $nodeset2 = $xpp->find('/oai_marc/*');
    foreach my $node2 ( $nodeset2->get_nodelist ) {
      my $contents2 = XML::XPath::XMLParser::as_string($node2);
      if ( !marc21_is_utf8($contents2) ) {
	$contents2 = Encode::encode('UTF-8', $contents2);
      }

      if ( $contents2 =~ /^<fixfield id=\"(...)\">([^<]+)<\/fixfield>\s*$/ ) {
	my $tag = $1;
	my $content = $2;
	if ( $tag eq "LDR" ) {
	  $leader = $content;
	}
	else {
	  push(@tags, $tag);
	  push(@contents, $content);
	}
      }
      elsif ( $contents2 =~ /^<varfield id=\"(...)\" i1=\"(.)\" i2=\"(.)\">/ ) {
	my $tag = $1;
	my $ind1 = $2;
	my $ind2 = $3;
	my $str = "";
	my $xppp = XML::XPath->new($contents2);
	my $nodeset3 = $xppp->find('/varfield/subfield');
	foreach my $node3 ( $nodeset3->get_nodelist ) {
	  #my $contents3 = Encode::encode('UTF-8', XML::XPath::XMLParser::as_string($node3));
	  my $contents3 = XML::XPath::XMLParser::as_string($node3);
	  if ( !marc21_is_utf8($contents3) ) {
	    $contents3 = Encode::encode('UTF-8', $contents3);
	  }

	  print "FOO: $contents3\n";
	  if ( $contents3 =~ /^<subfield label=\"(.)\" \/>\s*$/ ) {
	    my $sfcode = $1;
	    if ( 1 ) { # Säilytä tyhjä
	      $str .= "\x1F${1}";
	    }
	    else {
	      if ( !defined($skipped{"$tag$sfcode"}) ) {
		print STDERR " $tag: skip empty subfield '$tag$sfcode' (warn only once)\n";
		$skipped{"$tag$sfcode"} = 1;
	      }
	    }
	    # print STDERR "'$contents2'\n";
	  }
	  elsif ( $contents3 =~ /^<subfield label="(.)">([^<]+)<\/subfield>\s*$/ ) {
	    $str .= "\x1F${1}${2}";
	  }
	  else {
	    die();
	  }
	}
	if ( $str ne '' ) {
	    $str = &encoding_fixes($str);

	    push(@tags, $tag);
	    push(@contents, "$ind1$ind2$str");
	}
	else {
	  die("No content");
	}
      }
    }
    if ( $leader && $#tags > -1 ) {
      my $i;

      for ( $i=0; $i<=$#tags;$i++ ) {
	print STDERR "NV$i\t$tags[$i]\t$contents[$i]\n";
      }

      my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader, \@tags, \@contents);
      #exit();
      return $new_record;
    }
  }

  die();


}

sub nvolk_split_marcxml($) {

  my $xml = shift();
  my @arr = ();

  my $start;
  my $end;

  my $end_tag_length = length("</record>");

  if ( $xml =~ s|(<record(( [^>]+)+)>)|<record>|g ) {
    print STDERR "Simplified $1 as <record>\n";
  }
  while ( ($start = index($xml, '<record>') ) ) {
    $xml = substr($xml, $start);
    $end = index($xml, '</record>');
    print STDERR "FOO START $start END $end\n";
    if ( $end < 0 ) {
      return @arr;
    }
    $end += $end_tag_length;
    my $elem = substr($xml, 0, $end);
    push(@arr, $elem);
    $xml = substr($xml, $end);
  }
  return @arr;


  if ( 0 ) { # corrupts charset! don't use!
    my $xp = XML::XPath->new( $xml );
    # Using // as we have some partial files from mets...
    my $nodeset = $xp->find('//record');
    foreach my $node ( $nodeset->get_nodelist ) {
      my $contents = XML::XPath::XMLParser::as_string($node);
      push(@arr, $contents);
    }
    return @arr;
  }
}

sub xml_get_first_instance($$) {
  my ( $data, $tag ) = @_;
  if ( $data =~ /(<$tag(\s[^>]*)?>)/s ) {
    my $target = $1;
    #print STDERR "Found '$target'\n";
    my $start = index($data, "$target");
    if ( $start < 0 ) { die(); }
    # TODO: handle <foo attr="s" />
    my $len;
    if ( $target =~ /\/>$/ ) {
      $len = length($target);
    }
    else {

      $target = "</$tag>";
      #print STDERR "Looking for '$target'\n";


      my $end = index($data, $target);
      if ( $end < $start ) {
	print STDERR "Looking for '$target'\n";
	die("DATA:".$data);
      }
      $len = $end - $start + length($target);
    }
    my $contents = substr($data, $start, $len);

    #print STDERR "CON $contents CON";
    return $contents;
  }

  return undef;
}

sub only_contents($) {
  my $xml = $_[0];
  $xml =~ s/^\s*<.*?>\s*//s or die("OC1: $xml");
  $xml =~ s/\s*<\/[^<]+>\s*$//s or die("OC2: $xml");
  return $xml;
}

sub remove_data_from_xml($$) {
  my ( $str, $stuff ) = @_;
  my $i = index($str, $stuff);
  if ( $i < 0 ) { return $str; }
  substr($str, $i, length($stuff)) = "";
  return $str;
}

sub trim($) {
  my $data = $_[0];
  $data =~ s/^\s*//s;
  $data =~ s/\s*$//s;
  return $data;
}


sub nvolk_marcxml2marc21($) {
  # NB! Return but one (first) record
  # FFS! XML::XPath converts perfectly valid utf-8 (bytes) to a "string".
  # NB! Makes too many assumptions with regexps... Needs improveing!
  my $xml = shift();

  my $leader1 = undef;
  my @tags1 = ();
  my @contents1 = ();

  my $leader2 = undef;
  my @tags2 = ();
  my @contents2 = ();

  my $record = &xml_get_first_instance($xml, 'record');
  $record = &only_contents($record);
  #print STDERR "GOT RECORD '$record'\n";
  # PROCESS LEADER:
  my $ldr = &xml_get_first_instance($record, 'leader');
  if ( $ldr ) {
    $record = &remove_data_from_xml($record, $ldr);
    $ldr = &only_contents($ldr);
    $leader1 = $ldr;
    $leader1 =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
  }
  $record = &trim($record);
  
  my $proceed = 1;
  while ( $proceed ) {
    $record = &trim($record);
    $proceed = 0;
    if ( $record =~ s/^<controlfield tag=\"(...)\">([^<]+)<\/controlfield>\s*//s ) {
      my $tag = $1;
      my $content = $2;
      
      $content =~ s/\#/ /g; # TAV2-data, Mintun bugiraportti, Melinda 7322871:
      #print STDERR "GOT CONTROLFIELD $tag: '$content'\n";
      push(@tags1, $tag);
      push(@contents1, $content);
      $proceed = 1;
    }
    elsif ( $record =~ /^<datafield tag=\"(...)\" ind1=\"(.)\" ind2=\"(.)\">/ ) {

      my $tag = $1;
      my $ind1 = $2;
      my $ind2 = $3;
      my $str = '';
      my $datafield = &xml_get_first_instance($record, 'datafield');

      #print STDERR "GOT DATAFIELD $tag i1 '$ind1' i2 '$ind2'\n";
      #print STDERR "DF v1 '$datafield'\n";
      $record = &remove_data_from_xml($record, $datafield);
      $datafield = &only_contents($datafield);
      #print STDERR "DF v2 '$datafield'\n";
      my $proceed2 = 1;
      while ( $proceed2 ) {
	$datafield = &trim($datafield);
	# if ( $datafield ne '' ) { print STDERR "DATAFIELD: '$datafield'\n"; }
	$proceed2 = 0;
	if ( $datafield !~ /\S/ ) { }
	elsif ( $datafield =~ s/^<subfield code=\"(.)\">(.*?)<\/subfield>\s*// ) {
	  my $sfcode = $1;
	  my $sfvalue = $2;
	  if ( 0 && !marc21_is_utf8($sfvalue) ) {
	    $sfvalue = Encode::encode('UTF-8', $sfvalue);
	  }
	  
	  $str .= "\x1F${sfcode}${sfvalue}";
	  #print STDERR "IS NOW '$str'\n";
	  $proceed2 = 1;
	}
	else {
	  die($datafield);
	}
      }
      if ( $str ne '' ) {
	  $str = &encoding_fixes($str);
	  #print STDERR "NVV $tag $ind1 $ind2 '$str'\n";
	  push(@tags1, $tag);
	  push(@contents1, "$ind1$ind2$str");
	  $proceed = 1;
      }
      else {
	die();
      }
      
    }
  }

  if ( $leader1 && $#tags1 > -1 ) {
    my $new_record = &marc21_leader_directoryarr_fieldsarr2record($leader1, \@tags1, \@contents1);
    #print STDERR marc21_debug_record($new_record, "NEW MARCXML IMPORT");
    #exit();
    return $new_record;
  }

  die("LEFT: '$record'");
  #print STDERR marc21_debug_record($new_record, "NEW v2");
}


# Tämä ei kuuluisi tänne, mutta olkoon...
sub _publisher_b($) {
  my $field = $_[0];
  my $b = marc21_field_get_subfield($field, 'b');
  if ( defined($b) && $b =~ /\S/ ) {
    if ( $b !~ /tuntematon/i ) {
      $b =~ s/( *:|,)$//;
      return $b;
    }
  }
  return undef;
}

sub marc21_record_get_publisher_field($) {
  my $record = $_[0];


  my @cands = marc21_record_get_fields($record, '264', undef);
  @cands = grep(/^.1/, @cands);

  for ( my $i=0; $i <= $#cands; $i++ ) {
    my $cand = $cands[$i];
    if ( defined(_publisher_b($cand)) ) {
      return $cands[$i];
    }
  }
  
  # Käytä 260-kenttää (ET) vain jos 264 on tyhjä:
  my $publisher = marc21_record_get_field($record, '260', undef);
  if ( defined($publisher) ) {
    if ( $#cands == -1 && defined(_publisher_b($publisher)) ) {
      return $publisher;
    }
  }

  # Joskus on vaan vuosi tms... Nekin kuitenkin vissiin tulee 773-kenttään...
  if ( $#cands > -1 ) { return $cands[0]; }
  if ( defined($publisher) ) { return $publisher; }
  return undef;
}


sub marc21_record_get_publisher($) {
  my $record = $_[0];

  my $publisher_data = marc21_record_get_publisher_field($record);

  if ( defined($publisher_data) ) {
    print STDERR " '$publisher_data'\n";
    my $b = marc21_field_get_subfield($publisher_data, 'b');
    if ( defined($b) && $b !~ /tuntematon/i ) {
      $b =~ s/( *:|,)$//;
      return $b;
    }
  }
  return undef;
}


sub marc21_record_target_aleph($) {
  # Aleph haluaa kiinteämittaisten kenttien tyhjät caretteina...
  my $record = $_[0];
  $record =~ s/^(.{24})//;
  my $leader = $1;
  $leader =~ s/#/\^/g; # Hack, some data contain this bug
  $leader =~ s/ /\^/g;
  $record = $leader . $record;
  my ( $i, $j );
  for ( $i = 1; $i < 10; $i++ ) { # tags 001 ... 009
    my $tag = "00$i";
    my @fields = &marc21_record_get_fields($record, $tag);
    for ( $j=$#fields; $j >= 0; $j-- ) {
      if ( $fields[$j] =~ s/ /\^/g ) {
	$record = marc21_record_replace_nth_field($record, $tag, $fields[$j], $j);
      }
    }
  }
  return $record;
}


sub marc21_field_has_subfield($$$) {
  my ( $kentta, $osakentta, $arvo ) = @_;

  if ( !defined($osakentta) || $osakentta eq '' ) {
    #print STDERR "marc21_field_equals_field('$kentta', '$arvo')\n";
    if ( $kentta eq $arvo ) { return 1; }
    return 0;
  }

  if ( !defined($arvo) || $arvo eq '' ) {
    if ( $kentta =~ /\x1F$osakentta/ ) { return 1; }
    return 0;
  }

  if ( $debug ) {
      print STDERR "marc21_field_has_subfield('$kentta', '$osakentta', '$arvo')\n";
  }
  
  my @osakenttien_arvot = marc21_field_get_subfields($kentta, $osakentta);
  for ( my $i=0; $i <= $#osakenttien_arvot; $i++ ) {
      #print STDERR "  has sub: \$$osakentta: '$arvo' vs '", $osakenttien_arvot[$i], "'?\n";
      if ( $arvo eq $osakenttien_arvot[$i] ) {
	  #print STDERR "  SF HIT!\n";
	  return 1;
      }
  }
  return 0;
}

sub marc21_record_has_field($$$$) {
  #print STDERR "HF\n";
  my ( $tietue, $kentta, $osakentta, $arvo ) = @_;
  my $val = marc21_record_has_field_at($tietue, $kentta, $osakentta, $arvo);
  if ( $val == -1 ) {
    return 0;
  }
  return 1;
}


sub marc21_record_has_field_at($$$$) {
  #print STDERR "HFA\n";
  my ( $tietue, $kentta, $osakentta, $arvo ) = @_;

  my @kentat = marc21_record_get_fields($tietue, $kentta, '');

  if ( $#kentat < 0 ) {
    return -1;
  }

  # Check that field (and only field) exists. No content checks:
  if ( ( !defined($osakentta) || $osakentta eq '' ) &&
       ( !defined($arvo) || $arvo eq '' ) ) {
      return 1;
  }

  my $i;
  for ( $i=0; $i<=$#kentat; $i++ ) {
      if ( marc21_field_has_subfield($kentat[$i], $osakentta, $arvo) ) {
	  return $i;
      }
  }
  return -1;
}


sub mfhd_record2bib_id($) {
  my ( $mfhd_record ) = @_;
  return marc21_record_get_field($mfhd_record, '004', undef);
}


sub viola_lisaa_puuteluetteloon($) {
  my ( $record ) = @_;

  my $f008 = marc21_record_get_field($record, '008', '');

  my $julkaisumaa = substr($f008, 15, 3);
  my $julkaisuvuosi = substr($f008, 7, 4);
  my $kieli = substr($f008, 37, 4);
  my $aanite = ( $record =~ /^......j/ ? 1 : 0 );
  my $skip583 = 0;

  # Ks. VIOLA-54 kommentit
  if ( $julkaisuvuosi =~ /^\d+$/ && $julkaisuvuosi < 1981 && $aanite ) {
    $skip583 = 1;
  }

  my $nf = "  \x1FaPUUTELUETT.";
  if ( !$skip583 ) {

    unless ( marc21_record_has_field($record, '583', undef, $nf) ) {
      print " Lisätään puuteluettelomerkintä 583 '$nf'\n";
      $record = marc21_record_add_field($record, '583', $nf);
    }
  }

  $nf = "  \x1FaPuuttuu kansalliskokoelmasta";
  unless ( marc21_record_has_field($record, '594', undef, $nf) ) {
    print " Lisätään puuteluettelomerkintä 594 '$nf'\n";
    $record = marc21_record_add_field($record, '594', $nf);
  }

  return $record;
}

sub is_bk($) {
  my $record = $_[0];
  if ( $record =~ /^......[at][^bis]/ ) { return 1; }
  return 0;
}

sub is_cr($) { # countinuing resource, serial
  my $record = $_[0];
  if ( $record =~ /^......[at][bis]/ ) { return 1; }
  return 0;
}

sub is_mu($) {
  my $record = $_[0];
  if ( $record =~ /^......[^cdij]/ ) { # LDR/06 po. cdij
    return 0;
  }
  if ( $record =~ /^.......[bis]/ ) {
    my @f006 = marc21_record_get_fields($record, '006', undef);
    for ( my $i=0; $i <= $#f006; $i++ ) {
      if ( $f006[$i] =~ /^s/ ) { return 1; }
    }
    return 0;
  }
  return 1;
}



sub is_electronic($) {
  my $record = $_[0];
  my @fields = marc21_record_get_fields($record, '007', undef);
  foreach my $field (@fields) {
    if ( $field =~ /^c/ ) { return 1; }
  }
  return 0;
}

sub is_host($) {
  my $record = $_[0];
  if ( $record =~ /^.{7}[ms]/ ) { # [ms]?
    return 1;
  }
  return 0;
}

sub get_record_type($) {
  my $record = $_[0];
  if ( is_bib($record) ) {
    return 'BIB';
  }
  if ( is_mfhd($record) ) {
    return 'MFHD';
  }
  if ( is_auth($record) ) {
    return 'AUTH';
  }
  return '???';
}
 
sub is_auth($) {
  my $record = $_[0];
  if ( $record =~ /^.{6}z/ ) {
    return 1;
  }
  return 0;
}

sub is_bib($) {
  my $record = $_[0];
  if ( $record =~ /^.{6}[acdefgijkmoprt]/ ) {
    return 1;
  }
  return 0;
}

sub is_holding($) {
  my $record = $_[0];
  if ( $record =~ /^.{6}[uvxy]/ ) {
    return 1;
  }
  return 0;
}

sub is_component_part($) {
  my $record = $_[0];
  if ( $record =~ /^.{7}[abd]/ ) { # 2019-02-26: added 'd'
    return 1;
  }
  return 0;
}

sub is_serial($) {
  my $record = $_[0];
  if ( $record =~ /^.{7}[sb]/ ) {
    return 1;
  }
  if ( $record =~ /^.{7}a/ ) {
      # MELINDA-7427: Translation bug was found, and even 'a' can
      # belong to a serial... However the host should be checked...
      # But do we really want to get into that...
      die();
  }
  return 0;
}
		  

sub is_isbn($) {
  my $issn = shift;
  if ( $issn =~ /^([0-9]\-?){9}[0-9X]$/ ) {
    return 1;
  }
  if ( $issn =~ /^([0-9]\-?){12}[0-9X]$/ ) {
    return 1;
  }
  return 0;
}

sub is_issn($) {
  my $issn = shift;
  if ( $issn =~ /^([0-9]{4}\-[0-9]{3}[0-9X])$/ ) {
    return 1;
  }
  return 0;
}


sub karsi_kentan_perusteella($$$$$$$) {
  my ( $tietueetP, $kentta, $osakentta, $sisalto, $poista_kaikki, $hyva_kentta, $puuttuvaa_ei_poisteta ) = @_;
  my @tietueet = @{$tietueetP};
  if ( $#tietueet < 0 ) { return @tietueet; }

  my $n_tietueet = $#tietueet+1;

  my $prefix = ( $hyva_kentta ? "LACKING " : 'CONTAINING ' );
  print STDERR "OPERATION: REMOVE RECORDS ${prefix}$kentta", ( defined($osakentta) ? "\$$osakentta" : '' ), " '", (defined($sisalto) ? $sisalto : 'undef'), "'\tN=", (1+$#tietueet), "\n";

  my @pois;
  my $n_osuma = 0;
  for ( my $i=$#tietueet; $i >= 0; $i-- ) {
    my $tietue = $tietueet[$i];
    #$pois[$i] = ( marc21_record_has_field($tietue, 'LOW', undef, "  \x1FaFENNI") ? 1 : 0 );
    $pois[$i] = 0;

    my @tietueen_kentat = marc21_record_get_fields($tietue, $kentta, $osakentta);
    my $osumat = 0;
    my $j = 0;
    for ( $j=0; $j <= $#tietueen_kentat; $j++ ) {
      my $tietueen_kentta = $tietueen_kentat[$j];
      if ( !defined($sisalto) ) {
	  $osumat++;
      }
      elsif ( $tietueen_kentta eq $sisalto ) {
	$osumat++;
      }
    }

    if ( $j == 0 && $puuttuvaa_ei_poisteta ) {

    }
    elsif ( ( $osumat && !$hyva_kentta ) ||
	 ( !$osumat && $hyva_kentta ) ) {
      $pois[$i] = 1;
      $n_osuma++;
    }
  }

  if ( $n_osuma ) {
    if ( $n_osuma == $n_tietueet && !$poista_kaikki ) {
      if ( $hyva_kentta ) {
	print STDERR " Every record matches. Remove nothing\n";
      }
      else {
	print STDERR " NO record matches! Remove nothing\n";
      }
    }
    else {
      print STDERR " Remove $n_osuma/$n_tietueet records\n";
      for ( my $i=$#tietueet; $i >= 0; $i-- ) {
	if ( $pois[$i] ) {
	  my $id = marc21_record_get_field($tietueet[$i], '001', undef);
	  print STDERR "  Removing $id\n";
	  splice(@tietueet, $i, 1);
	}
      }
    }
  }

  if ( $#tietueet == -1 ) {
    print STDERR " NB! Poistettiin kaikki!\n";
  }
  if ( $n_tietueet == $#tietueet + 1 ) {
    print STDERR "  Did not apply.\n";
  }
  return @tietueet
}



sub lisaa_kentta($$$) {
  # Miten tää suhtautuu marc21_record_add_field()-funktioon?

  my ( $tietue, $kentta, $arvo ) = @_;
  # print STDERR "LK IN $kentta='$arvo'...\n";
  if ( marc21_record_has_field($tietue, $kentta, '', undef) ) {
    if ( marc21_record_has_field($tietue, $kentta, '', $arvo) ) {
      # on jo, kaikki hyvin
      return $tietue;
    }
    my @fields = marc21_record_get_fields($tietue, $kentta, undef);
    # täällä on jotain paskaa, joka pitää selvittää
    die("Jotain on jo olemassa \@$kentta:\n" . join("\n", @fields));
  }
  $tietue = marc21_record_add_field($tietue, $kentta, $arvo);
  return $tietue;
}



sub append_zeroes_to_melinda_id($) {
  my $melinda_id = shift();

  if ( length($melinda_id) < 9 ) {
    # Append zeroes:
    $melinda_id = ( '0' x ( 9-length($melinda_id) )) . $melinda_id;
  }
  # remove this after testing:
  if ( length($melinda_id) != 9 ) { die("length($melinda_id) != 9"); }

  return $melinda_id;
}



sub lisaa_ulkofennicuus($) {
  my ( $record ) = @_;

  my $nf = "  \x1Faulkofennica";

  unless ( marc21_record_has_field($record, '583', undef, $nf) ) {
    print " Lisätään ulkofennica-merkintä 583 '$nf'\n";
    $record = marc21_record_add_field($record, '583', $nf);
  }

  return $record;
}


sub on_fennica_ja_kaunokirjallisuus($$) {
  my ( $id, $record ) = @_;

  if ( $record !~ /^......[at][^bis]/ ) {
    return 0;
  }

  my $f008 = marc21_record_get_field($record, '008', undef);
  if ( $f008 !~ /^.{33}f/ ) { # entäs arvot 1 ja j
    return 0;
  }

  my @f041a = marc21_record_get_fields($record, '041', 'a');

  if ( $#f041a == -1 ) {
    print STDERR "$id\t041a puuttuu...\n";
    return 0;
  }

  my $hit = 0;
  for ( my $i=0; $i <= $#f041a; $i++ ) {
    my $f041a = $f041a[$i];
    if ( defined($f041a) && $f041a eq 'fin' ) {
      $hit++;
    }
  }

  if ( !$hit ) {
    return 0;
  }

  my $f042a = marc21_record_get_fields($record, '042', 'a');
  if ( !defined($f042a) || $f042a ne 'finb' ) {
    return 0;
  }
  return 1;
}

sub fennican_kaunokirjallisuus($$) {
  my ( $id, $record ) = @_;

  if ( !on_fennica_ja_kaunokirjallisuus($id, $record) ) {
    return $record;
  }

  my $f084 = "  \x1Fa84.2\x1F2ykl";
  $record = marc21_record_add_field($record, '084', $f084);
  return $record;
}

sub lisaa_puuteluetteloon($) {
  my ( $record ) = @_;

  my $nf = "  \x1FaPUUTELUETT.";
  unless ( marc21_record_has_field($record, '583', undef, $nf) ) {
    print " Lisätään puuteluettelomerkintä 583 '$nf'\n";
    $record = marc21_record_add_field($record, '583', $nf);
  }

  $nf = "  \x1FaPuuttuu kansalliskokoelmasta";
  unless ( marc21_record_has_field($record, '594', undef, $nf) ) {
    print " Lisätään puuteluettelomerkintä 594 '$nf'\n";
    $record = marc21_record_add_field($record, '594', $nf);
  }

  return $record;
}

sub lisaa_udk_versio($$$) {
  my ( $id, $record, $fennikeep ) = @_;

  my @f080 = marc21_record_get_fields($record, '080', undef);

  if ( $#f080 > -1 ) {
    my $new_sf2 = '1974/fin/fennica';
    if ( $record =~ /^......(as|is|es|gs|ms|os|ai)/ ) {
      $new_sf2 = '1974/fin/finuc-s';
    }
    for ( my $i=0; $i <= $#f080; $i++ ) {
      my $field = $f080[$i];
      my $sf2 = marc21_field_get_subfield($field, '2');
      # Jos kenttä on olemassa älä tee mitään

      if ( defined($sf2) ) {
	if ( $sf2 ne $new_sf2 ) {
	  print STDERR "$id\t080\tTODO: fix \$2 '$sf2' => '$new_sf2' manually\n";
	}
      }
      else {

	print STDERR "$id\tAdd \$2\n";
	if ( $field =~ s/(\x1F[3-9])/\x1F2${new_sf2}$1/ ) {
	  # Huomaa, että onnistuessaan s/// lisää $2:n	  
	}
	else {
	  $field .= "\x1F2${new_sf2}";
	}
	# FENNI<KEEP>-lisäys tarvittaessa
	if ( $fennikeep ) {
	  if ( $field =~ /\x1F9FENNI<KEEP>/ ) {
	    # do nothing
	  }
	  elsif ( $field !~ /\x1F9/ ) {
	    $field .= "\x1F9FENNI<KEEP>";
	  }
	  else {
	    die("FENNI<KEEP>-lisäys epäonnistui");
	  }
	}
	$record = marc21_record_replace_nth_field($record, '080', $field, $i);
      }
    }
  }
  return $record;
}

sub marc21_record_type($) { # sinnepäin, hyvin karkea
  my $record = $_[0];
  $record =~ /^......(.)(.)/ or die();
  my $type_of_record = $1;
  my $bibliographic_level = $2;
  my $format = $1.$2;
  # Book (BK)
  # Continuing Resources (CR)
  # Computer Files (CF)
  # Maps (MP)
  # Mixed Materials (MX)
  # Music (MU)
  # Visual Materials (VM)
  if ( $format =~ /^[at]/ ) {
    if ( $format =~ /[bis]/ ) { return 'CR'; }
    return 'BK';
  }
  if ( $format =~ /^[cdj]/ ) { return 'MU'; }
  if ( $format =~ /^[ef]/ ) { return 'MP'; }
  if ( $format =~ /^[m]/ ) { return 'CF'; }
  if ( $format =~ /^[p]/ ) { return ' MX'; }
  if ( $format =~ /^[g]/ ) { return 'VM'; }
  if ( $format =~ /^[iko]/ ) { return 'MX'; }
  if ( $format =~ /^[r]/ ) { return 'MX'; } # nähty lautapeli...

  print STDERR marc21_debug_record($record, "UNKNOWN RECORD TYPE");
  die(); # TODO: lisää AU...
  return 'MX'; # whatever

}


sub marc21_record_replace_field_with_field($$$$) {
  my ( $record, $tag, $from_field, $to_field) = @_;

  my @fields = marc21_record_get_fields($record, $tag, undef);
  for ( my $i=0; $i <= $#fields; $i++ ) {
    my $field = $fields[$i];
    if ( $field eq $from_field ) {
      $record = marc21_record_replace_nth_field($record, $tag, $to_field, $i);
      return $record;
    }
  }
  die(); # epic failure?
  return $record;
}



sub marc21_remove_duplicate_fields($$) {
  my ( $record, $tag ) = @_;
  my $id = 0;
  my @fields = marc21_record_get_fields($record, $tag, undef);
  for ( my $i = $#fields; $i > 0; $i-- ) {
    my $f1 = $fields[$i];
    my $poista = 0;
    for ( my $j = 0; !$poista && $j < $i; $j++ ) {
      my $f2 = $fields[$j];
      if ( $f1 eq $f2 ) {
	$poista = 1;
      }
    }
    if ( $poista ) {
      if ( $id == 0 ) {
	$id = marc21_record_get_field($record, '001', undef);
      }
      print STDERR "$id\tPoistettu tupla $tag '", $fields[$i], "' => /dev/null\n";
      $record = marc21_record_remove_nth_field($record, $tag, '', $i);
    }
  }
  return $record;
}


sub get_773d_from_hosts_26X($) {
    my $publisher_field = shift();
    my $h26Xa = marc21_field_get_subfield($publisher_field, 'a');
    my $h26Xb = marc21_field_get_subfield($publisher_field, 'b');
    my $h26Xc = marc21_field_get_subfield($publisher_field, 'c');
    my @d;

    #if ( !defined($h26Xa) ) { $h26Xa = '[Kustannuspaikka tuntematon]'; }
    #if ( !defined($h26Xb) ) { $h26Xb = '[kustantaja tuntematon]'; }
    #if ( !defined($h26Xb) ) { $h26Xb = '[julkaisuvuosi tuntematon]'; }

    if ( defined($h26Xa) ) { $d[$#d+1] = $h26Xa; }
    if ( defined($h26Xb) ) { $d[$#d+1] = $h26Xb; }
    if ( defined($h26Xc) ) { $d[$#d+1] = $h26Xc; }
    if( $#d > -1 ) {
	my $d = join(' ', @d);
      # $d =~ s/\] *℗ ?\d+$/\]/; # siivoa vähän (ei kyl pyydetty)
      # $d =~ s/, *℗ ?\d+$//;; # siivoa vähän (ei kyl pyydetty)
	$d =~ s/\.$//;
	return $d;
    }
    return '';
}

sub get_773d_from_host_record_ref($) {
    my $host_record_ref = shift;
    my $f26X = ${$host_record_ref}->get_publisher_field();
    if ( !defined($f26X) ) { return undef; }
    return get_773d_from_hosts_26X($f26X->{content});
}


sub get_773d_from_host($) {
  my $record = $_[0];

  my $d = '';
  my $publisher_field = marc21_record_get_publisher_field($record);

  if ( defined($publisher_field) ) {
      return get_773d_from_26X($publisher_field);
  }

  return $d;
}


sub get_773h_from_host_300($) {
    my $content = shift();

    my $h = marc21_field_get_subfield($content, 'a');
    if ( !defined($h) ) { return ''; }

    # Uh, we might want to keep /(daisy)/ and other info...
    while ( $h !~ /\(daisy/i && $h =~ s/\([^\(\)]*\)// ) {} # recursive bracker removal "(23 sivua) )"
    $h =~ s/[ ,\.:;\+]*$//;
    if ( $h =~ s/(\S)\s*\([^\)]*\)$/$1/ ) { # loppusulut (kesto) pois.
	$h =~ s/[ ,\.:;\+]*$//;
    }
    $h =~ s/ +(,)/$1/g; 

    if ( $h =~ /^\[?\d+\]? (sivua|numeroimatonta sivua)$/ ) {
	return '';
    }
    
    # Musiikinluettelointiohjeessa oli tommoinen, onkohan kuinka universaali:
    my $e = marc21_field_get_subfield($content, 'e');
    if ( $h && defined($e) ) {
	while ( $e =~ s/\([^\(\)]*\)// ) {} # recursive bracker removal "(23 sivua) )"
	$e =~ s/[ \.:;\+]*$//;
	if ( $e !~ /[\(\)\[\]]/ ) {
	    $h .= " + $e";
	}
	$h =~ s/ +,/,/g;
	$h =~ s/ +/ /g;
	
    }
    print STDERR "H300: '$h'\n";
    return $h;
}

sub get_773h_from_host_record_ref($) {
    my $host_record_ref = shift;
    if ( !${$host_record_ref} ) { return undef; }
    my $h300 = ${$host_record_ref}->get_first_matching_field('300');
    if ( !defined($h300) ) { return undef; }
    return get_773h_from_host_300($h300->{content});
}

sub get_773h_from_host($) {
  my $record = $_[0];

  my $f300 = marc21_record_get_field($record, '300', undef);
  if ( !defined($f300) ) { return ''; }
  my $h = get_773h_from_host_300($f300);
  if ( !defined($h) ) {
      return '';
  }
  return $h;
}

sub get_773k_from_host($) {
  my $record = $_[0];
  my $k = '';

  my $h490 = marc21_record_get_field($record, '490', undef);
  if ( defined($h490) ) {
    my $h490a = marc21_field_get_subfield($h490, 'a');
    my $h490n = marc21_field_get_subfield($h490, 'n');
    my $h490p = marc21_field_get_subfield($h490, 'p');
    my $h490x = marc21_field_get_subfield($h490, 'x');
    my $h490v = marc21_field_get_subfield($h490, 'v');
    my @k;
    if ( defined($h490a) ) { $k[$#k+1] = $h490a; }
    if ( defined($h490n) ) { $k[$#k+1] = $h490n; }
    if ( defined($h490p) ) { $k[$#k+1] = $h490p; }
    if ( defined($h490x) ) { $k[$#k+1] = $h490x; }
    if ( defined($h490v) ) { $k[$#k+1] = $h490v; }
    
    if( $#k > -1 ) {
      $k = join(' ', @k);
      $k =~ s/[ \.:]*$//;
    }
  }
  
  return $k;
}



sub get_773os_from_host($) {
  my $record = $_[0];

  my @ostack;

  if ( is_mu($record) ) {
    my @h024 = marc21_record_get_fields($record, '024', undef);
    for ( my $i=0; $i <= $#h024; $i++ ) {
	my $o = '';
	my $h024 = $h024[$i];
	if ( defined($h024) && $h024 =~ /^2/ ) { # ind1=ISMN
	    my $h024a = marc21_field_get_subfield($h024, 'a');
	    if ( defined($h024a) ) {
		$ostack[$#ostack+1] = $h024a;
	    }
	}
    }

    my @f028 = marc21_record_get_fields($record, '028', undef);
    for ( my $i=0; $i <= $#f028; $i++ ) {
	my $f028 = $f028[$i];
	if ( defined($f028) && $f028 =~ /^0/ ) { # IND1=0 = tuotenumero
	    my $f028a = marc21_field_get_subfield($f028, 'a');
	    my $f028b = marc21_field_get_subfield($f028, 'b');
	    my @o;
	    if ( defined($f028b) ) { $o[$#o+1] = $f028b; } # $b tulee ensin
	    if ( defined($f028a) ) { $o[$#o+1] = $f028a; }
	    if( $#o > -1 ) {
		my $o = join(' ', @o);
		$ostack[$#ostack+1] = $o;
		if ( 0 && $#o == 1 ) { # ota pelkkä $b, miksi?
		    $ostack[$#ostack] = $o[1];
		}
	    }
	}
    }
  }
  elsif ( $record =~ /^......[acdo]/ ) {
    my @h024 = marc21_record_get_fields($record, '024', undef);
    for ( my $i=0; $i <= $#h024; $i++ ) {
      my $o = '';
      my $h024 = $h024[$i];
      if ( defined($h024) ) {
	my $h024a = marc21_field_get_subfield($h024, 'a');
	if ( defined($h024a) ) {
	  $ostack[$#ostack+1] = $h024a;
	}
      }
    }

    my @h028 = marc21_record_get_fields($record, '028', undef);
    for ( my $j=0; $j <= $#h028; $j++ ) {
      my $h028 = $h028[$j];
      if ( defined($h028) && $h028 =~ /^3/ ) {
	#my $h028b = marc21_field_get_subfield($h028, 'b');
	my $h028a = marc21_field_get_subfield($h028, 'a');

	#if ( defined($h028b) ) { $o[$#o+1] = $h028b; }
	if ( defined($h028a) ) {
	  $ostack[$#ostack+1] = $h028a;
	}
      }

    }
  }
  elsif ( $record =~ /^......[g]/ ) { # tarkista
    my @h028 = marc21_record_get_fields($record, '028', undef);
    for ( my $i=0; $i <= $#h028; $i++ ) {
      my $h028 = $h028[$i];
      if ( defined($h028) ) {
	my $h028a = marc21_field_get_subfield($h028, 'a');
	my $h028b = marc21_field_get_subfield($h028, 'b');
	my @o;
	if ( defined($h028b) ) { $o[$#o+1] = $h028b; } # B tulee ensin
	if ( defined($h028a) ) { $o[$#o+1] = $h028a; }
	if( $#o > -1 ) {
	  my $o = join(' ', @o);
	  $ostack[$#ostack+1] = $o;
	  if ( $#o == 1 ) {
	    $ostack[$#ostack] = $o[1];
	  }
	}
      }
    }
  }

  # Trimmaa ja poista tuplat:
  my %keys;
  my @ostack2;
  for ( my $i=0; $i <= $#ostack; $i++ ) {
      $ostack[$i] =~ s/\.$//;
      $ostack[$i] =~ s/\s+$//;
      if ( !defined($keys{$ostack[$i]}) ) {
	  $keys{$ostack[$i]} = 1;
	  $ostack2[$#ostack2+1] = $ostack[$i];
      }
  }

  return @ostack2;
}

sub get_773o_from_host($) {
  my $record = $_[0];
  my $o = '';
  die(); # mieti tämä uusiksi.
  # Jos *oikeasti* halutaan vain yksi arvo, niin
  # Laita käyttämään get_773os_from_host($)-funktion palauttaman taulukon
  # ekaa alkiota. Jos
  
  if ( $record =~ /^......[acdo]/ ) {
    my $h024 = marc21_record_get_field($record, '024', undef);
    if ( defined($h024) ) {
      my $h024a = marc21_field_get_subfield($h024, 'a');
      if ( defined($h024a) ) {
	$o = $h024a;
      }
    }

    my $h028 = marc21_record_get_field($record, '028', undef);
    if ( defined($h028) && $h028 =~ /^3/ ) {
      #my $h028b = marc21_field_get_subfield($h028, 'b');
      my $h028a = marc21_field_get_subfield($h028, 'a');

      #if ( defined($h028b) ) { $o[$#o+1] = $h028b; }
      if ( defined($h028a) ) {
	my @o;
	if ( $o ) {
	  $o[0] = $o;
	}
	$o[$#o+1] = $h028a;
	if( $#o > -1 ) {
	  $o = join(' ', @o);
	}
      }
    }
  }
  elsif ( $record =~ /^......[gj]/ ) {
    my $h028 = marc21_record_get_field($record, '028', undef);
    if ( defined($h028) ) {

      my $h028a = marc21_field_get_subfield($h028, 'a');
      my $h028b = marc21_field_get_subfield($h028, 'b');
      my @o;
      if ( defined($h028b) ) { $o[$#o+1] = $h028b; } # B tulee ensin
      if ( defined($h028a) ) { $o[$#o+1] = $h028a; }
      if( $#o > -1 ) {
	$o = join(' ', @o);
      }
    }
  }

  $o =~ s/\.$//;
  $o =~ s/\s+$//;
  return $o;
}

sub get_773t_from_hosts_245($) {
    my ( $h245 ) = @_;
    my $h245a = marc21_field_get_subfield($h245, 'a');
    if ( !defined($h245a) ) {
	return undef;
    }

    my $h245b = marc21_field_get_subfield($h245, 'b');
    my $h245n = marc21_field_get_subfield($h245, 'n');
    my $h245p = marc21_field_get_subfield($h245, 'p');
    my $h245c = marc21_field_get_subfield($h245, 'c');

    my $t = $h245a;
    if ( defined($h245b) ) {
	$t .= " " . $h245b;
    }
    if ( defined($h245n) ) { $t .= " " . $h245n; }
    if ( defined($h245p) ) { $t .= " " . $h245p; }
    if ( defined($h245c) ) {
	# Don't take 245c:
	if ( $h245c =~ /^(julk|publ)/ ) {
	    $t =~ s/ \///;
	}
	else {
	    $t .= " " . $h245c;
	}
    }
    print STDERR "DERIVED 773\$t: '$t'\n";
    return $t;
}


sub get_773t_from_host_record_ref($) {
    my $host_record_ref = shift;
    my $h245 = ${$host_record_ref}->get_first_matching_field('245');
    if ( !defined($h245) ) { return undef; }
    return get_773t_from_hosts_245($h245->{content});
}


#sub get_773t_from_host($) {
#  my $record = $_[0];
#  my $h245 = marc21_record_get_field($record, '245', undef);
#  if ( !defined($h245) ) {
#      return undef;
#  }
#  if ( 1 ) {
#      my $f001 = marc21_record_get_field($record, '001', undef);
#      die($f001);
#  }
#  return get_773t_from_hosts_245($h245); 
#}


sub get_773z_from_host($) {
  my $record = $_[0];
  my $z = '';

  if ( $record =~ /^......[acdo]/ ) {
    my $h020 = marc21_record_get_field($record, '020', undef);
    if ( defined($h020) ) {
      my $h020a = marc21_field_get_subfield($h020, 'a');
      if ( defined($h020a) ) {
	$z = $h020a;
      }
    }
  }
  return $z;
}

sub get_773x_from_host($) {
  my $record = $_[0];
  my $x = '';

  if ( 1 ) { # $record =~ /^......[acdo]/ ) {
    my $h022 = marc21_record_get_field($record, '022', undef);
    if ( defined($h022) ) {
      my $h022a = marc21_field_get_subfield($h022, 'a');
      if ( defined($h022a) && $h022a =~ /^[0-9]{4}-[0-9]{3}[0-9X]$/ ) {
	$x = $h022a;
      }
    }
  }
  return $x;
}

sub get_7737_from_host($) {
    my $record = shift();
    if ( !is_mu($record) ) { die(); } # not implemented yet, use only for music
    $record =~ /^......([acdgjo])([ms])/ || die();
    my $type = $1;
    my $bibliografinen_taso = $2;
    return "nn$type$bibliografinen_taso";
}


sub create773($$$) {
  my ( $host_id, $host_record, $g ) = @_;

  # LDR/07: mono and serial currently supported...
  if ( $host_record =~ /^......([acdgjo])([ms])/ ) {
    my $type = $1;
    my $bibliografinen_taso = $2;

    my $t = get_773t_from_host($host_record);
    my $d = get_773d_from_host($host_record);
    my $h = get_773h_from_host($host_record); # Onkos tämä vain musiikille?
    my $k = ( is_mu($host_record) ? '' : get_773k_from_host($host_record) );
    my $z = get_773z_from_host($host_record);
    my $x = ''; # get_773x_from_host($host_record);
    my $o = '';
    #die(); # mieti toistettava $o uusiksi...
    my @os = get_773os_from_host($host_record);

	
    # $z???

    my $new773 = "0 " .
	"\x1F7" . "nn${type}${bibliografinen_taso}" .
	"\x1Fw" . $host_id .
	( length($t) ? "\x1Ft" . $t : '' ) . # might not even have this
	( length($d) ? " -\x1Fd" . $d . '.' : '' ) .
	( length($h) ? " -\x1Fh" . $h . "." : '' ) .
	( length($k) ? " -\x1Fk" . $k . "." : '' ) .
	( length($z) ? " -\x1Fz" . $z . "." : '' ) .
	( length($x) ? " -\x1Fx" . $x . "." : '' );
    
    if ( length($o) ) { $new773 .= " -\x1Fo" . $o; }
    elsif ( $#os > -1 ) {
	$new773 .= " -\x1Fo" . join(" -\x1Fo", @os);
    }
    if ( defined($g) ) { $new773 .= " -\x1Fg\u$g"; }
    
    $new773 =~ s/\.$//;
    $new773 =~ s/\s+/ /g;
    return $new773;
  }
  else {
    print STDERR "773 creation: check code/sanity, host=$host_id...\n";
    #die("HOST $host_id LDR/06-07: ".substr($host_record, 6, 2));
  }

  return undef;
}


sub on_videopeli($$) {
  my ( $id, $record) = @_;
  if ( $record =~ /^......m/ ) { # multimedia
    my @f008 = marc21_record_get_fields($record, '008', undef);
    for ( my $i=0; $i <= $#f008; $i++ ) {
      if ( $f008[$i] =~ /^.{26}g/ ) { return 1; }
    }
  }
  return 0;
}


sub on_sarjakuva($$) {
  my ( $id, $record) = @_;
  if ( $record =~ /^......a/ ) { # LDR/06='a'
    my @f008 = marc21_record_get_fields($record, '008', undef);
    for ( my $i=0; $i <= $#f008; $i++ ) {
      #if ( $f008[$i] =~ /^.{24}(6|.6|..6|...6)/ ) { return 1; }
      if ( $f008[$i] =~ /^.{24}(6)/ ) {
	return 1;
      }
    }
  }
  return 0;
}

sub get_sid($$) {
  my ( $record, $sid_sf_b ) = @_;
  my @sids = marc21_record_get_fields($record, 'SID', undef);
  for ( my $i=0; $i <= $#sids; $i++ ) {
    my $content = $sids[$i];
    if ( $content =~ /^  \x1Fc(\d+)\x1Fb(.*)$/ ) {
      my $cand_sid = $1;
      my $cand_b = $2;
      if ( $sid_sf_b eq $cand_b ) {
	return $cand_sid;
      }
    }
  }
  return 0;
}


sub number_of_nonfiling_characters_in_given_language($$) {
    my ( $content, $lang ) = @_;

    ## Language-specific non-filing stuff (articles etc.):
    # This is just a stub. Feel free to add more rules.
    if ( $lang eq "eng" ) {
	if ( $content =~ /\x1FaA / ) { return 2; } # slightly risky
	if ( $content =~ /\x1FaAn / ) { return 3; }
	if ( $content =~ /\x1FaThe / ) { return 4; }
	if ( $content =~ /\x1Fa[\"\'\(]The / ) { return 5; }
    }
    elsif ( $lang eq "fre" ) {
	if ( $content =~ /\x1Fa(l\')[A-Z]/ ||
	     $content =~ /\x1Fa(L\')[A-Za-z]/ ) {
	    return 2;
	}
	if ( $content =~ /\x1Fa(Le) / ) { return 3; }
    }
    elsif ( $lang eq "ger" ) {
	if ( $content =~ /\x1Fa(Der|Die|Das) / ) { return 4; }
    }
    elsif ( $lang eq "swe" ) {
	if ( $content =~ /\x1Fa(En) / ) { return 3; }
	if ( $content =~ /\x1Fa(Ett) / ) { return 4; }
    }
    
    return 0;
}

sub nvolk_lc($) {
    my $word = shift();
    # meidän perlin versio ei välttämättä klaaraa utf-8-merkkejä:
    $word = lc($word);
    $word =~ s/Å/å/g;
    $word =~ s/Ä/ä/g;
    $word =~ s/Ö/ö/g;
    return $word;
}

sub normalize_name($) {
    my $word = shift;
    $word = nvolk_lc($word);
    # meidän perlin versio ei välttämättä klaaraa utf-8-merkkejä:
    $word = "\u$word";
    $word =~ s/(^| |\.)([a-z])/$1\u$2/g;
    $word =~ s/(^| |\.)å/${1}Å/g;
    $word =~ s/(^| |\.)ä/${1}Ä/g;
    $word =~ s/(^| |\.)ö/${1}Ö/g;;
    return $word;
}

sub unique_array {
    my @array = @_;
    my %seen;
    print STDERR "unique array...\n";
    return grep { !$seen{$_}++ } @array;
}

sub unique_array2 {
    my @array = @_;

    my @unique;
    my %seen;

    foreach my $value (@array) {
	if ( !defined($seen{$value}) ) {
	    $seen{$value} = 1;
	    push @unique, $value;
	}
    }
    return @unique;
}


1;

