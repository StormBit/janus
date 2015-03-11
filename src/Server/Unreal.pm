# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Server::Unreal;
use Nick;
use Modes;
use Util::BaseNick;
use Util::ModularNetwork;
use Persist 'Util::BaseNick', 'Util::ModularNetwork';
use strict;
use warnings;

our(@rawout, @sjmerge_head, @sjmerge_txt, @srvname, @servers, @numeric, @protoctl);
Persist::register_vars(qw(rawout sjmerge_head sjmerge_txt srvname servers numeric protoctl));
Persist::autoget(qw(protoctl));

sub _init {
	my $net = shift;
	$rawout[$$net] = '';
	$sjmerge_head[$$net] = '';
	$sjmerge_txt[$$net] = '';
	$protoctl[$$net] = 0;
	$net->module_add('CORE');
	$net->module_add('CUSTOM-'.$net->name, 1);
}

my %cmd2token = (qw/
		PRIVMSG     !
		NICK        &
		SERVER      '
		TOPIC       )
		INVITE      *
		VERSION     +
		SQUIT       -
		KILL        .
		LINKS       0
		STATS       2
		HELP        4
		ERROR       5
		AWAY        6
		CONNECT     7
		PING        8
		PONG        9
		PASS        <
		TIME        >
		ADMIN       @
		SETHOST     AA
		NACHAT      AC
		SETIDENT    AD
		SETNAME     AE
		LAG         AF
		SDESC       AG
		KNOCK       AI
		CREDITS     AJ
		LICENSE     AK
		CHGHOST     AL
		RPING       AM
		RPONG       AN
		NETINFO     AO
		SENDUMODE   AP
		ADDMOTD     AQ
		ADDOMOTD    AR
		SVSMOTD     AS
		SMO         AU
		OPERMOTD    AV
		TSCTL       AW
		SAJOIN      AX
		SAPART      AY
		CHGIDENT    AZ
		NOTICE      B
		SWHOIS      BA
		SVSO        BB
		SVSFLINE    BC
		TKL         BD
		VHOST       BE
		BOTMOTD     BF
		HTM         BH
		DCCDENY     BI
		UNDCCDENY   BJ
		CHGNAME     BK
		SHUN        BL
		CYCLE       BP
		MODULE      BQ
		SVSNLINE    BR
		SVSPART     BT
		SVSLUSERS   BU
		SVSSNO      BV
		SVS2SNO     BW
		SVSJOIN     BX
		SVSSILENCE  Bs
		SVSWATCH    Bw
		JOIN        C
		PART        D
		LUSERS      E
		EOS         ES
		MOTD        F
		MODE        G
		KICK        H
		REHASH      O
		RESTART     P
		CLOSE       Q
		SENDSNO     Ss
		DNS         T
		TEMPSHUN    Tz
		SILENCE     U
		AKILL       V
		UNKLINE     X
		RAKILL      Y
		GLOBOPS     ]
		LOCOPS      ^
		PROTOCTL    _
		TRACE       b
		SQLINE      c
		UNSQLINE    d
		SVSNICK     e
		SVSNOOP     f
		SVSKILL     h
		SVSMODE     n
		SAMODE      o
		CHATOPS     p
		UNZLINE     r
		RULES       t
		MAP         u
		SVS2MODE    v
		DALINFO     w
		ADMINCHAT   x
		UMODE2      |
		SJOIN       ~
/,		INFO =>    '/',
		WHOIS =>   '#',
		QUIT =>    ',',
		WATCH =>   '`',
);

my %token2cmd;
$token2cmd{$cmd2token{$_}} = $_ for keys %cmd2token;

my $textip_table = join '', 'A'..'Z','a'..'z', 0 .. 9, '+/';

sub nicklen { 30 }

sub lc {
	CORE::lc $_[1] || '';
}

sub request_nick {
	my($net, $nick, $reqnick, $tagged) = @_;
	$tagged = 1 if $reqnick =~ /^ircd?/i;
	$net->SUPER::request_nick($nick, $reqnick, $tagged);
}


sub str {
	my $net = shift;
	$net->jname();
}

sub intro {
	my($net, $param, $addr) = @_;
	$net->SUPER::intro($param, $addr);
	if ($net->auth_should_send) {
		my $name = $net->cparam('linkname');
		my $num = $net->numeric_for($net);
		$net->send(
			'PASS :'.$net->cparam('sendpass'),
			'PROTOCTL NOQUIT TOKEN NICKv2 CLK NICKIP SJOIN SJOIN2 SJ3 VL NS UMODE2 TKLEXT SJB64',
			"SERVER $name 1 :U2309-hX6eE-$num Janus Network Link",
		);
	}
}

# parse one line of input
sub parse {
	my ($net, $line) = @_;
	return () unless $line;
	my ($txt, $msg) = split /\s+:/, $line, 2;
	my @args = split /\s+/, $txt;
	push @args, $msg if defined $msg;
	if ($args[0] =~ /^@(\S+)$/) {
		$args[0] = $net->srvname($1);
	} elsif ($args[0] !~ s/^://) {
		unshift @args, undef;
	}
	my $cmd = $args[1];
	$cmd = $args[1] = $token2cmd{$cmd} if exists $token2cmd{$cmd};
	Log::netin(@_) unless $cmd eq 'PRIVMSG' || $cmd eq 'NOTICE';
	unless ($net->auth_ok || $cmd eq 'PASS' || $cmd eq 'SERVER' || $cmd eq 'PROTOCTL' || $cmd eq 'ERROR') {
		return () if $cmd eq 'NOTICE'; # NOTICE AUTH ... annoying
		$net->send('ERROR :Not authorized');
		return +{
			type => 'NETSPLIT',
			net => $net,
			msg => 'Sent command '.$cmd.' without authenticating',
		};
	}
	return $net->nick_msg(@args) if $cmd =~ /^\d+$/;
	return $net->from_irc(@args);
}

sub send {
	my $net = shift;
	for my $act (@_) {
		if (ref $act) {
			my $type = $act->{type};
			my @lines = $net->to_irc($act);
			if (@lines) {
				$net->merge_join();
				$rawout[$$net] .= join "\r\n", @lines, '';
			}
		} else {
			$net->merge_join();
			$rawout[$$net] .= $act . "\r\n";
		}
	}
}

sub rawsend {
	my $net = shift;
	$rawout[$$net] .= join "\r\n", @_, '';
}

sub merge_join {
	my($net, $head, $txt) = @_;
	$head ||= '';
	my $chead = $sjmerge_head[$$net];
	if ($chead && $chead ne $head) {
		local $_ = $sjmerge_txt[$$net];
		s/^ //;
		while (s/^(.{400,465}) //) {
			$rawout[$$net] .= $net->cmd1(SJOIN => $chead, $1) . "\r\n";
		}
		$rawout[$$net] .= $net->cmd1(SJOIN => $chead, $_) . "\r\n";
		$sjmerge_txt[$$net] = '';
	}
	$sjmerge_head[$$net] = $head;
	if ($head) {
		$sjmerge_txt[$$net] .= ' ' . $txt;
	}
}

