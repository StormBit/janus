# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2012 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Interface;
use Network;
use Nick;
use Persist 'Network';
use strict;
use warnings;

=over

=item $Interface::janus - Nick

Nick object representing the janus interface bot.

=cut

our $janus;   # Janus interface bot: this module handles interactions with this bot
our $network;

sub pmsg {
	my $act = shift;
	my $src = $act->{src};
	my $dst = $act->{dst};
	my $type = $act->{msgtype};
	return 1 unless ref $src && ref $dst;

	if ($type eq '312') {
		# server whois reply message
		my $nick = $act->{msg}->[0];
		if ($src->isa('Network') && ref $nick && $nick->isa('Nick')) {
			return undef if $src->jlink();
			Event::append(+{
				type => 'MSG',
				msgtype => 640,
				src => $src,
				dst => $dst,
				msg => [
					$nick,
					'is connected through a Janus link. Home network: '.$src->netname().
					'; Home nick: '.$nick->homenick(),
				],
			});
		} else {
			warn "Incorrect /whois reply: $src $nick";
		}
		return undef;
	} elsif ($type eq '313') {
		# remote oper - change message type
		$act->{msgtype} = 641;
		$act->{msg}->[-1] .= ' (on remote network)';
		return 0;
	}
	return 1 if $type eq '310'; # available for help

	if ($$src == 1 && ref $act->{except}) {
		my $srcj = $act->{except}->id;
		delete $act->{IJ_RAW};
		$act->{msg} = "\@$srcj $act->{msg}" unless $act->{msg} =~ /^@/;
	}

	return undef unless $src->isa('Nick') && $dst->isa('Nick');

	unless ($$src == 1 || $$dst == 1 || $src->is_on($dst->homenet())) {
		#Interface::jmsg($src, 'You must join a shared channel to speak with remote users') if $act->{msgtype} eq 'PRIVMSG';
		return 1;
	}
	undef;
}

Event::hook_add(
	'INIT' => act => sub {
		$network = Interface->new(
			id => 'janus',
			gid => 'janus',
			netname => 'Janus',
		);
		Event::append(+{
			type => 'NETLINK',
			net => $network,
		});

		my $inick = $Conffile::netconf{set}{janus_nick} || 'Janus';

		$janus = Nick->new(
			net => $network,
			gid => 'janus:1',
			nick => $inick,
			ts => ($^T - 1000000000),
			info => {
				ident => ($Conffile::netconf{set}{janus_ident} || 'janus'),
				host => ($Conffile::netconf{set}{janus_rhost} || 'services.janus'),
				vhost => ($Conffile::netconf{set}{janus_host} || 'service'),
				name => ($Conffile::netconf{set}{janus_name} || 'Janus Control Interface'),
				opertype => 'Janus Service',
				signonts => $^T,
				noquit => 1,
			},
			mode => { oper => 1, service => 1, bot => 1 },
		);
		warn if $$janus != 1;
		Event::append(+{
			type => 'NEWNICK',
			dst => $janus,
		});
	}, KILL => check => sub {
		my $act = shift;
		return unless $act->{dst} == $janus;
		my $net = $act->{net};
		$janus->_netpart($net);
		Event::insert_full(+{
			type => 'CONNECT',
			dst => $janus,
			net => $net,
		});
		my @all;
		for my $chan ($janus->all_chans) {
			next unless $chan->is_on($net);
			push @all, +{
				type => 'JOIN',
				dst => $chan,
				src => $janus,
			};
		}
		$net->send(@all);
		return 1;
	}, KICK => 'act:-1' => sub {
		my $act = shift;
		return unless $act->{kickee} eq $janus;
		my $chan = $act->{dst};
		return unless grep { $_ == $janus } $chan->all_nicks;
		Event::append({
			type => 'JOIN',
			dst => $chan,
			src => $janus,
		});
	},
	MSG => parse => \&pmsg,
	INVITE => parse => sub {
		my $act = shift;
		my $src = $act->{src};
		my $dst = $act->{dst};
		my $chan = $act->{to};
		unless ($src->is_on($dst->homenet)) {
			Interface::jmsg($src, 'You cannot /invite a user unless you are on a channel on their network');
			return 1;
		}
		unless ($chan->is_on($dst->homenet)) {
			Interface::jmsg($src, 'You cannot /invite a user to a channel not on their network');
			return 1;
		}
		undef;
	},
	WHOIS => parse => sub {
		my $act = shift;
		my $src = $act->{src};
		my $dst = $act->{dst};
		return undef if $src->is_on($dst->homenet()) || $$dst == 1;
		Interface::jmsg($src, 'You cannot use this /whois syntax unless you are on a shared channel with the user');
		return 1;
	}, NETLINK => act => sub {
		my $act = shift;
		my $net = $act->{net};
		return if $net->jlink();
		return if $janus->is_on($net);
		Event::append(+{
			type => 'CONNECT',
			dst => $janus,
			net => $net,
		});
	},
);

