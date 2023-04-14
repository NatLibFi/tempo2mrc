#
# Tempo's 'title' related functions
#
use strict;

use tempo_utils;

my $debug = 1;
my $robust = 0;

our $strArticlesForHead = "A|An|Den|Das|Der|Det|El|Ett|La|Le|Les|The";
our $strArticlesForTail = "A|An|Den|Das|Der|Det|Die|El|En|Ett|La|Le|Les|The";

my $iso_kirjain =  "(?:[A-Z]|Á|Å|Ä|Ç|É|Md|Ø|Ó|Õ|Ö|Ø|Š|Ü|Ž)"; # Md. on mm. Bangladeshissä yleinen lyhenne M[ou]hammedille...

sub extract_media_from_title($$) {
    my ( $title_ref, $expected_value ) = @_;
    if ( !defined($title_ref) ) {
	return undef;
    }
    print STDERR ${$title_ref}, "\n";
    if ( ${$title_ref} =~ s/\s*\(([2-9]|[1-9][0-9]+) ?CD\)// ) {
	my $value = $1;
	if ( $expected_value && $value != $expected_value ) {
	    print STDERR "WARNING\t300\$a extent: $value vs $expected_value\n";
	    if ( $value < $expected_value ) { die(); }
	}
	return $value.' CD-äänilevyä';
    }

    if ( ${$title_ref} =~ s/\s*\(([2-9]|[1-9][0-9]+)[^\)]+\)// ) {
	die($1);
    }    
    # if ( $expected_value > 1 ) { return undef; }
    return undef;
}

sub extract_hakuapu($) {
    my $titleP = shift();
    my $orig_title = ${$titleP};
    # (hakuapu: looks like this)
    if ( ${$titleP} =~ s/\(hakuapu:\s*([^\)]+)\)// ) {
	my $hakuapu = $1;
	if ( $debug ) {
	    print STDERR "DEBUG\tExtracted hakuapu '$hakuapu' from title '$orig_title'\n";
	}
	return $hakuapu;
    }
    return undef;
}

sub extract_incipit($) {
    my $titleP = shift();
    my $orig_title = ${$titleP};
    # Example: "(incipit string looks like this -)"
    if ( ${$titleP} =~ s/ \(([^\(\)]+) \-\)\././ || # hacky '.' handling
	 ${$titleP} =~ s/\(([^\(\)]+) \-\)// ) {
	my $incipit = $1;
	
	if ( $debug ) {
	    print STDERR "DEBUG\tExtracted incipit '$incipit' from title '$orig_title'\n";
	}
	return $incipit;
    }
    return undef;
}

sub extract_tassa($) {
    my $titleP = shift();
    my $orig_title = ${$titleP};
    # "/tässä: jotainkin /" tai "/tässä: foo$/

    # 20230410: "(tässä: ...)" should come first as we have:
    # 62bd2b86677ce600345ec0f3.json:"title": "Romansseja (tässä: Drei Romanzen, Kolme romanssia) oboelle /tässä KLARINETILLE/ ja pianolle op.94 /S/.",
    if ( ${$titleP} =~ s/ \(tässä: ([^\(\)]+)\)($|\.| )/$2/ ||
	 ${$titleP} =~ s/\/tässä:? *([^\/]+)($|\/)// ) {
	# Added pm 2022-09-22. Reason 627e1ff64b6d9c01ab9968d3
	
	my $tassa = $1;
	$tassa = trim_ends($tassa);
	${$titleP} =~ s/ \.$//;
	if ( $debug ) {
	    print STDERR "DEBUG\tExtracted tässä '$tassa' from title '$orig_title'\n";
	}
	#${$titleP} =~ s/ +$//;
	return $tassa;
    }
    return undef;
}

sub extract_analytical_title($) {
    my $titleP = shift();
    my $orig_title = ${$titleP};
    # (= uniform title looks like this)
    if ( ${$titleP} =~ s/\(= ([^\(\)]+)\)/ / ||
	 # "(= (I'd go the) whole wide world).":
	 ${$titleP} =~ s/\(= ([^\(\)]+)\)/ / ) {
	my $analytical_title = $1;
	${$titleP} = &trim($$titleP);
	if ( $debug ) {
	    print STDERR "DEBUG\tExtracted uniform title '$analytical_title' from title '$orig_title'\n";
	}
	return $analytical_title;
    }
    return undef;
}