sub dump_sendq {
	my $net = shift;
	local $_;
	$net->merge_join();
	my $q = $rawout[$$net];
	$rawout[$$net] = '';
	for (split /[\r\n]+/, $q) {
		next if /^:\S+ (B|!) /;
		Log::netout($net, $_);
	}
	$q;
}

sub umode_text {
	my($net,$nick) = @_;
	my $mode = '+';
	for my $m ($nick->umodes()) {
		my $um = $net->txt2umode($m);
		$mode .= $um if defined $um;
	}
	my $visible = $Janus::operlvl;
	$visible = Setting::get(oper_visibility => $net) if Setting::get(oper_visibility => $net) < $visible;
	$visible = 2 if $$nick == 1;
	if ($visible == 0) {
		# no remote oper
		$mode =~ s/[oaANSH]//g;
	} elsif ($visible == 1) {
		# hidden
		$mode .= 'H' if $mode =~ /o/ && $mode !~ /H/;
	} else {
		# fully visible
	}
	$mode . 'xt';
}

sub _connect_ifo {
	my ($net, $nick, $althost) = @_;

	my $mode = $net->umode_text($nick);
	my $rhost = $nick->info('host');
	my $vhost = $nick->info('vhost');
	my $ip = $nick->info('ip') || '*';
	if ($net->param('untrusted')) {
		$vhost = $rhost if $vhost eq '*';
		$rhost = $vhost;
		$ip = '*';
	}
	if ($althost) {
		$rhost = $nick->homenet->name . '/' . $rhost;
		$ip = '*';
	}

	my($hc, $srv) = (2,$nick->homenet()->jname());
	$hc = 3 if $nick->jlink();
	($hc, $srv) = (1, $net->cparam('linkname')) if $srv eq 'janus'.$Janus::laddy;

	if ($net->protoctl >= 2305) {
		if ($ip =~ /^[0-9.]+$/) {
			$ip =~ s/(\d+)\.?/sprintf '%08b', $1/eg; #convert to binary
			$ip .= '0000=='; # base64 uses up 36 bits, so add 4 from the 32...
			$ip =~ s/([01]{6})/substr $textip_table, oct("0b$1"), 1/eg;
		} elsif ($ip =~ /^[0-9a-f:]+$/) {
			$ip .= ':';
			$ip =~ s/::/:::/ while $ip =~ /::/ && $ip !~ /(.*:){8}/;
			# fully expanded IPv6 address, with an additional : at the end
			$ip =~ s/([0-9a-f]*):/sprintf '%016b', hex $1/eg;
			$ip .= '0000==';
			$ip =~ s/([01]{6})/substr $textip_table, oct("0b$1"), 1/eg;
		} else {
			warn "Unrecognized IP address '$ip'" unless $ip eq '*';
			$ip = '*';
		}
		unless ($ip eq '*' || length $ip == 8 || length $ip == 24) {
			warn "Dropping NICKIP to avoid crashing unreal!";
			$ip = '*';
		}
	}
	my @out;
	push @out, $net->cmd1(NICK => $nick, $hc, $net->sjb64($nick->ts($net)), $nick->info('ident'), $rhost,
		$srv, 0, $mode, $vhost, $ip, $nick->info('name'));
	my $whois = $nick->info('swhois');
	push @out, $net->cmd1(SWHOIS => $nick, $whois) if defined $whois && $whois ne '';
	my $away = $nick->info('away');
	push @out, $net->cmd2($nick, AWAY => $away) if defined $away && $away ne '';
	$net->rawsend(@out);
}

# IRC Parser
# Arguments:
#	$_[0] = Network
#	$_[1] = source (not including leading ':') or 'undef'
#	$_[2] = command (for multipurpose subs)
#	3 ... = arguments to the irc line; last element has the leading ':' stripped
# Return:
#  list of hashrefs containing the Action(s) represented (can be empty)

sub nickact {
	#(SET|CHG)(HOST|IDENT|NAME)
	my $net = shift;
	my($type, $act) = (CORE::lc($_[1]) =~ /(SET|CHG)(HOST|IDENT|NAME)/i);
	$act =~ s/host/vhost/i;

	my($src,$dst);
	if ($type eq 'set') {
		$src = $dst = $net->mynick($_[0]);
	} else {
		$src = $net->item($_[0]);
		$dst = $net->nick($_[2]);
	}

	return () unless $dst;

	if ($dst->homenet() eq $net) {
		return {
			type => 'NICKINFO',
			src => $src,
			dst => $dst,
			item => CORE::lc $act,
			value => $_[-1],
		};
	} else {
		my $old = $dst->info($act);
		$act =~ s/vhost/host/;
		$net->send($net->cmd2($dst, 'SET'.uc($act), $old));
		return ();
	}
}

sub ignore { (); }
sub todo { (); }