sub parse { () }
sub send {
	my $net = shift;
	for my $act (@_) {
		if ($act->{type} eq 'MSG' && $act->{msgtype} eq 'PRIVMSG') {
			my $src = $act->{src};
			my $dst = $act->{dst};
			next if !$src || !$src->isa('Nick') || $src == $janus;
			$_ = $act->{msg};
			next if /^\001/;
			if ($dst->isa('Channel')) {
				my $hn = $src->homenet;
				next if $hn->jlink || $hn->isa('Server::ClientBot');
				my $jnick = $janus->str($hn);
				my $jcmd = $dst->get_mode('jcommand') || 0;
				next unless s/^\Q$jnick\E[:,] // || ($jcmd >= 2 && /^[.!@]/);
				$dst = $src unless $jcmd;
			} elsif ($dst == $janus) {
				$dst = $src;
			} else {
				next;
			}
			my $rjto = $RemoteJanus::self;
			if (s/^\.//) {
				$rjto = $RemoteJanus::self;
			} elsif (s/^!//) {
				$rjto = $Janus::global;
			} elsif (s/^\@(\S+)\s+//) {
				$rjto = $Janus::ijnets{$1};
				$rjto = $RemoteJanus::self if $1 eq $RemoteJanus::self->id;
				Janus::jmsg($dst, 'Cannot find that network') unless $rjto;
			}
			next unless $rjto;
			my @args = split /\s+/, $_;
			my $cmd = shift @args;
			Event::append({
				type => 'REMOTECALL',
				src => $src,
				dst => $rjto,
				replyto => $dst,
				call => $cmd,
				raw => $_,
				args => \@args,
			}) if $cmd;
		} elsif ($act->{type} eq 'WHOIS' && $act->{dst} == $janus) {
			my $src = $act->{src} or next;
			my $snet = $src->homenet;
			Event::append(whois_reply($src, $janus, 0, $janus->info('signonts'),
				312 => [ 'janus.janus', "Janus Interface" ],
			));
		} elsif ($act->{type} eq 'TSREPORT') {
			my $src = $act->{src} or next;
			Event::append({
				type => 'MSG',
				src => $src->homenet,
				dst => $src,
				msgtype => 'NOTICE',
				msg => 'Time on '.$RemoteJanus::self->id.'.janus is '.gmtime($Janus::time)." ($Janus::time)",
			});
		}
	}
}
sub request_newnick { $_[2] }
sub request_cnick { $_[2] }
sub release_nick { }
sub is_synced { 0 }
sub all_nicks { $janus }
sub all_chans { values %Janus::gchans }
sub lc { $_[1] }
sub type { 'Interface' }
sub chan { $Janus::gchans{$_[1]}; }

sub replace_chan {
	my $new = $_[2];
	Log::debug("Replace channel $_[1]");
	if ($_[2] && 2 > scalar $_[2]->nets) {
		Event::append({
			type => 'PART',
			dst => $new,
			src => $janus,
			msg => 'Unlinked',
		});
	}
	();
}

