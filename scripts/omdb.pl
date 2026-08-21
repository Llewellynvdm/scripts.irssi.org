use strict;
use vars qw($VERSION %IRSSI);

use Irssi;
use File::Fetch;
use File::Basename;
use File::Path qw/remove_tree/;
use JSON::PP;
use Storable qw/store_fd fd_retrieve/;
use Text::Wrap;

$VERSION = '0.1';
%IRSSI = (
    authors	=> 'bw1,Eric Jansen',
    contact	=> 'bw1@aol.at',
    name	=> 'omdb',
    description	=> 'Automatically lookup IMDB-numbers in nicknames from omdbapi',
    license	=> 'GPL',
    url		=> 'https://scripts.irssi.org/',
    changed	=> '2026-08-13',
    modules => '',
    commands=> "omdb",
    selfcheckcmd=> 'omdb check',
);

my $help= << "END";
%9Name%9
  /omdb -  $IRSSI{description}

%9Version%9
  $VERSION

%9Description%9
  /set omdb_apikey      set apikey
  /omdb <imdbID>        print title, year, plot, type
  /omdb search <title>  print a list title, year type
  /omdb next            print next list
END

my %bg_process= ();
my ($lastsearch, $lastpage);
my ($lastresult);
my $cache;

sub geturl {
	my ($url) = @_;
	my $rt;
	my $r;
	my $ff = File::Fetch->new(uri => $url);
	my $where = $ff->fetch( to => \$rt );
	if ( $where ne '' && -e $where && $rt ne '' ) {
		my ( $n, $p, $s ) = fileparse($where);
		remove_tree( $p );
	}
	if ( $rt ne '' ) {
		eval {
			$r = decode_json( $rt );
		};
		if ( $@ ne '' ) {
			$r->{_error}="error: ($url) no json";
		}
	} else {
		$r->{_error}="error: ($url) no result";
	}
	$r->{_url}=$url;
	return encode_json( $r );
}


sub background {
	my ($cmd) =@_;
	my ($fh_r, $fh_w);
	pipe $fh_r, $fh_w;
	my $pid = fork();
	if ($pid ==0 ) {
		my @res;
		@res= &{$cmd->{cmd}}(@{$cmd->{args}});
		store_fd \@res, $fh_w;
		close $fh_w;
		POSIX::_exit(1);
	} else {
		$cmd->{fh_r}=$fh_r;
		Irssi::pidwait_add($pid);
		$bg_process{$pid}=$cmd;
	}
}

sub sig_pidwait {
	my ($pid, $status) = @_;
	if (exists $bg_process{$pid}) {
		my @res= @{ fd_retrieve($bg_process{$pid}->{fh_r})};
		$bg_process{$pid}->{res}=[@res];
		if (exists $bg_process{$pid}->{last}) {
			foreach my $p (@{$bg_process{$pid}->{last}}) {
				&$p($bg_process{$pid});
			}
		} else {
			Irssi::print(join(" ",@res), MSGLEVEL_CLIENTCRAP);
		}
		delete $bg_process{$pid};
	}
}


sub draw_box {
    my ($title, $text, $footer, $colour) = @_;
    my $box = '';
    $box .= '%R,--[%n%9%U'.$title.'%U%9%R]%n'."\n";
    foreach (split(/\n/, $text)) {
        $box .= '%R|%n '.$_."\n";
    }
    $box .= '%R`--<%n'.$footer.'%R>->%n';
    $box =~ s/%.//g unless $colour;
    return $box;
}

