# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Commands::Link;
use strict;
use warnings;

Event::command_add({
	cmd => 'link',
	help => 'Link to a remote network\'s shared channel',
	section => 'Channel',
	syntax => '<channel> <network> [<remote-channel>]',
	details => [
		"The remote network must use the \002CREATE\002 command to",
		"share a channel before links to that channel will be accepted",
	],
	api => '=src =replyto localchan net ?$',
	code => sub {
		my($src,$dst,$chan1,$net2,$cname2) = @_;

		return unless Account::chan_access_chk($src, $chan1, 'link', $dst);

		my $net1 = $chan1->homenet;
		my $cname1 = $chan1->homename;
		$cname2 ||= $cname1;

		if ($Link::request{$net1->name()}{lc $cname1}{mode}) {
			Janus::jmsg($dst, 'This network is the owner for that channel. Other networks must link to it.');
			return;
		}
		if (1 < scalar $chan1->nets()) {
			Janus::jmsg($dst, 'That channel is already linked');
			return;
		}
		$Janus::Burst = 1;
		Event::append(+{
			type => 'LINKREQ',
			src => $src,
			chan => $chan1,
			dst => $net2,
			dlink => lc $cname2,
			reqby => $src->realhostmask,
			reqtime => $Janus::time,
		});
		Janus::jmsg($dst, 'Done');
	}
}, {
	cmd => 'create',
	help => 'Creates a channel that other networks can link to',
	section => 'Channel',
	syntax => '<channel>',
	api => '=src =replyto localchan',
	code => sub {
		my($src,$dst,$chan) = @_;
		my $net = $chan->homenet;

		if (1 < scalar $chan->nets) {
			Janus::jmsg($dst, 'That channel is already linked');
			return;
		}
		return unless Account::chan_access_chk($src, $chan, 'create', $dst);
		my $cname = $chan->lstr($net);
		Log::audit("New channel $cname shared by ".$src->netnick);
		Event::append(+{
			type => 'LINKOFFER',
			src => $net,
			name => $cname,
			reqby => $src->realhostmask(),
			reqtime => $Janus::time,
		});
		Janus::jmsg($dst, 'Done');
	},
}, {
	cmd => 'delink',
	help => 'Delinks a channel',
	section => 'Channel',
	syntax => '<channel> [<network>]',
	details => [
		"The home network must specify a network to delink, or use \002DESTROY\002",
		"Other networks can only delink themselves from the channel",
	],
	api => '=src =replyto chan localdefnet ?$',
	code => sub {
		my($src, $dst, $chan, $net, $cause) = @_;
		return unless Account::chan_access_chk($src, $chan, 'delink', $dst);
		if ($net == $chan->homenet) {
			Janus::jmsg($dst, 'Please specify the network to delink, or use DESTROY');
			return;
		}
		if ($src->homenet == $chan->homenet) {
			$cause = 'reject';
		} elsif ($src->homenet == $net) {
			$cause = 'unlink';
		} else {
			return unless Account::chan_access_chk($src, $chan, 'create', $dst);
			$cause = 'split' unless $cause eq 'reject' || $cause eq 'unlink';
		}

		$Janus::Burst = 1;
		Log::audit('Channel '.$chan->netname.' delinked from '.$net->name.' by '.$src->netnick);
		Event::append(+{
			type => 'DELINK',
			cause => $cause,
			src => $src,
			dst => $chan,
			net => $net,
		});
		Janus::jmsg($dst, 'Done');
	},
}, {
	cmd => 'destroy',
	help => 'Removes a channel that other networks can link to',
	section => 'Channel',
	syntax => '<channel>',
	api => '=src =replyto localchan',
	code => sub {
		my($src,$dst,$chan) = @_;
		my $net = $chan->homenet;
		return unless Account::chan_access_chk($src, $chan, 'create', $dst);
		$Janus::Burst = 1;
		Log::audit('Channel '.$chan->netname.' destroyed by '.$src->netnick);
		Event::append(+{
			type => 'DELINK',
			cause => 'destroy',
			src => $src,
			dst => $chan,
			net => $net,
		}, {
			type => 'LINKOFFER',
			src => $net,
			name => lc $chan->homename,
			remove => 1,
			reqby => $src->realhostmask(),
			reqtime => $Janus::time,
		});
		Janus::jmsg($dst, 'Done');
	},
}, {
	cmd => 'linkacl',
	help => 'Manages access control for shared channels',
	section => 'Channel',
	syntax => '<action> <channel> [...]',
	details => [
		"\002LINKACL LIST\002 #channel               Lists ACL entries for the channel",
		"\002LINKACL ALLOW\002 #channel net          Allows a network access to link",
		"\002LINKACL DENY\002 #channel net           Denies a network access to link",
		"\002LINKACL DEL\002 #channel net            Removes a network's ACL entry",
		"\002LINKACL DEFAULT\002 #channel allow/deny Sets the default access for networks",
	],
	api => '=src =replyto $ localchan ?$',
	code => sub {
		my($src,$dst, $m, $chan, $arg) = @_;
		$m = lc $m;
		my $acl = $m eq 'list' ? 'info' : 'create';
		return unless Account::chan_access_chk($src, $chan, $acl, $dst);
		my $hn = $chan->homenet;
		my $cname = $chan->lstr($hn);
		my $ifo = $Link::request{$hn->name}{$cname};
		unless ($ifo && $ifo->{mode}) {
			Interface::jmsg($dst, 'That channel is not shared');
			return;
		}
		if ($m eq 'list') {
			Interface::jmsg($dst, 'Default: '.($ifo->{mode} == 1 ? 'allow' : 'deny'));
			return unless $ifo->{ack};
			for my $nn (keys %{$ifo->{ack}}) {
				Interface::jmsg($dst, sprintf '%8s %s', $nn,
					($ifo->{ack}{$nn} == 1 ? 'allow' : 'deny'));
			}
		} elsif ($m eq 'allow') {
			return Interface::jmsg($dst, 'Cannot find that network') unless $Janus::nets{$arg};
			$ifo->{ack}{$arg} = 1;
			Interface::jmsg($dst, 'Done');
		} elsif ($m eq 'deny') {
			return Interface::jmsg($dst, 'Cannot find that network') unless $Janus::nets{$arg};
			$ifo->{ack}{$arg} = 2;
			Interface::jmsg($dst, 'Done');
		} elsif ($m eq 'del' && $arg) {
			if (delete $ifo->{ack}{$arg}) {
				Interface::jmsg($dst, 'Deleted');
			} else {
				Interface::jmsg($dst, 'Cannot find that network');
			}
		} elsif ($m eq 'default' && $arg) {
			if ($arg eq 'allow') {
				$ifo->{mode} = 1;
			} elsif ($arg eq 'deny') {
				$ifo->{mode} = 2;
			} else {
				return Interface::jmsg($dst, 'Invalid default ACL');
			}
			Interface::jmsg($dst, 'Done');
		} else {
			Interface::jmsg($dst, 'Invalid command, see help linkacl');
		}
	}
}, {
	cmd => 'accept',
	help => 'Links a channel to a network that has previously requested a link',
	section => 'Channel',
	syntax => '<channel> <network>',
	details => [
		'Links a channel to a network that has previously requested a link.',
		'This command is useful after changing a channel ACL, or if the link',
		'request was made before the destination channel was created.',
	],
	api => 'act =src =replyto =tochan chan net',
	code => sub {
		my($genact, $src, $dst, $tochan, $chan, $dnet) = @_;
		my $snet = $chan->homenet;
		my $dnname = $dnet->name;
		unless ($tochan) {
			return Janus::jmsg($dst, 'Run this command on your own server') if $snet->jlink;

			return unless Account::chan_access_chk($src, $chan, 'create', $dst);
			my %act = %$genact;
			$act{tochan} = $tochan = lc $chan->homename;

			my $difo = $Link::request{$snet->name}{$tochan};
			unless ($difo && $difo->{mode}) {
				Janus::jmsg($dst, 'That channel is not shared');
				return;
			}
			if ($difo->{mode} == 2) {
				$difo->{ack}{$dnname} = 1;
			} else {
				delete $difo->{ack}{$dnname};
			}

			$act{dst} = $dnet->jlink;
			$dnet->send(\%act) if $dnet->jlink;
		}
		return if $dnet->jlink;
		my $hname = $snet->name;
		for my $dcname (keys %{$Link::request{$dnname}}) {
			my $ifo = $Link::request{$dnname}{$dcname};
			next if $ifo->{mode};
			next unless $ifo->{net} eq $hname && lc $ifo->{chan} eq $tochan;
			my $ichan = $dnet->chan($dcname, 1);
			$Janus::Burst = 1;
			Event::append(+{
				type => 'LINKREQ',
				chan => $ichan,
				dst => $snet,
				dlink => $tochan,
				reqby => $ifo->{mask},
				reqtime => $ifo->{time},
				linkfile => 1,
			});
		}
	},
});

1;