sub nick_msg {
	my $net = shift;
	my $src = $net->item($_[0]);
	my $msg = [ @_[3..$#_] ];
	my $about = $net->item($_[3]);
	if (ref $about && $about->isa('Nick')) {
		$msg->[0] = $about;
	}
	if ($_[2] =~ /\./) {
		# Why do we care about numerics we don't use?
		# Log::warn_in($net, 'numeric', @_);
		return ();
	}
	my $dst = $net->nick($_[2]) or return ();
	return {
		type => 'MSG',
		src => $src,
		dst => $dst,
		msg => $msg,
		msgtype => $_[1],
	};
}

sub nc_msg {
	my $net = shift;
	return () if $_[2] eq 'AUTH' && $_[0] =~ /\./;
	my $src = $net->item($_[0]) or return ();
	my $msgtype = $_[1];
	my $out = $_[3];

	my $ccode = $Janus::cclvl;
	if ($ccode == 2) {
		$out =~ s/\x03[0-9]{1,2}(,[0-9]{1,2})?//g;
		$out =~ s/[\x02\x1f\x16\x0f]//g;
	} elsif ($ccode == 1) {
		$out =~ s/\x03[0-9]{1,2}(,[0-9]{1,2})?//g;
	} else {
		$out = $_[3];
	}
	
	if ($_[2] =~ /^\$/) {
		# server broadcast message. No action; these are confined to source net
		return ();
	} elsif ($_[2] =~ /([~&@%+]?)(#\S*)/) {
		# channel message, possibly to a mode prefix
		return {
			type => 'MSG',
			src => $src,
			prefix => $1,
			dst => $net->chan($2),
			msg => $out,
			msgtype => $msgtype,
		};
	} elsif ($_[2] =~ /^(\S+?)(@\S+)?$/) {
		# nick message, possibly with a server mask
		# server mask is ignored as the server is going to be wrong anyway
		my $dst = $net->nick($1);
		return () unless $dst;
		return {
			type => 'MSG',
			src => $src,
			dst => $dst,
			msg => $_[3],
			msgtype => $msgtype,
		};
	}
	();
}

my %opermodes = (
	oper => 1,
	coadmin => 2,
	admin => 4,
	service => 8,
	svs_admin => 16,
	netadmin => 32,
);

my @opertypes = (
	'IRC Operator', 'Server Co-Admin', 'Server Administrator',
	'Service', 'Services Administrator', 'Network Administrator',
);

sub operlevel {
	my($net, $nick) = @_;
	my $lvl = 0;
	for my $m (keys %opermodes) {
		next unless $nick->has_mode($m);
		$lvl |= $opermodes{$m};
	}
	$lvl;
}

sub _parse_umode {
	my($net, $nick, $mode) = @_;
	my @out;
	my @mode;
	my $pm = '+';
	my $vh_delta = 0; # 0,1,2 = nochange,host,chost
	my $oper_pre = $net->operlevel($nick);
	my $oper_post = $oper_pre;
	for (split //, $mode) {
		if (/[-+]/) {
			$pm = $_;
		} elsif (/d/ && $_[3]) {
			# adjusts the services TS.
			# This event should be sent before the UMODE event
			push @out, +{
				type => 'NICKINFO',
				dst => $nick,
				item => 'svsts',
				value => $_[3],
			};
		} elsif (/[xt]/) {
			if ($pm eq '+' && $_ eq 'x') {
				$vh_delta = 2;
			} elsif ($pm eq '-' && $_ eq 'x') {
				$vh_delta = 1;
			} elsif ($pm eq '-' && $_ eq 't') {
				$vh_delta = 2 unless $vh_delta;
			}
		} else {
			my $txt = $net->umode2txt($_);
			next unless $txt;
			if ($opermodes{$txt}) {
				$oper_post = $pm eq '+' ? $oper_post | $opermodes{$txt} : $oper_post & ~$opermodes{$txt};
			}
			push @mode, $pm.$txt;
		}
	}
	push @out, +{
		type => 'UMODE',
		dst => $nick,
		mode => \@mode,
	} if @mode;

	if ($vh_delta) {
		my $vhost = $nick->info(($vh_delta == 2) ? 'chost' : 'host');
		push @out, {
			type => 'NICKINFO',
			dst => $nick,
			item => 'vhost',
			value => $vhost,
		};
	}

	if ($oper_pre != $oper_post) {
		my $t = undef;
		$oper_post & (1 << $_) ? $t = $opertypes[$_] : 0 for 0..$#opertypes;
		push @out, +{
			type => 'NICKINFO',
			dst => $nick,
			item => 'opertype',
			value => $t,
		};
	}
	@out;
}

my $unreal64_table = join '', 0 .. 9, 'A'..'Z', 'a'..'z', '{}';

sub sjbint {
	my $t = $_[1];
	return $t unless $t =~ s/^!//;
	local $_;
	my $v = 0;
	$v = 64*$v + index $unreal64_table, $_ for split //, $t;
	$v;
}

sub sjb64 {
	my $n = $_[1];
	my $b = '';
	while ($n) {
		$b = substr($unreal64_table, $n & 63, 1) . $b;
		$n = int($n / 64);
	}
	$_[2] ? $b : '!'.$b;
}

sub srvname {
	my($net,$num) = @_;
	return $srvname[$$net]{$num} if exists $srvname[$$net]{$num};
	return $num;
}

sub numeric_for {
	my($net, $for) = @_;
	my $r = $numeric[$$net]{$$for};
	return $r if $r;
	$r = $net->find_numeric();
	$numeric[$$net]{$$for} = $r;
	$srvname[$$net]{$net->sjb64($r, 1)} = $for->jname;
	return $r;
}

sub find_numeric {
	my $net = shift;
	my $range = ($net->param('numeric_range') || '') . ',100-676';
	for (split /,/, $range) {
		if (/(\d+)-(\d+)/) {
			for my $n ($1..$2) {
				my $num = $net->sjb64($n, 1);
				next if $srvname[$$net]{$num};
				return $n;
			}
		} elsif (/\d+/) {
			my $num = $net->sjb64($_, 1);
			next if $srvname[$$net]{$num};
			return $_;
		}
	}
	Log::err_in($net, 'No available numerics');
	return 0;
}

sub _out {
	my($net,$itm) = @_;
	return '' unless defined $itm;
	return $itm unless ref $itm;
	if ($itm->isa('Nick')) {
		return $itm->str($net) if $itm->is_on($net);
		return $itm->homenet()->jname();
	} elsif ($itm->isa('Channel')) {
		return $itm->str($net);
	} elsif ($itm->isa('Network')) {
		return $net->cparam('linkname') if $itm eq $net;
		return $itm->jname();
	} else {
		Log::warn_in($net,"Unknown item $itm");
		$net->cparam('linkname');
	}
}

sub cmd1 {
	my $net = shift;
	$net->cmd2(undef, @_);
}

sub cmd2 {
	my($net,$src,$cmd) = (shift,shift,shift);
	my $out = defined $src ? ':'.$net->_out($src).' ' : '';
	$out .= exists $cmd2token{$cmd} ? $cmd2token{$cmd} : $cmd;
	if (@_) {
		my $end = $net->_out(pop @_);
		$out .= ' '.$net->_out($_) for @_;
		$out .= ' :'.$end;
	}
	$out;
}


our %moddef;
Janus::static('moddef');
$moddef{'CORE-2309'} = {
	umode => { qw/
		p hide_chans
		T deaf_ctcp
	/ },
	cmode => { qw/
		f v_flood3.2
		j s_joinlimit
		I l_invex
		T r_noticeblock
	/ },
};
$moddef{CORE} = {
	umode => { qw/
		o oper
		C coadmin
		A admin
		a svs_admin
		N netadmin
		S service
		H hideoper
		W whois_notice

		B bot
		i invisible
		G badword
		q no_kick
		v dcc_reject
		w wallops
		z ssl

		d deaf_chan
		R deaf_regpriv
	/, map { $_, '' } qw/r s x t g h V/ },
	cmode => { qw/
		v n_voice
		h n_halfop
		o n_op
		a n_admin
		q n_owner

		b l_ban
		c t2_colorblock
		e l_except
		i r_invite
		k v_key
		l s_limit
		m r_moderated
		n r_mustjoin
		p t1_chanhide
		s t2_chanhide
		t r_topic
		u r_auditorium
		z r_sslonly
		C r_ctcpblock
		G r_badword
		K r_noknock
		L v_forward
		M r_regmoderated
		N r_norenick
		O r_oper
		Q r_nokick
		R r_reginvite
		S t1_colorblock
		V r_noinvite
		A r_
		r r_
	/, },
  cmds => {
	NICK => sub {
		my $net = shift;
		my @out;
		if (@_ < 7) {
			my $nick = $net->mynick($_[0]) or return ();
			my $stomp = $net->nick($_[2], 1);
			my $nts = (@_ == 4 ? $net->sjbint($_[3]) : $Janus::time);
			if ($stomp && $stomp != $nick) {
				if ($stomp->ts($net) < $nts) {
					$net->send({
						type => 'QUIT',
						dst => $stomp,
						msg => "Nickname collision ($_[0] -> $_[2])",
					});
					return +{
						type => 'QUIT',
						dst => $nick,
						msg => "Nickname collision ($_[0] -> $_[2])",
					}, {
						type => 'RECONNECT',
						dst => $stomp,
						net => $net,
						killed => 1,
						altnick => 1,
					};
				} else {
					push @out, {
						type => 'RECONNECT',
						dst => $stomp,
						net => $net,
						killed => 1,
						altnick => 1,
					};
				}
			}
			push @out, {
				type => 'NICK',
				src => $nick,
				dst => $nick,
				nick => $_[2],
				nickts => $nts,
			};
			return @out;
		}
		# NICKv2 introduction
		my %nick = (
			net => $net,
			nick => $_[2],
			ts => $net->sjbint($_[4]),
			info => {
				ident => $_[5],
				host => $_[6],
				vhost => $_[6],
				home_server => $net->srvname($_[7]),
				svsts => $net->sjbint($_[8]),
				signonts => $Janus::time,
				name => $_[-1],
			},
		);
		my $vh_mode = 0;
		if (@_ >= 12) {
			my @m = split //, $_[9];
			Log::warn_in($net, "Invalid NICKv2") unless '+' eq shift @m;
			$nick{mode} = {};
			for (@m) {
				$vh_mode++ if /[xt]/;
				my $um = $net->umode2txt($_);
				$nick{mode}{$um}++ if $um;
			}
			$nick{info}{vhost} = $_[10];
		}
		if (@_ >= 13) {
			local $_;
			if (@_ >= 14) {
				$nick{info}{chost} = $_[11];
				$_ = $_[12];
			} else {
				$nick{info}{chost} = $_[6];
				$_ = $_[11];
			}
			if (s/=+//) {
				s/(.)/sprintf '%06b', index $textip_table, $1/eg;
				if (length $_ == 36) { # IPv4
					s/(.{8})/sprintf '%d.', oct "0b$1"/eg;
					s/\.\d*$//;
				} elsif (length $_ == 132) { # IPv6
					s/(.{16})/sprintf '%x:', oct "0b$1"/eg;
					s/:[^:]*$//;
				} else {
					Log::warn_in($net, "Unknown protocol address in use");
				}
			}
			$nick{info}{ip} = $_;
		} else {
			$nick{info}{chost} = $_[6];
		}

		if ($vh_mode == 0) {
			$nick{info}{vhost} = $nick{info}{host};
		} elsif ($vh_mode == 1) {
			$nick{info}{vhost} = $nick{info}{chost};
		}
		my $oplvl = 0;
		for my $m (keys %opermodes) {
			$oplvl |= $opermodes{$m} if $nick{mode}{$m};
		}
		$oplvl & (1 << $_) ? $nick{info}{opertype} = $opertypes[$_] : 0 for 0..$#opertypes;

		my $nick = $net->nick($_[2], 1);
		if ($nick) {
			push @out, +{
				type => 'RECONNECT',
				dst => $nick,
				net => $net,
				killed => 1,
				altnick => 1,
			} if $nick->homenet != $net;
			$net->send($net->cmd2($net, KILL => $_[2], 'Nick collision'));
		} else {
			$nick = Nick->new(%nick);
			$net->request_newnick($nick, $_[2]);
			push @out, +{
				type => 'NEWNICK',
				dst => $nick,
			};
		}
		@out;
	}, QUIT => sub {
		my $net = shift;
		my $nick = $net->mynick($_[0]) or return ();
		# normal boring quit
		return +{
			type => 'QUIT',
			dst => $nick,
			msg => $_[2],
		};
	}, KILL => sub {
		my $net = shift;
		my $src = $net->item($_[0]);
		my $dst = $net->nick($_[2]) or return ();
		my $msg = $_[3];
		$msg =~ s/^\S+!//;

		if ($dst->homenet() eq $net) {
			return {
				type => 'QUIT',
				dst => $dst,
				msg => "Killed ($msg)",
				killer => $src,
			};
		}
		return {
			type => 'KILL',
			src => $src,
			dst => $dst,
			net => $net,
			msg => $msg,
		};
	}, SVSKILL => sub {
		my $net = shift;
		my $nick = $net->nick($_[2]) or return ();
		if ($nick->homenet() eq $net) {
			return {
				type => 'QUIT',
				dst => $nick,
				msg => $_[3],
				killer => $net,
			};
		} else {
			return +{
				type => 'KILL',
				src => $net->item($_[0]),
				dst => $nick,
				net => $net,
				msg => $_[3],
			};
		}
	}, SVSNICK => sub {
		my $net = shift;
		my $nick = $net->nick($_[2]) or return ();
		if ($nick->homenet eq $net) {
			Log::warn_in($net, "Misdirected SVSNICK!");
			return ();
		} elsif ($net->lc($nick->homenick) eq $net->lc($_[2])) {
			return +{
				type => 'RECONNECT',
				src => $net->item($_[0]),
				dst => $nick,
				net => $net,
				killed => 0,
				altnick => 1,
			};
		} else {
			Log::warn_in($net, "Ignoring SVSNICK on already tagged nick\n");
			return ();
		}
	}, UMODE2 => sub {
		my $net = shift;
		my $nick = $net->mynick($_[0]) or return ();
		$net->_parse_umode($nick, @_[2 .. $#_]);
	}, SVSMODE => sub {
		my $net = shift;
		my $nick = $net->nick($_[2]) or return ();
		if ($nick->homenet() eq $net) {
			return $net->_parse_umode($nick, @_[3 .. $#_]);
		} else {
			my $mode = $_[3];
			$mode =~ y/-+/+-/;
			$mode =~ s/d// if $_[4];
			$mode =~ s/[raAN]//g; # List of umode changes NOT rejected by janus
			$mode =~ s/[-+]+([-+]|$)/$1/g; # umode +r-i ==> -+i ==> +i
			$net->send($net->cmd2($nick, 'UMODE2', $mode)) if $mode;
			return ();
		}
	},
	SVS2MODE => 'SVSMODE',
	SETIDENT => \&nickact,
	CHGIDENT => \&nickact,
	SETHOST => \&nickact,
	CHGHOST => \&nickact,
	SETNAME => \&nickact,
	CHGNAME => \&nickact,
	SWHOIS => sub {
		my $net = shift;
		my $nick = $net->nick($_[2]) or return ();
		if ($nick->homenet ne $net) {
			$net->send($net->cmd1(SWHOIS => $nick, ($nick->info('swhois') || '')));
			return ();
		}
		return +{
			src => $net->item($_[0]),
			dst => $nick,
			type => 'NICKINFO',
			item => 'swhois',
			value => $_[3],
		};
	}, AWAY => sub {
		my $net = shift;
		my $nick = $net->mynick($_[0]) or return ();
		return +{
			dst => $nick,
			type => 'NICKINFO',
			item => 'away',
			value => $_[2],
		};
	},
# Channel Actions
	JOIN => sub {
		my $net = shift;
		my $nick = $net->mynick($_[0]) or return ();
		my @act;
		for (split /,/, $_[2]) {
			if ($_ eq '0') {
				# this is SUCH a dumb feature...
				@act = ();
				for my $c ($nick->all_chans()) {
					push @act, +{
						type => 'PART',
						src => $nick,
						dst => $c,
						msg => 'Left all channels',
					};
				}
			} else {
				my $chan = $net->chan($_, 1);
				push @act, +{
					type => 'JOIN',
					src => $nick,
					dst => $chan,
				};
			}
		}
		@act;
	}, SJOIN => sub {
		my $net = shift;
		my $ts = $net->sjbint($_[2]);
		if ($ts == 0) {
			$ts = 42;
			Log::warn_in($net, 'Broken (zero) timestamp on '.$_[3]);
		}
		my $chan = $net->chan($_[3], $ts);
		my $applied = ($chan->ts() >= $ts);
		my $joins = pop;
		push @_, '+' if @_ < 5;
		my $cmode = $_[4];

		my @acts;

		if ($chan->ts > $ts) {
			push @acts, +{
				type => 'CHANTSSYNC',
				src => $net,
				dst => $chan,
				newts => $ts,
				oldts => $chan->ts(),
			};
			if ($chan->homenet == $net) {
				my($modes,$args,$dirs) = Modes::delta($chan, undef, $net);
				# this is a TS wipe, justified. Wipe janus's side.
				push @acts, +{
					type => 'MODE',
					src => $net,
					dst => $chan,
					mode => $modes,
					args => $args,
					dirs => $dirs,
				};
			} else {
				my($modes,$args,$dirs) = Modes::delta(undef, $chan, $net, 1);
				# someone else owns the channel. Fix.
				$net->send(map {
					$net->cmd1(MODE => $chan, @$_, 0);
				} Modes::to_multi($net, $modes, $args, $dirs));
			}
		}

		for (split /\s+/, $joins) {
			if (/^([&"'])(.+)/) {
				$cmode .= $1;
				push @_, $2;
			} else {
				/^([*~@%+]*)(.+)/ or warn;
				my $nmode = $1;
				my $nick = $net->mynick($2) or next;
				my %mh = map {
					tr/*~@%+/qaohv/;
					$_ = $net->cmode2txt($_);
					/n_(.*)/ ? ($1 => 1) : ();
				} split //, $nmode;
				push @acts, +{
					type => 'JOIN',
					src => $nick,
					dst => $chan,
					mode => ($applied ? \%mh : undef),
				};
			}
		}
		$cmode =~ tr/&"'/beI/;
		my($modes,$args,$dirs) = Modes::from_irc($net, $chan, $cmode, @_[5 .. $#_]);
		push @acts, +{
			type => 'MODE',
			src => $net,
			dst => $chan,
			mode => $modes,
			args => $args,
			dirs => $dirs,
		} if $applied && @$modes;
		return @acts;
	}, PART => sub {
		my $net = shift;
		my $nick = $net->mynick($_[0]) or return ();
		return {
			type => 'PART',
			src => $nick,
			dst => $net->chan($_[2]),
			msg => @_ ==4 ? $_[3] : '',
		};
	}, KICK => sub {
		my $net = shift;
		my $nick = $net->nick($_[3]) or return ();
		return {
			type => 'KICK',
			src => $net->item($_[0]),
			dst => $net->chan($_[2]),
			kickee => $nick,
			msg => $_[4],
		};
	}, MODE => sub {
		my $net = shift;
		my $src = $net->item($_[0]) or return ();
		my $chan = $net->item($_[2]) or return ();
		if ($chan->isa('Nick')) {
			# umode change
			return () unless $chan->homenet() eq $net;
			return $net->_parse_umode($chan, @_[3 .. $#_]);
		}
		my @out;
		if ($src->isa('Network') && $_[-1] =~ /^(\d+)$/) {
			#TS update
			push @out, +{
				type => 'CHANTSSYNC',
				dst => $chan,
				newts => $1,
				oldts => $chan->ts(),
			} if $1 && $1 < $chan->ts();
		}
		my $mode = $_[3];
		my $bounce = $mode =~ s/^&//;
		my($modes,$args,$dirs) = Modes::from_irc($net, $chan, $mode, @_[4 .. $#_]);
		if ($bounce) {
			# mode bounce: assume we are correct, and inform the server
			# that they are mistaken about whatever they think we have wrong.
			# This is not very safe, but there's not much way around it
			($modes, $args, $dirs) = Modes::revert($chan, $modes, $args, $dirs);
			$net->send({
				type => 'MODE',
				dst => $chan,
				mode => $modes,
				args => $args,
				dirs => $dirs,
			}) if @$dirs;
		} else {
			push @out, {
				type => 'MODE',
				src => $src,
				dst => $chan,
				mode => $modes,
				args => $args,
				dirs => $dirs,
			};
		}
		@out;
	}, TOPIC => sub {
		my $net = shift;
		my %act = (
			type => 'TOPIC',
			dst => $net->chan($_[2]),
			topic => $_[-1],
		);
		if (defined $_[0]) {
			my $src = $act{src} = $net->item($_[0]);
			$act{topicset} = $src ? $_[0] : 'unknown';
		}
		$act{topicset} = $_[3] if @_ > 4;
		$act{topicts} = $net->sjbint($_[4]) if @_ > 5;
		$act{in_link} = 1 unless @_ > 4 && $_[0] && $_[3] eq $_[0];
		\%act;
	}, INVITE => sub {
		my $net = shift;
		my $src = $net->mynick($_[0]) or return ();
		my $dst = $net->nick($_[2]) or return ();
		my $chan = $net->chan($_[3]) or return ();
		return {
			type => 'INVITE',
			src => $src,
			dst => $dst,
			to => $chan,
		};
	},
	KNOCK => \&todo,

# Server actions
	__PANGPANG__ => \&ignore,
	SERVER => sub {
		my $net = shift;
		# :src SERVER name hopcount [numeric] description
		my $src = $_[0] ? $net->srvname($_[0]) : $net->cparam('linkname');
		my $name = CORE::lc $_[2];
		my $desc = $_[-1];

		my $snum = 0;
		if (@_ > 5) {
			$snum = $net->sjb64($_[4], 1);
		} elsif ($desc =~ s/^U(\d+)-\S+-(\d+) //) {
			$protoctl[$$net] = $1;
			$snum = $net->sjb64($2, 1);
			$net->module_add('CORE-'.$protoctl[$$net], 1);
		}

		if ($net->auth_should_send) {
			my $server = $net->cparam('linkname');
			my $netname = $net->cparam('netname');
			my $pass = $net->cparam('sendpass');
			my $num = $net->numeric_for($net);
			my $systime = time();
			$rawout[$$net] = "PASS :$pass\r\n".
				'PROTOCTL NOQUIT TOKEN NICKv2 CLK NICKIP SJOIN SJOIN2 SJ3 VL NS UMODE2 TKLEXT SJB64'.
				"\r\nSERVER $server 1 :U2309-hX6eE-$num Janus Network Link\r\n".
				"NETINFO 100 $systime 2309 * 0 0 0 :$netname\r\n".$rawout[$$net];
		}
		Log::info_in($net, "Server $_[2] [\@$snum] added from $src");
		$servers[$$net]{$name} = {
			parent => CORE::lc $src,
			hops => $_[3],
			numeric => $snum,
		};
		$srvname[$$net]{$snum} = $name if $snum;

		$_[0] ? () : ({
			type => 'NETLINK',
			net => $net,
		});
	}, SQUIT => sub {
		my $net = shift;
		my $srv = $net->srvname($_[2]);
		my $splitfrom = $servers[$$net]{CORE::lc $srv}{parent};

		my $rextemp = quotemeta $Janus::laddy;
		if (!$splitfrom && $srv =~ /^(.*)$rextemp/) {
			my $ns = $Janus::nets{$1} or return ();
			$net->send($net->cmd2($net->cparam('linkname'), SERVER => $srv, 2, $net->numeric_for($ns), $ns->netname()));
			my @out;
			for my $nick ($net->all_nicks()) {
				next unless $nick->homenet() eq $ns;
				push @out, +{
					type => 'RECONNECT',
					dst => $nick,
					net => $net,
					killed => 1,
				};
			}
			return @out;
		}

		my %sgone = (CORE::lc $srv => 1);
		my $k = 0;
		while ($k != scalar keys %sgone) {
			# loop to traverse each layer of the map
			$k = scalar keys %sgone;
			for (keys %{$servers[$$net]}) {
				$sgone{$_} = 1 if $sgone{$servers[$$net]{$_}{parent}};
			}
		}
		delete $srvname[$$net]{$servers[$$net]{$_}{numeric}} for keys %sgone;
		delete $servers[$$net]{$_} for keys %sgone;

		my @quits;
		for my $nick ($net->all_nicks()) {
			next unless $nick->homenet() eq $net;
			next unless $sgone{CORE::lc $nick->info('home_server')};
			push @quits, +{
				type => 'QUIT',
				src => $net,
				dst => $nick,
				msg => "$splitfrom $srv",
			}
		}
		Log::info_in($net, 'Lost servers: '.join(' ', sort keys %sgone).' with '.(scalar @quits).' users');
		@quits;
	}, PING => sub {
		my $net = shift;
		my $from = $_[3] || $net->cparam('linkname');
		$net->send($net->cmd1('PONG', $from, $_[2]));
		();
	},
	PONG => \&ignore,
	PASS => sub {
		my $net = shift;
		if ($_[2] eq $net->cparam('recvpass')) {
			$net->auth_recvd;
		} else {
			$net->send('ERROR :Bad password');
		}
		();
	}, NETINFO => sub {
		my $net = shift;
		return +{
			type => 'LINKED',
			net => $net,
		};
	},
	PROTOCTL => \&todo,
	EOS => \&ignore,
	ERROR => sub {
		my $net = shift;
		{
			type => 'NETSPLIT',
			net => $net,
			msg => 'ERROR: '.$_[-1],
		};
	},

# Messages
	PRIVMSG => \&nc_msg,
	NOTICE => \&nc_msg,
	WHOIS => sub {
		my $net = shift;
		my $src = $net->item($_[0]);
		my @out;
		for my $n (split /,/, $_[3]) {
			my $dst = $net->item($n);
			next unless ref $dst && $dst->isa('Nick');
			push @out, +{
				type => 'WHOIS',
				src => $src,
				dst => $dst,
			};
		}
		@out;
	},
	HELP => \&ignore,
	SMO => \&ignore,
	SENDSNO => \&ignore,
	SENDUMODE => \&ignore,
	GLOBOPS => \&ignore,
	WALLOPS => \&ignore,
	NACHAT => \&ignore,
	ADMINCHAT => \&ignore,
	CHATOPS => \&ignore,

	TKL => sub {
		my $net = shift;
		my $iexpr;
		my $act = {
			type => 'XLINE',
			dst => $net,
			ltype => $_[3],
			setter => $_[6],
		};
		if ($_[2] eq '+') {
			$act->{expire} = $_[7];
			$act->{settime} = $_[8];
			$act->{reason} = $_[9];
		} else {
			$act->{expire} = 1;
		}
		if ($_[3] eq 'G') {
			$act->{mask} = $_[4].'@'.$_[5];
		} elsif ($_[3] eq 'Q' || $_[3] eq 'Z') {
			$act->{mask} = $_[5];
		} else {
			# shun is the same syntax as gline
			# spamfilter:
			# BD + F targets action source 0 settimestamp tklduration tklreason :regex
			# BD - F targets action source 0 settimestap :regex
			# we do not currently parse these
			return ();
		}
		$act;
	},
	SVSFLINE => \&ignore,
	TEMPSHUN => \&ignore,

	SAJOIN => \&ignore,
	SAPART => \&ignore,
	SILENCE => \&ignore,
	SMONITOR => \&ignore,
	SVSJOIN => \&ignore,
	SVSLUSERS => \&ignore,
	SVSNOOP => \&ignore,
	SVSO => \&ignore,
	SVSSILENCE => \&ignore,
	SVSPART => \&ignore,
	SVSSNO => \&ignore,
	SVS2SNO => \&ignore,
	SVSWATCH => \&ignore,
	SQLINE => \&ignore,
	UNSQLINE => \&ignore,

	TSCTL => sub {
		my $net = shift;
		my $nick = $net->item($_[0]) or return ();
		return () unless CORE::lc $_[2] eq 'alltime';
		return +{
			type => 'TSREPORT',
			src => $nick,
			sendto => $Janus::global,
		};
	},
	VERSION => \&todo,
	CREDITS => \&todo,
	DALINFO => \&todo,
	LICENSE => \&todo,
	ADMIN => \&todo,
	LINKS => \&todo,
	STATS => \&todo,
	MODULE => \&todo,
	MOTD => \&todo,
	RULES => \&todo,
	LUSERS => \&todo,
	ADDMOTD => \&todo,
	ADDOMOTD => \&todo,
	SVSMOTD => \&todo,
	OPERMOTD => \&todo,
	BOTMOTD => \&todo,
	INFO => \&todo,
	TIME => \&todo,
	LAG => \&todo,
	TRACE => \&todo,
	RPING => \&todo,
	RPONG => \&todo,
	CONNECT => \&todo,
	SDESC => \&todo,
	HTM => \&todo,
	RESTART => \&todo,
	REHASH => sub {
		return +{
			type => 'REHASH',
		};
	},
  }, acts => {
	JNETLINK => sub {
		my($net,$act) = @_;
		my $ij = $act->{net};
		# don't bother with numerics, no users end up on these servers...
		$net->cmd2($net->cparam('linkname'), SERVER => $ij->id().$Janus::laddy, 2, 0, 'Inter-Janus Link');
	}, NETLINK => sub {
		my($net,$act) = @_;
		my $new = $act->{net};
		if ($net eq $new) {
			# first link to the net
			Log::info_in($net, "First link, introducing all servers");
			my @out;
			for my $ij (values %Janus::ijnets) {
				next unless $ij->is_linked();
				push @out, $net->cmd2($net->cparam('linkname'), SERVER => $ij->id().$Janus::laddy, 2, 0, 'Inter-Janus Link');
			}
			for my $id (keys %Janus::nets) {
				$new = $Janus::nets{$id};
				next if $new->isa('Interface') || $new eq $net;
				my $jl = $new->jlink();
				if ($jl) {
					push @out, $net->cmd2($jl->id() . $Janus::laddy, SERVER => $new->jname(), 3,
						$net->numeric_for($new), $new->netname());
				} else {
					push @out, $net->cmd2($net->cparam('linkname'), SERVER => $new->jname(), 2,
						$net->numeric_for($new), $new->netname());
				}
			}
			return @out;
		} else {
			return () if $net->isa('Interface');
			my $jl = $new->jlink();
			if ($jl) {
				$net->cmd2($jl->id() . $Janus::laddy, SERVER => $new->jname(), 3, $net->numeric_for($new), $new->netname());
			} else {
				$net->cmd2($net->cparam('linkname'), SERVER => $new->jname(), 2, $net->numeric_for($new), $new->netname());
			}
		}
	}, LINKED => sub {
		my($net,$act) = @_;
		my $new = $act->{net};
		my $id = $new->name();
		$net->cmd1(SMO => 'o', "(\002link\002) Janus Network $id (".$new->netname().') is now linked');
	}, NETSPLIT => sub {
		my($net,$act) = @_;
		my $gone = $act->{net};
		my $num = delete $numeric[$$net]{$$gone};
		delete $srvname[$$net]{$net->sjb64($num, 1)};
		return () if $act->{netsplit_quit};
		my $id = $gone->name();
		my $msg = $act->{msg} || 'Excessive Core Radiation';
		(
			$net->cmd1(SMO => 'o', "(\002delink\002) Janus Network $id (".$gone->netname().") has delinked: $msg"),
			$net->cmd1(SQUIT => $gone->jname(), $msg),
		);
	}, JNETSPLIT => sub {
		my($net,$act) = @_;
		my $gone = $act->{net};
		my $id = $gone->id();
		my $msg = $act->{msg} || 'Excessive Core Radiation';
		(
			$net->cmd1(SMO => 'o', "(\002delink\002) InterJanus Network $id has delinked: $msg"),
			$net->cmd1(SQUIT => "$id.$Janus::laddy", $msg),
		);
	}, CONNECT => sub {
		my($net,$act) = @_;
		my $nick = $act->{dst};
		$net->_connect_ifo($nick);
		();
	}, RECONNECT => sub {
		my($net,$act) = @_;
		my $nick = $act->{dst};

		if ($act->{killed}) {
			$net->_connect_ifo($nick, $act->{althost});
			my @out;
			for my $chan (@{$act->{reconnect_chans}}) {
				next unless $chan->is_on($net);
				my $mode = '';
				$chan->has_nmode($_, $nick) and $mode .= $net->txt2cmode("n_$_")
					for qw/voice halfop op admin owner/;
				$mode =~ tr/qaohv/*~@%+/;
				push @out, $net->cmd1(SJOIN => $net->sjb64($chan->ts()), $chan, $mode.$nick->str($net));
			}
			return @out;
		} else {
			return $net->cmd2($act->{from}, NICK => $act->{to}, $nick->ts($net));
		}
	}, JOIN => sub {
		my($net,$act) = @_;
		my $chan = $act->{dst};
		if ($act->{src}->homenet eq $net) {
			Log::warn_in($net, 'Trying to force channel join remotely ('.$act->{src}->gid().$chan->str($net).")");
			return ();
		}
		my $sj = '';
		if ($act->{mode}) {
			$sj .= $net->txt2cmode("n_$_") for keys %{$act->{mode}};
		}
		$sj =~ tr/qaohv/*~@%+/;
		return () unless $act->{src}->is_on($net);
		$sj .= $net->_out($act->{src});
		$net->merge_join($net->sjb64($chan->ts()).' '.$chan->str($net), $sj);
		();
	}, PART => sub {
		my($net,$act) = @_;
		$net->cmd2($act->{src}, PART => $act->{dst}, $act->{msg});
	}, KICK => sub {
		my($net,$act) = @_;
		$net->cmd2($act->{src}, KICK => $act->{dst}, $act->{kickee}, $act->{msg});
	}, INVITE => sub {
		my($net,$act) = @_;
		$net->cmd2($act->{src}, INVITE => $act->{dst}, $act->{to});
	}, MODE => sub {
		my($net,$act) = @_;
		my $src = $act->{src};
		my @modes = Modes::to_multi($net, @$act{qw(mode args dirs)}, 12);
		my @out;
		for my $line (@modes) {
			if (ref $src && $src->isa('Nick') && $src->is_on($net)) {
				push @out, $net->cmd2($src, MODE => $act->{dst}, @$line);
			} else {
				push @out, $net->cmd2($src, MODE => $act->{dst}, @$line, 0);
			}
		}
		@out;
	}, CHANTSSYNC => sub {
		my($net,$act) = @_;
		my $chan = $act->{dst};
		return $net->cmd1(MODE => $chan, '+', $act->{newts});
	}, CHANBURST => sub {
		my($net,$act) = @_;
		my $old = $act->{before};
		my $new = $act->{after};
		my @sjmodes = Modes::to_irc($net, Modes::dump($new));
		@sjmodes = '+' unless @sjmodes;
		my @out;
		push @out, $net->cmd1(SJOIN => $net->sjb64($new->ts), $new, @sjmodes, $Interface::janus);
		if ($new->topic && (!$old->topic || $old->topic ne $new->topic)) {
			push @out, $net->cmd1(TOPIC => $new, $new->topicset, $net->sjb64($new->topicts), $new->topic);
		}
		push @out, map {
			$net->cmd1(MODE => $new, @$_, 0);
		} Modes::to_multi($net, Modes::delta($new->ts < $old->ts ? undef : $old, $new));
		@out;
	}, CHANALLSYNC => sub {
		my($net,$act) = @_;
		my $chan = $act->{chan};
		my @sjmodes = Modes::to_irc($net, Modes::dump($chan));
		@sjmodes = '+' unless @sjmodes;
		my $sj = '';
		for my $nick ($chan->all_nicks) {
			my $mode = $chan->get_nmode($nick);
			my $m = join '', map { $net->txt2cmode("n_$_") } keys %$mode;
			$m =~ tr/qaohv/*~@%+/;
			$sj .= ' '.$m.$net->_out($nick);
		}
		$sj =~ s/^ // or return ();
		my @txt = qw/ban except invex/;
		my @sjban = qw/& " '/;
		for my $lm (0..2) {
			my $list = $chan->get_mode($txt[$lm]) or next;
			for my $ban (@$list) {
				$sj .= ' '.$sjban[$lm].$ban;
			}
		}
		my @out = $net->cmd1(SJOIN => $net->sjb64($chan->ts), $chan, @sjmodes, $sj);
		if (defined $chan->topic) {
			push @out, $net->cmd1(TOPIC => $chan, $chan->topicset,
				$net->sjb64($chan->topicts), $chan->topic);
		}
		@out;
	}, TOPIC => sub {
		my($net,$act) = @_;
		$net->cmd2($act->{src}, TOPIC => $act->{dst}, $act->{topicset},
			$net->sjb64($act->{topicts}), $act->{topic});
	}, MSG => sub {
		my($net,$act) = @_;
		return if $act->{dst}->isa('Network');
		my $type = $act->{msgtype} || 'PRIVMSG';
		my $src = $act->{src};
		# only send things we know we should be able to get through to the client
		return () unless $type eq 'PRIVMSG' || $type eq 'NOTICE' || $type =~ /^\d\d\d$/;
		return () if $type eq '378' && $net->param('untrusted');
		my @msg;
		if (ref $act->{msg} eq 'ARRAY') {
			@msg = @{$act->{msg}};
		} elsif ($src->isa('Nick') && !$src->is_on($net)) {
			@msg = '<'.$src->homenick.'> '.$act->{msg};
		} else {
			@msg = $act->{msg};
		}
		my $dst = ($act->{prefix} || '').$net->_out($act->{dst});
		$net->rawsend($net->cmd2($src, $type, $dst, @msg));
		();
	}, WHOIS => sub {
		my($net,$act) = @_;
		my $dst = $act->{dst};
		$net->cmd2($act->{src}, WHOIS => $dst, $dst);
	}, NICK => sub {
		my($net,$act) = @_;
		my $id = $$net;
		$net->cmd2($act->{from}->{$id}, NICK => $act->{to}->{$id}, $act->{dst}->ts($net));
	}, NICKINFO => sub {
		my($net,$act) = @_;
		my $item = $act->{item};
		if ($item =~ /^(vhost|ident|name)$/) {
			$item =~ s/vhost/host/;
			if ($act->{dst}->homenet() eq $net) {
				my $src = $act->{src}->is_on($net) ? $act->{src} : $net->cparam('linkname');
				return $net->cmd2($src, 'CHG'.uc($item), $act->{dst}, $act->{value});
			} else {
				return $net->cmd2($act->{dst}, 'SET'.uc($item), $act->{value});
			}
		} elsif ($item eq 'away') {
			return $net->cmd2($act->{dst}, 'AWAY', defined $act->{value} ? $act->{value} : ());
		} elsif ($item eq 'swhois') {
			return $net->cmd1(SWHOIS => $act->{dst}, $act->{value});
		}
		();
	}, UMODE => sub {
		my($net,$act) = @_;
		local $_;
		my $pm = '';
		my $mode = '';
		my @out;
		my $visible = $Janus::operlvl;
		$visible = Setting::get(oper_visibility => $net) if Setting::get(oper_visibility => $net) < $visible;
		for my $ltxt (@{$act->{mode}}) {
			my($d,$txt) = $ltxt =~ /([-+])(.+)/ or warn $ltxt;
			my $um = $net->txt2umode($txt);
			if (ref $um) {
				$um = $um->($net, $act->{dst}, $ltxt, \@out);
			}
			if (defined $um && length $um) {
				if ($visible == 0) {
					next if $um =~ /[oaANSH]/;
				} elsif ($visible == 1) {
					next if $um eq 'H';
					$um .= 'H' if $um eq 'o';
				}
				$mode .= $d if $pm ne $d;
				$mode .= $um;
				$pm = $d;
			}
		}

		push @out, $net->cmd2($act->{dst}, UMODE2 => $mode) if $mode;
		@out;
	}, QUIT => sub {
		my($net,$act) = @_;
		return () if $act->{netsplit_quit};
		return () unless $act->{dst}->is_on($net);
		$net->cmd2($act->{dst}, QUIT => $act->{msg});
	}, KILL => sub {
		my($net,$act) = @_;
		my $killfrom = $act->{net};
		return () unless $net eq $killfrom;
		return () unless defined $act->{dst}->str($net);
		$net->cmd2($act->{src}, KILL => $act->{dst}, $act->{msg});
	}, PING => sub {
		my($net,$act) = @_;
		$net->cmd1(PING => $net->cparam('linkname'));
	}, TSREPORT => sub {
		my($net,$act) = @_;
		return () unless $act->{src}->is_on($net);
		$net->cmd2($act->{src}, TSCTL => 'alltime');
	},
  }
};

Event::hook_add(
	INFO => 'Network:1' => sub {
		my($dst, $net, $asker) = @_;
		return unless $net->isa(__PACKAGE__);
		Janus::jmsg($dst, 'Modules: '. join ' ', sort $net->all_modules);
		# TODO maybe server list?
	},
	Server => find_module => sub {
		my($net, $name, $d) = @_;
		return unless $net->isa(__PACKAGE__);
		return unless $moddef{$name};
		$$d = $moddef{$name};
	}
);



1;