sub api_parse {
	my($act, $api, @argin) = @_;

	my $fail;  # user's error message
	my $bncto; # automatic ij command bouncing
	my $hnet = $act->{src}->homenet;
	my @args;

	my $idx = 0;
	for (split / /, $api) {
		$idx++;
		my $opt = s/^\?//;
		my $forceloc = s/^local//;
		if (/^=(.*)/) {
			push @args, $act->{$1};
		} elsif ($_ eq '@') {
			push @args, @argin;
			@argin = ();
		} elsif ($_ eq '*') {
			@argin = ();
		} elsif ($_ eq '$') {
			$fail ||= 'Not enough arguments' unless $opt || @argin;
			push @args, (@argin ? shift @argin : undef);
		} elsif ($_ eq '#') {
			my $n = @argin ? $argin[0] : '';
			if ($n =~ /^\d+$/) {
				shift @argin;
			} else {
				$fail ||= @argin ? 'Argument must be an integer' : 'Not enough arguments' unless $opt;
				$n = undef;
			}
			push @args, $n;
		} elsif ($_ eq 'homenet') {
			push @args, $hnet;
		} elsif ($_ eq 'nick') {
			my $nname = $argin[0] || '';
			my $net = $hnet;
			if ($nname =~ /^(\S+):(\S+)$/) {
				$net = $Janus::nets{$1};
				$nname = $2;
				$fail ||= 'Could not find network '.$1 unless $opt || $net;
			}
			if ($nname && $net && !$net->jlink) {
				$act->{$idx} = $net->nick($nname, 1);
			}
			if ($act->{$idx}) {
				shift @argin;
			} else {
				$bncto ||= $net->jlink if $net && $net->jlink;
				$fail = 'Could not find nick "'.$nname.'"' unless $fail || $opt || $bncto == $net->jlink;
			}
			push @args, $act->{$idx};
		} elsif ($_ eq 'chan') {
			my $cname = $argin[0] || '';
			my $net = $hnet;
			if ($cname && $cname =~ /^([^#]+)(#.*)/) {
				$net = $Janus::nets{$1};
				$cname = $2;
				$fail ||= 'Could not find network '.$1 unless $opt || $net;
			}
			if ($cname && $net && !$net->jlink) {
				$act->{$idx} = $net->chan($cname, 0);
			}
			if ($act->{$idx}) {
				shift @argin;
			} else {
				$bncto ||= $net->jlink if $net && $net->jlink;
				$fail = 'Could not find channel "'.$cname.'"' unless $fail || $opt || ($net->jlink && $bncto == $net->jlink);
			}
			push @args, $act->{$idx};
		} elsif ($_ eq 'net') {
			my $id = $argin[0] || '';
			my $net = $Janus::nets{$id};
			$fail ||= 'Could not find network "'.$id.'"' unless $opt || $net;
			shift @argin if $net;
			push @args, $net;
		} elsif ($_ eq 'defnet') {
			my $id = $argin[0] || '';
			my $net = $Janus::nets{$id};
			shift @argin if $net;
			push @args, ($net || $hnet);
		} elsif ($_ eq 'act') {
			push @args, $act;
		} else {
			Log::err("Skipping unknown command API $_");
		}
		if ($forceloc && $args[-1]) {
			my $itm = $args[-1];
			warn "Ambiguous local* API spec" if $bncto;
			if ($itm->isa('Network')) {
				$bncto = $itm->jlink;
			} elsif ($itm->isa('Channel')) {
				$bncto = $itm->homenet->jlink;
			} elsif ($itm->isa('Nick')) {
				$bncto = $itm->homenet->jlink;
			} else {
				warn 'Unknown item';
			}
		}
	}
	$fail ||= 'Too many arguments' if @argin;
	if (wantarray) {
		return (\@args, $fail, $bncto);
	} elsif ($fail) {
		Janus::jmsg($act->{replyto}, $fail);
		return undef;
	} elsif ($bncto) {
		Janus::jmsg($act->{replyto}, 'You must refer to local networks with this command');
		return undef;
	} else {
		return $args[0];
	}
}

=item Interface::jmsg($dst, $msg,...)

Send the given message(s), sourced from the janus interface,
to the given destination

=cut

sub jmsg {
	my $dst = shift;
	return unless $dst && ref $dst;
	my $ntype = $Janus::janus_type;
	my $type =
		$dst->isa('Nick') ? $ntype :
		$dst->isa('Channel') ? 'PRIVMSG' : '';
	return unless $type;
	local $_;
	my @o;
	for (map { split /[\r\n]+/ } @_) {
		push @o, $1 while s/^(.{400,450})\s+/ / or s/^(.{450})/ /;
		push @o, $_;
	}
	Event::insert_full(map +{
		type => 'MSG',
		src => $Interface::janus,
		dst => $dst,
		msgtype => $type,
		msg => $_,
	}, @o);
}

=item Interface::msgtable($dst, $table, arghash)

Table is a list of table items; each table item is a list of strings.
The table is formatted according to arghash, as follows:

  minw - list of minimum widths of each column
  fmtfmt - list of printf formats $ff such that the result of
	sprintf($ff, $w) will be used to format the corresponding
	column; $w is the calculated width. Default is '%%-%ds'.
  isep - separator for columns in an entry
  cols - number of columns of entries, defaults to 1
  pfx - prefix before each row sent to the user
  osep - separator betweenc columns of entries

=cut

sub msgtable {
	my($dst, $table, %a) = @_;
	my @maxw = $a{minw} ? @{$a{minw}} : map 0, @{$table->[0]};
	my @fmtfmt = $a{fmtfmt} ? @{$a{fmtfmt}} : ();
	for my $line (@$table) {
		for my $i (0..$#$line) {
			my $len = length $line->[$i];
			$maxw[$i] = $len if $maxw[$i] < $len;
		}
	}
	# Regex required because the length of a tainted string is tainted
	my $fmt = join(($a{isep} || ' '), map {
		my $ff = $fmtfmt[$_] || '%%-%ds';
		$maxw[$_] =~ /(\d+)/;
		sprintf $ff, $1;
	} 0..$#maxw);

	my $cols = $a{cols} || 1;
	my $c = 1 + $#$table / $cols; # height of table
	my $pfx = $a{pfx} || '';
	for my $i (0..($c-1)) {
		jmsg($dst, $pfx . join( ($a{osep} || ' '), map $_ ? sprintf $fmt, @$_ : '',
			map $table->[$c*$_ + $i], 0 .. ($cols-1)));
	}
}

sub whois_reply {
	my($dst, $src, $idle, $sgon, %args) = @_;
	my $net = $src == $janus ? $dst->homenet : $src->homenet;
	my %msgh = (
		311 => [ $src->info('ident'), $src->info('vhost'), '*', $src->info('name') ],
		312 => [ ($src->info('home_server') || $net->jname), 'Janus link' ],
		319 => [ join ' ', map { $_->is_on($net) ? $_->str($net) : () } $dst->all_chans() ],
		317 => [ $idle, $sgon, 'seconds idle, signon time'],
		318 => [ 'End of /WHOIS list' ],
	);
	$msgh{313} = [ 'is a '.($src->info('opertype') || 'Unknown Oper') ] if $src->has_mode('oper');
	my @msglist = (311,312);
	for my $add (sort { $a <=> $b } keys %args) {
		push @msglist, $add unless $msgh{$add};
		$msgh{$add} = $args{$add};
	}
	push @msglist, 319, 317, 318;

	return map +{
		type => 'MSG',
		src => $net,
		dst => $dst,
		msgtype => $_, # first part of message
		msg => [$src, @{$msgh{$_}} ], # source nick, rest of message array
	}, @msglist;
}

1;