# {
#	"Response":"True",
#	"imdbID":"tt3896198",
#	"Title":"Guardians of the Galaxy: Vol. 2"
# 	"Plot":"The Guardians struggle to keep together as a team while 
#   	dealing with their personal family issues, notably Star-Lord's encounter 
#   	with his father, the ambitious celestial being Ego.",
#	"Year":"2017",
# 	"Director":"James Gunn",
# 	"Language":"English",
# 	"Country":"United States",
#	"Actors":"Chris Pratt, Zoe Saldaña, Dave Bautista",
#	"Metascore":"67",
#	"Runtime":"136 min",
#	"Rated":"PG-13",
#	"BoxOffice":"$389,813,101",
#	"DVD":"N/A",
#	"imdbVotes":"828,114",
#	"Awards":"Nominated for 1 Oscar. 15 wins & 62 nominations total",
#	"Poster":"https://m.media-amazon.com/images/M/MV5BNWE5MGI3MDctMmU5Ni00YzI2LWEzMTQtZGIyZDA5MzQzNDBhXkEyXkFqcGc@._V1_QL75_UX380_CR0,1,380,562_.jpg",
#	"Ratings":[
#		{"Source":"Internet Movie Database","Value":"7.6/10"},
#		{"Source":"Rotten Tomatoes","Value":"85%"},
#		{"Value":"67/100","Source":"Metacritic"}],
#	"Type":"movie",
#	"Website":"N/A",
#	"Production":"N/A",
#	"Genre":"Action, Adventure, Comedy",
#	"Released":"05 May 2017",
#	"Writer":"James Gunn, Dan Abnett, Andy Lanning",
#	"imdbRating":"7.6",
#	}

sub print_result {
	my ($cmd) = @_;
	if (defined $cmd->{res}->[0]) {
		my $r= decode_json  $cmd->{res}->[0];
		$Text::Wrap::columns =50;
		my $pl= wrap('Plot:  ', '       ', $r->{Plot}); 
		$pl=~s/^Plot:  //;
		my $t=<<"END";
%9Titel:%9 $r->{Title}
%9Year:%9  $r->{Year}
%9Plot:%9  $pl
%9Type:%9  $r->{Type}
END
		Irssi::print(draw_box($IRSSI{name}, $t, $r->{imdbID}, 1)
				, MSGLEVEL_CLIENTCRAP);
	}
}

sub check_result {
	my ($cmd) = @_;
	my $s='ok';
	if (defined $cmd->{res}->[0]) {
		$lastresult = decode_json  $cmd->{res}->[0];
		unless ( $lastresult->{Title} =~ m/The Top 14 Perform/ ) {
			$s="Error: title ($lastresult->{title})";
		}
		unless ($lastresult->{Year} =~ m/2008/ ) {
			$s="Error: year ($lastresult->{year})";
		}
	} else {
		$s="Error: no result";
	}
	Irssi::print("omdb: self check: $s");
	my $schs =  exists $Irssi::Script::{'selfcheckhelperscript::'};
	Irssi::command("selfcheckhelperscript $s") if ( $schs );
}

sub print_searchresult {
	my ($cmd) = @_;
	if (defined $cmd->{res}->[0]) {
		my $r= decode_json  $cmd->{res}->[0];
		my $t;
		my $c=0;
		foreach my $n ( @{$r->{Search}} ) {
			$c++;
			$t.=sprintf("%s\n   %-4s %-6s %-10s\n", 
				$n->{Title},
				$n->{Year},
				$n->{Type},
				$n->{imdbID},
			);
		}
		if ( $c < 10 ) {
			$lastpage=0;
		}
		Irssi::print(draw_box($IRSSI{name}, $t,$c." of ". $r->{totalResults}, 1)
				, MSGLEVEL_CLIENTCRAP);
	}
}

