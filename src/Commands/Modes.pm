# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Commands::Modes;
use strict;
use warnings;
use integer;
use Modes;

Event::command_add({
	cmd => 'showmode',
	help => 'Shows the current intended modes of a channel',
	section => 'Channel',
	syntax => '<channel>',
	api => '=src =replyto chan defnet',
	code => sub {
		my($src,$dst,$chan,$net) = @_;
		return Janus::jmsg($dst, 'That channel does not exist') unless $chan;
		return unless Account::chan_access_chk($src, $chan, 'info', $dst);
		if ($net->isa('LocalNetwork')) {
			my @modes = Modes::to_multi($net, Modes::delta(undef, $chan), 0, 400);
			Janus::jmsg($dst, join ' ', @$_) for @modes;
		}

		my $modeh = $chan->all_modes();
		unless ($modeh && scalar %$modeh) {
			Janus::jmsg($dst, "No modes set");
			return;
		}
		my $out = 'Modes:';
		for my $mk (sort keys %$modeh) {
			my $t = Modes::mtype($mk);
			my $mv = $modeh->{$mk};
			if ($t eq 'r') {
				$out .= ' '.$mk.('+'x($mv - 1));
			} elsif ($t eq 'v') {
				$out .= ' '.$mk.'='.$mv;
			} elsif ($t eq 'l') {
				$out .= join ' ', '', $mk.'={', @$mv, '}';
			} else {
				Log::err("bad mode $mk:$mv - $t?\n");
			}
		}
		Janus::jmsg($dst, $out);
	},
}, {
	cmd => 'setmode',
	help => 'Sets a mode by its long name',
	section => 'Channel',
	syntax => '<channel> <modes...>',
	details => [
		"Modes: +modetoset -modeunset +mode=value +mode=nick ++multistate",
		"For a list of modes, see the \002LISTMODES\002 command.",
		"For multistate modes, use multiple + signs to set a higher level",
	],
	api => '=src =replyto homenet chan @',
	code => sub {
		my($src,$dst,$hn,$chan,@argin) = @_;
		return unless Account::chan_access_chk($src, $chan, 'mode', $dst);
		my(@modes,@args,@dirs);
		for (@argin) {
			/^([-+]+)([^=]+)(?:=(.+))?$/ or do {
				Janus::jmsg($dst, "Invalid mode $_");
				return;
			};
			my($d,$txt,$v) = ($1,$2,$3);
			my $type = Modes::mtype($txt) or do {
				Janus::jmsg($dst, "Unknown mode $txt");
				return;
			};
			if ($type eq 'r') {
				if ($d =~ /-+/) {
					$v = $chan->get_mode($txt);
					$d = '-';
				} else {
					$v = length $d;
					$d = '+';
				}
			} elsif ($type eq 'n') {
				$v = $hn->nick($v, 1) or do {
					Janus::jmsg($dst, "Cannot find nick '$v'");
					return;
				};
			}
			if ($type eq 'v' && $d eq '-') {
				$v = $chan->get_mode($txt);
			}
			if (length $d > 1 || !defined $v) {
				Janus::jmsg($dst, "Invalid mode $_");
				return;
			}
			unshift @dirs, $d;
			unshift @modes, $txt;
			unshift @args, $v;
		}
		if (@dirs) {
			Event::append(+{
				type => 'MODE',
				src => $Interface::janus,
				dst => $chan,
				mode => \@modes,
				args => \@args,
				dirs => \@dirs,
			});
			Janus::jmsg($dst, 'Done');
		} else {
			Janus::jmsg($dst, 'Nothing to do');
		}
	},
}, {
	cmd => 'listmodes',
	help => 'Shows a list of the long modes\' names',
	syntax => '[<network>] [<width>]',
	section => 'Info',
	api => '=replyto localdefnet ?#',
	code => sub {
		my($dst,$net,$w) = @_;
		$w ||= 5;
		my @nmodes = sort keys %Nick::umodebit;
		my @cmodes = sort keys %Modes::mtype;
		my $l = 0;
		$l < length $_ and $l = length $_ for @cmodes, @nmodes;
		Interface::jmsg($dst, 'Nick modes:');
		Interface::msgtable($dst, [
			map {
				my $netv = $net->can('txt2umode') ? $net->txt2umode($_) : '';
				$netv = '' if ref $netv || !defined $netv;
				[ $_, $netv ]
			} @nmodes ], cols => $w, fmtfmt => [ '%%-'.$l.'s', '%%2s' ], pfx => ' ');
		Interface::jmsg($dst, 'Channel modes:');
		Interface::msgtable($dst, [
			map {
				my $m = $_;
				my $type = Modes::mtype($m);
				my $netv = '';
				if ($net->can('txt2cmode')) {
					$netv .= ($net->txt2cmode($_ . '_' . $m) || '') for qw/r t1 t2 v s n l/;
				}
				[ $m, $netv ]
			} @cmodes ], cols => $w, fmtfmt => [ '%%-'.$l.'s', '%%2s' ], pfx => ' ');
	},
});

1;
