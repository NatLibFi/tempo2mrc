use strict;

my $debug = 1;

our $localhost = `hostname`;

our %name2auth_records;   # koottu siistityistä (100|110|700|710)#a-kentistä
our %alt_name2auth_records;   # Field 400
#our %wrong_name2auth_records; # source: FIN11 fields 400/410
our %name2tarke; # Mamba => yhtye (vrt. "Mamba (yhtye)")

our $fin11_read = 0;
our $fin11_file = '/dev/shm/index/asteri/fin11_for_fono.seq';

sub map_name2auth_record($$) {
    my ( $name, $auth_record ) = @_;

    &read_minified_fin11();

    my $i;
    my @stack = ( $name );
    
    my $normalized_name = remove_diacritics($name);
    if ( $normalized_name ne $name ) {
	$stack[$#stack+1] = $normalized_name;
    }

    my $authstr = $auth_record->toString();
    foreach my $n ( @stack ) {
	my $skip = 0;
	for ( $i = 0; $i <= $#{$name2auth_records{$n}}; $i++ ) {
	    if ( $authstr eq $name2auth_records{$n}[$i]->toString() ) {
		$skip = 1;
	    }
	}
	if ( !$skip ) {
	    push(@{$name2auth_records{$name}}, $auth_record);
	}
    }
}

sub map_alt_name2auth_record($$) {
    my ( $name, $auth_record ) = @_;

    &read_minified_fin11();

    my $i;
    my @stack = ( $name );
    
    my $normalized_name = remove_diacritics($name);
    if ( $normalized_name ne $name ) {
	$stack[$#stack+1] = $normalized_name;
    }

    my $authstr = $auth_record->toString();
    foreach my $n ( @stack ) {
	my $skip = 0;
	for ( $i = 0; $i <= $#{$alt_name2auth_records{$n}}; $i++ ) {
	    if ( $authstr eq $alt_name2auth_records{$n}[$i]->toString() ) {
		$skip = 1;
	    }
	}
	if ( !$skip ) {
	    push(@{$alt_name2auth_records{$name}}, $auth_record);
	}
    }
}

sub name2auth_records($) {
    my ( $name ) = @_;

    &read_minified_fin11();

    if ( defined($name2auth_records{$name}) ) {
	return @{$name2auth_records{$name}};
    }
    return ();
}

sub alt_name2auth_records($) {
    my ( $name ) = @_;

    &read_minified_fin11();

    if ( defined($alt_name2auth_records{$name}) ) {
	return @{$alt_name2auth_records{$name}};
    }
    return ();
}


sub read_minified_fin11() {
    if ( $fin11_read ) { return; }
    $fin11_read = 1;
    
    # Read minified FIN11 authority data:
    if ( $localhost =~ /ehistoria-kk/ ) {
	if ( ! -e $fin11_file ) {
	    die();
	}
    }
    else {
	print STDERR "WARNING!\tWrong server! Unable to read FIN11 data.\n";
	return;
    }

    # NB! Melinda runs a script "minify_fin11_for_tempo.perl" via crontab
    # which can create minified version of FIN11 for our purposes

    # [melinda@tietuehistoria-kk 0:130] 0.85 ~
    # $ ~/bin/minify_fin11_for_tempo.perl /dev/shm/index/asteri/fin11.seq > /dev/shm/index/asteri/fin11_for_fono.seq

    my $FH;
    my $file = $fin11_file;
    if ( $debug && -e "./fin11test.seq" ) {
	# $file = "./fin11test.seq";
    }
    if ( ! -e $file ) {
	print STDERR "$file: $!\nCREATE IT FIRST!\n";
	print STDERR "[melinda\@tietuehistoria-kk 0:130] 0.85 ~\n";
	print STDERR "\$ ~/bin/minify_fin11_for_tempo.perl /dev/shm/index/asteri/fin11.seq > /dev/shm/index/asteri/fin11_for_fono.seq\n";
	exit();
    }
    elsif ( open($FH, "<$file") ) {
	my $old_id = '';
	my $record = '';
	my $n = 0;
	while ( my $line = <$FH> ) {
	    $line =~ /^(\d+) (.*)$/;
	    my $curr_id = $1;
	    if ( $curr_id eq $old_id ) {
		$record .= $line;
	    } else {
		if ( $old_id ne '' ) {
		    #print STDERR "OLD $old_id NEW $curr_id END\n";
		    process_fin11_auth_record($record);
		    $n++;
		}
		$record = $line;
		$old_id = $curr_id;
	    }
	}
	close($FH);
	if ( $record) { $n++; process_fin11_auth_record($record); }
	if ( $debug ) {
	    print STDERR "$n auktoriteettitietuetta luettu!\n";
	}
    }
    else {
	print STDERR "ERROR: $file: $!\n";
	die();
    }
}



sub process_fin11_auth_record($) {
    my $sequential = shift;

    my $record = new nvolk_marc_record($sequential);
    my $f001 = $record->get_first_matching_field('001');
    my $record_id = $f001->{content};
    if ( !$record_id ) { die(); }
    
    my $f100 = $record->get_first_matching_field('100');
    my $f110 = $record->get_first_matching_field('110');

    if ( !defined($f100) && !defined($f110) ) { die(); }

    # Don't use 400 data, as the name might change
    my @tags = ( '100' ); # , '400' ); # no relevant 700 data
    foreach my $curr_tag ( @tags ) {
	my @X00 = $record->get_all_matching_fields($curr_tag);
	for ( my $i=0; $i <= $#X00; $i++ ) {
	    my $X00 = $X00[$i];
	    my @names = get_name_variants($X00);
	    foreach my $name ( @names ) {
		&map_name2auth_record($name, $record);
		if ( $debug && $name =~ /(Hammerstein|Hertzen|Leeuwen)/i ) {
		    my $f001 = $record->get_first_matching_field('001');
		    print STDERR "MAP '$name' TO (FIN11)", $f001->{content}, "\n";
		}
	    }
	}
    }

    if ( 1 ) {
	my @X00 = $record->get_all_matching_fields('400');
	for ( my $i=0; $i <= $#X00; $i++ ) {
	    my $X00 = $X00[$i];
	    my @names = get_name_variants($X00);
	    foreach my $name ( @names ) {
		&map_alt_name2auth_record($name, $record);
		if ( $debug && $name =~ /(Hammerstein|Hertzen|Leeuwen)/i ) {
		    my $f001 = $record->get_first_matching_field('001');
		    print STDERR "MAP '$name' TO (FIN11)", $f001->{content}, "\n";
		}
	    }
	}
    }


    if ( defined($f110) ) {
	#NV#      #print STDERR "AUTH-$record_id\t110\t$f110\n";
	#NV#    #die("TODO: pitää tutkia holdareita, ja ottaa vain yhtyeet...");
	my $f110a = $f110->get_first_matching_subfield('a');
	if ( $f110a ) {
	    &map_name2auth_record($f110a, $record);
	    #NV#      $names10{$f110a} = 1;
	    my $tarke = '';
	    # Lisää sulutonkin versio:
	    if ( $f110a =~ s/ \((.*)\)$// ) {
		$tarke = $1;
		&map_name2auth_record($f110a, $record);
	    }

	    if ( !defined($name2tarke{$f110a}) ) {
		if ( $tarke ne '' ) {
		    $name2tarke{$f110a} = $tarke;
		} else {
		    $name2tarke{$f110a} = "__TYHJÄ__";
		}
	    }
	    # Both auth records agree about tarke, so there's no problem:
	    elsif ( $name2tarke{$f110a} eq $tarke ) { }
	    # Both auth records lack tarke, so no problem here either:
	    elsif ( $tarke eq '' && $name2tarke{$f110a} eq '__TYHJÄ__' ) { } 
	    # Tarke mismatch:
	    else {
		print STDERR "Unsupported ambiguous tarke: $f110a: '$tarke' vs '", $name2tarke{$f110a}, "'\n";
		$name2tarke{$f110a} .= "\t$tarke";
	    }
	}
    }
}

sub name2tarke($) {
    my ( $name ) = @_;
    if ( !defined($name2tarke{$name}) ) {
	return undef;
    }
    return $name2tarke{$name};
}

1;