sub cmd {
    my ($args, $server, $witem)=@_;
    if ($args =~ m/^\s*check/) {
		my $cmd;
		$lastresult= {};
		my $url="http://www.omdbapi.com/?i=tt1234567&apikey=".
			Irssi::settings_get_str('omdb_apikey').
			"&page=$lastpage";
		$cmd->{cmd}=\&geturl;
		$cmd->{args}=[$url];
		$cmd->{last}=[
			\&print_result,
			\&check_result,
		];
		background( $cmd );
	} elsif ( $args =~ m/^\s*search (.*)/ ) {
		my $cmd;
		my $arg=$1;
		$arg=~s/\s+/+/g;
		my $url="http://www.omdbapi.com/?s=$arg&apikey=".
			Irssi::settings_get_str('omdb_apikey');
		$cmd->{cmd}=\&geturl;
		$cmd->{args}=[$url];
		$cmd->{last}=[
			\&print_searchresult,
		];
		background( $cmd );
		$lastsearch=$arg;
		$lastpage=1;
	} elsif ( $args =~ m/^\s*next/ ) {
		my $cmd;
		$lastpage++;
		my $url="http://www.omdbapi.com/?s=$lastsearch&apikey=".
			Irssi::settings_get_str('omdb_apikey').
			"&page=$lastpage";
		$cmd->{cmd}=\&geturl;
		$cmd->{args}=[$url];
		$cmd->{last}=[
			\&print_searchresult,
		];
		background( $cmd );
	} else {
		my $cmd;
		#http://www.omdbapi.com/?i=tt3896198&apikey=------
		my $url="http://www.omdbapi.com/?i=$args&apikey=".
			Irssi::settings_get_str('omdb_apikey');
		$cmd->{cmd}=\&geturl;
		$cmd->{args}=[$url];
		$cmd->{last}=[
			\&print_result,
		];
		background( $cmd );
		#$get = undef;
	}
}

sub scmd_help {
	my ($server, $witem, @args) =@_;
	Irssi::print(
		draw_box($IRSSI{name}, $help ,'help' , 1)
				, MSGLEVEL_CLIENTCRAP);
}

sub event_nickchange {
	my ($channel, $nick, $old_nick) = @_;
	my $id;
    # Lookup any 7-digit number in someone elses nick
    if($nick->{'nick'} ne $channel->{'ownnick'}->{'nick'} && $nick->{'nick'} =~ /\D(\d{7})(?:\D|$)/) {
		$id = $1;
		# See if we know the title already
		if(defined $cache->{$id}) {
			# Print it
			$channel->printformat(MSGLEVEL_CRAP, 'omdb_lookup', $old_nick, $cache->{$id}->{Title}, $cache->{$id}->{Year});
		# Otherwise, contact OMDBAPI
		} else {
			if ($channel->{type} eq "CHANNEL" ) {
				my $cmd;
				#http://www.omdbapi.com/?i=tt3896198&apikey=------
				my $url="http://www.omdbapi.com/?i=tt$id&apikey=".
					Irssi::settings_get_str('omdb_apikey');
				$cmd->{cmd}=\&geturl;
				$cmd->{args}=[$url];
				$cmd->{id}= $id;
				$cmd->{channel}= $channel;
				$cmd->{old_nick}= $old_nick;
				$cmd->{last}=[
					\&print_nickchange,
				];
				background( $cmd );
			}
		}
	}
}

sub print_nickchange {
	my ($cmd) = @_;
	if (defined $cmd->{res}->[0]) {
		my $channel= $cmd->{channel};
		my $old_nick= $cmd->{old_nick};
		my $id=$cmd->{id};
		my $r= decode_json  $cmd->{res}->[0];
		# Print it
		$channel->printformat(MSGLEVEL_CRAP, 'omdb_lookup', $old_nick, $r->{Title}, $r->{Year} );
		# And cache it
		$cache->{$id} = $r;
	}
}

Irssi::command_bind('help', sub {
		my @args = grep { $_ ne '' } quotewords('\s+', 0, $_[0]);
		my $s = shift @args;
		if ($s eq $IRSSI{name} ) {
			scmd_help(undef, undef, @args);
			Irssi::signal_stop;
		}
	}
);

Irssi::theme_register([
    'omdb_lookup', '{nick $0} is watching {hilight $1} ($2)'
]);
Irssi::signal_add('pidwait', \&sig_pidwait);
Irssi::signal_add('nicklist changed', 'event_nickchange');
Irssi::settings_add_str($IRSSI{name}, 'omdb_apikey', 'apikey');
Irssi::command_bind($IRSSI{name},\&cmd);
Irssi::command_bind($IRSSI{name}." search",\&cmd);