sub process_title_incipit($$) {
    my ( $tempo_titleP, $marc_recordP ) = @_;

    # There shouldn't be multiple incipits, but we have
    # "1. Jumalien keinu (tässä: Jumalten keinu) (Kenen korkeat jumalat keinuunsa ottavat kerta -). - 2. Hymni tulelle (Ken tulta on, se tulta palvelkoon -). - 3. Kanto, sellolle (soolosellolle)"
    # in host 6371f0485a02ae06e6090449.
    my $incipit;
    my $n = 0;
    while ( $incipit = extract_incipit($tempo_titleP) ) {
	add_marc_field($marc_recordP, '031', "  \x1Ft$incipit");
	$n++;
	if ( $n > 1 ) {
	    print STDERR "WARNING\tMultiplie 031\$t incipits!\n";
	}
    }
}

sub normalize_title($) {
    my ( $title ) = @_; 
    if ( $title =~ s/^(.*), ($strArticlesForTail)/$2 \l$1/ ) {
	return $title;
    }
    if ( $title =~ s/^(.*), ($strArticlesForTail) (\()/$2 \l$1 $3/ ) {
	return $title;
    }
    return $title;
}

#sub split_tempo_title($) {
#    my $title = shift;
#    my $subtitle = undef;
#
#    if ( $title =~ /\(.*\)/ ) {
#	if ( $debug ) {
#	    print STDERR "DEBUG\tProcessing title '$title'\n";
#	}
#    
#	$title =~ s/ +(\.?)$/$1/;
#	while ( $title =~ s/^(.*\S)  +(\S.*)$/$1/ ) {
#	    my $cand_subtitle = $2;
#	    if ( defined($subtitle) ) { die(); }
#	    $subtitle = $cand_subtitle;
#	    if (defined($subtitle) ) {
#		print STDERR "DEBUG\tSubtitle: '$subtitle'\n";
#	    }
#
#
#	}
#    }
#
#    if ( !defined($title) ) { die(); }
#    $title =~ s/\s*$//;
#    return ( $title, $subtitle);
#}

sub article_length($$) {
  my ( $name, $languages ) = @_;
  # Ambiguous articles:
  if ( $name =~ /^(Die) / ) {
    # Looks German, not English
    if ( $name =~ / [A-Z][a-z]/ || $name =~ /(ü|sch)/i || $languages =~ /(^|\t)ger(\t|$)/ ) {
      return 4; # "Die "
    }
    return 0;
  }

  if ( $name =~ /^En / ) {
    # Looks Swedish, not Finnish:
    if ( $name =~ /(å|Å)/ || $languages =~ /(^|\t)(dan|nor|swe)($|\t)/ ) {
      # TODO: lisää muita ruotsinkielisyyksiä...
      return 3; # "En "
    }
    return 0;
  }
  # Unproblematic articles:
  if ( $name =~ /^($strArticlesForHead)\s/ ) {
    my $art = $1;
    return length($1)+1;
  }
  return 0;
}


sub get_tempo_title($$) {
    my ( $prefix, $tempo_dataP ) = @_;
    my $title_path = "/$prefix/title";
    my $tempo_title = get_single_entry($title_path, $tempo_dataP);	
    if ( !defined($tempo_title) ) {
	print STDERR "No $title_path found!\n";
	return undef;
    }
    
    return $tempo_title;
}



sub process_title($$$$$$$$) {
    my ( $tempo_title, $tempo_dataP, $marc_recordP, $languagesP, $tempo_record_id, $is_host, $t773_ref) = @_;

    my $subtitle = undef;
    
    # Get subtitle and author information (if any) from host:
    # (I want to do this first, before article movements etc,
    # as this section seems relatively stable.)
    print STDERR "TITLE '$tempo_title'\n";
    my $f245c = undef;
    if ( $is_host ) {
	# 245$b/subtitle for host (type 1):
	if ( $tempo_title =~ /^([^a-z]+) - (.*)$/ ) {
	    my $title_part = $1;
	    my $subtitle_part = $2;
	    if ( $subtitle_part =~ /[a-z]/ ) { # subtitle-ish
		$tempo_title = $title_part;
		$subtitle = $subtitle_part;
	    }
	}
	# TODO: SILENCE (Minimalist piano music from Finland & Sweden)

	# 245$c:
	if ( $tempo_title =~ s/^([^ :a-z]+): ([^a-z]+)$/$2/ ||
	     $tempo_title =~ s/^($iso_kirjain+(?: $iso_kirjain+)+): ([^a-z]+)$/$2/ ) {
	    $f245c = tempo_ucinitial_lcrest($1);
	    $f245c =~ s/\-([a-z])/-\u$1/g; # Saint-saens => Saint-Saens
	}
	elsif ( $tempo_title =~ /[a-z]/ ) {
	    print STDERR "WARNING\tNON-CAP HOST TITLE: '$tempo_title'\n";
	}
	$tempo_title = tempo_ucfirst_lcrest($tempo_title);
    }
    

    
    # Articles. Source of much headache...
    # Simple cases first:
    # NB: "AUTHOR: TITLE, THE" would not work
    $tempo_title = normalize_title($tempo_title);

    # NB! Incipit has already been extracted!

    my $hakuapu = extract_hakuapu(\$tempo_title);
    if ( defined($hakuapu) ) {
	$hakuapu =~ s/([a-z0-9]|å|ä|ö)$/$1./gi;
	add_marc_field($marc_recordP, '500', "  \x1FaHakuapu: ".$hakuapu);
	if ( !$robust ) {
	    # Sanity check: can't have two hakuapus:
	    $hakuapu = extract_hakuapu(\$tempo_title);
	    if ( defined($hakuapu) ) { die(); }
	}
    }

    my $analytical_title = extract_analytical_title(\$tempo_title);
    if ( defined($analytical_title) ) {
	if ( $debug ) {
	    print STDERR "Looking at analytical title '$analytical_title'\n";
	}
	my $tassa = extract_tassa(\$analytical_title);
	if ( defined($tassa) && length($tassa) ) {
	    $tassa =~ s/([a-z0-9]|å|ä|ö)$/$1./gi;
	    add_marc_field($marc_recordP, '500', "  \x1FaHakuapu: ".$tassa);
	}

	add_marc_field($marc_recordP, '740', "02\x1Fa${analytical_title}");

	if ( !$robust ) {
	    # Sanity check: can't have two hakuapus:
	    $analytical_title = extract_analytical_title(\$tempo_title);
	    if ( defined($analytical_title) ) { die(); }
	}
    }

    
    while ( my $tassa = extract_tassa(\$tempo_title) ) {
	if ( $tassa !~ /\.$/ ) { $tassa .= '.'; }
	$tassa =~ s/([a-z0-9]|å|ä|ö)$/$1./gi;
	add_marc_field($marc_recordP, '500', "  \x1FaNimekehuomautus: ".$tassa);
    }
    if ( !$robust ) {
	if ( $tempo_title =~ /(hakuapu|\/tässä)/ ) {
	    die("Title requires further processing: '$tempo_title'");
	}
    }

    my $title = trim_ends($tempo_title);
    
    if ( $title =~ /  / ) { # Is this valid subfield identifier?
	if ( !$robust && $title =~ /  \S.*  / ) { die(); }
	if ( !$robust && $subtitle ) { die(); }
	( $title, $subtitle ) = split(/  +/, $title);
    }
    if ( length($title) == 0 ) { die(); }

    my $languagestr = join("\t", @{$languagesP});
    my $ind2 = &article_length($title, $languagestr);
    my $f245 = "0$ind2\x1Fa$title"; # ind1 is handled in postprocessing...
    if ( defined($subtitle) ) { $f245 .= " :\x1Fb$subtitle"; }
    if ( defined($f245c) ) { $f245 .= " /\x1Fc$f245c"; }
    # TODO? 245$c?
    if ( $f245 !~ /\.$/ ) { $f245 .= "."; }
    
    add_marc_field($marc_recordP, '245', $f245);
    if ( $tempo_record_id ) {
	my $val = $title;
	if ( defined($subtitle) ) { $val .= " : $subtitle"; }
	if ( defined($f245c) ) { $val .= " / $f245c"; }
	${$t773_ref}{$tempo_record_id} = $val;
    }
    
}



1;
