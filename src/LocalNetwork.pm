# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package LocalNetwork;
use Network;
use Channel;
use Persist 'Network';
use strict;
use warnings;
use constant {
	AUTH_RECV => 1,
	AUTH_SEND => 2,
	AUTH_OK   => 3,
	AUTH_DIR_IN  => 0x4,
	AUTH_DIR_OUT => 0x8,
	AUTH_DIR     => 0xC,
};

our(@fbid, @cparms, @nickseq, @auth);
Persist::register_vars(qw(fbid cparms nickseq auth));

sub param {
	my $net = shift;
	Conffile::value($_[0], $net, $fbid[$$net]);
}

sub cparam {
	my $net = shift;
	Conffile::value($_[0], $cparms[$$net], $fbid[$$net]);
}

sub intro {
	my($net,$conf,$peer) = @_;
	$auth[$$net] = $peer ? AUTH_DIR_IN : AUTH_DIR_OUT;
	$cparms[$$net] = { %$conf };

	my $fbmax = $cparms[$$net]{fb_max} || 1;
	my $fbid = $cparms[$$net]{fb_id} || 0;
	$fbid[$$net] = $fbid = 1 + ($fbid % $fbmax);
	$cparms[$$net]{'linkname.'.$fbid} ||= $RemoteJanus::self->jname;
}

sub next_nickgid {
	my $net = shift;
	$net->gid() . ':' . EventDump::seq2gid(++$nickseq[$$net]);
}

sub auth_recvd {
	my $net = shift;
	$auth[$$net] |= AUTH_RECV;
}

sub auth_sent {
	my $net = shift;
	$auth[$$net] |= AUTH_SEND;
}

sub auth_ok {
	my $net = shift;
	($auth[$$net] & AUTH_OK) == AUTH_OK;
}

sub auth_should_send {
	my $net = shift;
	return 0 unless $auth[$$net] & AUTH_DIR_OUT || $auth[$$net] & AUTH_RECV;
	return 0 if $auth[$$net] & AUTH_SEND;
	$auth[$$net] |= AUTH_SEND;
	1;
}

sub type {
	my $t = ref $_[0];
	$t = ${$_[0]}->{class} if $t eq 'Persist::Poison';
	$t;
}

Event::setting_add({
	name => 'force_tag',
	type => 'LocalNetwork',
	help => 'Regular expression for nicks that will be forcibly tagged',
	default => '',
}, {
	name => 'tagsep',
	type => 'LocalNetwork',
	help => 'Character used for tag separator.',
	default => '/',
}, {
	name => 'oper_visibility',
	type => 'LocalNetwork',
	help => [
		'Level of visibility remote opers have on this network',
		'0=not oper (may cause problems), 1=hidden, 2=visible',
	],
	default => 1,
});

### MODE SPLIT ###
eval($Janus::lmode eq 'Bridge' ? '#line '.__LINE__.' "'.__FILE__.qq{"\n}.q[#[[]]
### BRIDGE MODE ###

sub chan {
	my($net, $name, $new) = @_;
	$name = $net->lc($name);
	unless (exists $Janus::chans{$name}) {
		return undef unless $new;
		my $chan = Channel->new(
			net => $net,
			name => $name,
			ts => $new,
		);
		$Janus::chans{$name} = $chan;
	}
	$Janus::chans{$name};
}

sub replace_chan {
	my($net,$name,$new) = @_;
	$name = $net->lc($name);
	my $old = $Janus::chans{$name};
	warn "replacing nonexistant channel" unless $old;
	if (defined $new) {
		$Janus::chans{$name} = $new;
	} else {
		delete $Janus::chans{$name};
	}
	$old;
}

sub all_chans {
	values %Janus::chans;
}

1 ] : '#line '.__LINE__.' "'.__FILE__.qq{"\n}.q[#[[]]
### LINK MODE ###
our @chans;
Persist::register_vars(qw(chans));

sub _init {
	my $net = shift;
	$chans[$$net] = {};
}

sub chan {
	my($net, $name, $new) = @_;
	$name = $net->lc($name);
	unless (exists $chans[$$net]{$name}) {
		return undef unless $new;
		my $chan = Channel->new(
			net => $net,
			name => $name,
			ts => $new,
		);
		$chans[$$net]{$name} = $chan;
	}
	$chans[$$net]{$name};
}

sub replace_chan {
	my($net,$name,$new) = @_;
	$name = $net->lc($name);
	my $old = $chans[$$net]{$name};
	# This is really a useless thing to say about unlinked channels...
	# warn "replacing nonexistant channel" unless $old;
	if (defined $new) {
		$chans[$$net]{$name} = $new;
	} else {
		delete $chans[$$net]{$name};
	}
	$old;
}

sub all_chans {
	my $net = shift;
	values %{$chans[$$net]};
}

Event::hook_add(
	NETSPLIT => cleanup => sub {
		my $act = shift;
		my $net = $act->{net};
		return unless $net->isa('LocalNetwork');
		if (%{$chans[$$net]}) {
			my @clean;
			warn "channels remain after a netsplit, delinking...";
			for my $cn (keys %{$chans[$$net]}) {
				my $chan = $chans[$$net]{$cn};
				unless ($chan->is_on($net)) {
					Log::err("Channel $cn=$$chan not on network $$net as it claims");
					delete $chans[$$net]{$cn};
					next;
				}
				push @clean, +{
					type => 'DELINK',
					cause => 'split',
					dst => $chan,
					net => $net,
					nojlink => 1,
				};
			}
			Event::insert_full(@clean);
			for my $chan ($net->all_chans()) {
				$chan->unhook_destroyed();
			}
			warn "channels still remain after double delinks: ".join ',', keys %{$chans[$$net]} if %{$chans[$$net]};
			$chans[$$net] = undef;
		}
	},
	INFO => 'Network:1' => sub {
		my($dst, $net) = @_;
		return unless $net->isa('LocalNetwork');
		my $nickc = scalar $net->all_nicks;
		my $chanc = scalar keys %{$chans[$$net]};
		my $ngid = $net->gid . ':' . EventDump::seq2gid($nickseq[$$net]);
		Janus::jmsg($dst, "$nickc nicks, $chanc channels; nick GID $ngid");
	},
);

1 ]) or die $@;

1;
