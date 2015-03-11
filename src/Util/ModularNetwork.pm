# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Util::ModularNetwork;
use Persist 'LocalNetwork';
use strict;
use warnings;

our @modules;   # {module} => definition - List of active modules
our @meta;      # key => sub{} for METADATA command
our @fromirc;   # command => sub{} for IRC commands
our @act_hooks; # type => module => sub{} for Janus Action => output

our(@txt2cmode, @cmode2txt, @txt2umode, @umode2txt); # quick lookup hashes for translation in/out of janus
Persist::register_vars(qw(modules meta fromirc act_hooks txt2cmode cmode2txt txt2umode umode2txt));

sub module_add {
	my($net,$name,$opt) = @_;
	return if $modules[$$net]{$name};
	my $mod;
	Event::named_hook('Server/find_module', $net, $name, \$mod);
	unless ($mod) {
		#Log::err_in($net, "Unknown module $name, janus may become desynced if it is used") unless $opt;
		$mod = {};
	};
	$modules[$$net]{$name} = $mod;
	if ($mod->{cmode}) {
		for my $cm (keys %{$mod->{cmode}}) {
			my $txt = $mod->{cmode}{$cm};
			warn "Overriding mode $cm = $txt" if $cmode2txt[$$net]{$cm} || $txt2cmode[$$net]{$txt};
			$cmode2txt[$$net]{$cm} = $txt;
			$txt2cmode[$$net]{$txt} = $cm if length $txt > 2;
		}
	}
	if ($mod->{umode}) {
		for my $um (keys %{$mod->{umode}}) {
			my $txt = $mod->{umode}{$um};
			warn "Overriding umode $um = $txt" if $umode2txt[$$net]{$um} || $txt2umode[$$net]{$txt};
			$umode2txt[$$net]{$um} = $txt;
			$txt2umode[$$net]{$txt} = $um if $txt;
		}
	}
	if ($mod->{umode_hook}) {
		for my $txt (keys %{$mod->{umode_hook}}) {
			warn "Overriding umode $txt" if $txt2umode[$$net]{$txt} && !$mod->{umode}{$txt2umode[$$net]{$txt}};
			$txt2umode[$$net]{$txt} = $mod->{umode_hook}{$txt};
		}
	}
	if ($mod->{cmds}) {
		for my $cmd (keys %{$mod->{cmds}}) {
			warn "Overriding command $cmd" if $fromirc[$$net]{$cmd};
			$fromirc[$$net]{$cmd} = $mod->{cmds}{$cmd};
		}
	}
	if ($mod->{acts}) {
		for my $t (keys %{$mod->{acts}}) {
			$act_hooks[$$net]{$t}{$name} = $mod->{acts}{$t};
		}
	}
	if ($mod->{metadata}) {
		for my $i (keys %{$mod->{metadata}}) {
			warn "Overriding metadata $i" if $meta[$$net]{$i};
			$meta[$$net]{$i} = $mod->{metadata}{$i};
		}
	}
}

sub module_remove {
	my($net,$name,$opt) = @_;
	my $mod = delete $modules[$$net]{$name} or do {
		return if $opt;
		Log::err_in($net, "Could not unload moule $name: not loaded");
		return;
	};
	if ($mod->{cmode}) {
		for my $cm (keys %{$mod->{cmode}}) {
			my $txt = $mod->{cmode}{$cm};
			delete $cmode2txt[$$net]{$cm};
			delete $txt2cmode[$$net]{$txt};
		}
	}
	if ($mod->{umode}) {
		for my $um (keys %{$mod->{umode}}) {
			my $txt = $mod->{umode}{$um};
			delete $umode2txt[$$net]{$um};
			delete $txt2umode[$$net]{$txt};
		}
	}
	if ($mod->{umode_hook}) {
		for my $txt (keys %{$mod->{umode}}) {
			delete $txt2umode[$$net]{$txt};
		}
	}
	if ($mod->{cmds}) {
		for my $cmd (keys %{$mod->{cmds}}) {
			delete $fromirc[$$net]{$cmd};
		}
	}
	if ($mod->{acts}) {
		for my $t (keys %{$mod->{acts}}) {
			delete $act_hooks[$$net]{$t}{$name};
		}
	}
	if ($mod->{metadata}) {
		for my $i (keys %{$mod->{metadata}}) {
			delete $meta[$$net]{$i};
		}
	}
}

sub get_module {
	my($net,$name) = @_;
	$modules[$$net]{$name};
}

sub all_modules {
	my($net,$name) = @_;
	keys %{$modules[$$net]};
}

sub cmode2txt {
	my($net,$cm) = @_;
	$cmode2txt[$$net]{$cm};
}

sub txt2cmode {
	my($net,$tm) = @_;
	$txt2cmode[$$net]{$tm};
}

sub all_cmodes {
	my $net = shift;
	keys %{$txt2cmode[$$net]};
}

sub umode2txt {
	my($net,$um,$ok) = @_;
	my $t = $umode2txt[$$net]{$um};
	if (!defined $t && !$ok) {
	# Redundency is fun :D
	#	Log::warn_in($net, "Unknown umode '$um'");
		$t = '';
	}
	$t;
}

sub txt2umode {
	my($net,$tm) = @_;
	$txt2umode[$$net]{$tm};
}

sub all_umodes {
	my $net = shift;
	keys %{$txt2umode[$$net]};
}

sub do_meta {
	my $net = shift;
	my $key = shift;
	my $mdh = $meta[$$net]{$key};
	return () unless $mdh;
	$mdh->($net, @_);
}

sub from_irc {
	my $net = $_[0];
	my $cmd = $_[2];
	$cmd = $fromirc[$$net]{$cmd} || $cmd;
	$cmd = $fromirc[$$net]{$cmd} || $cmd if $cmd && !ref $cmd; # allow one layer of indirection
	unless ($cmd && ref $cmd) {
		Log::err_in($net, "Unknown command '$cmd'");
		return ();
	}
	$cmd->(@_);
}

sub _parse_umode {
	my($net, $nick, $mode) = @_;
	my @mode;
	my $pm = '+';
	for (split //, $mode) {
		if (/[-+]/) {
			$pm = $_;
		} else {
			my $txt = $net->umode2txt($_) or next;
			push @mode, $pm.$txt;
		}
	}
	my @out;
	push @out, +{
		type => 'UMODE',
		dst => $nick,
		mode => \@mode,
	} if @mode;
	@out;
}

sub to_irc {
	my $net = shift;
	my @sendq;
	for my $act (@_) {
		if (ref $act && ref $act eq 'HASH') {
			my $type = $act->{type};
			for my $ttype ("$type-", $type, "$type+") {
				next unless $act_hooks[$$net]{$ttype};
				for my $hook (values %{$act_hooks[$$net]{$ttype}}) {
					push @sendq, $hook->($net,$act);
				}
			}
		} else {
			push @sendq, $act;
		}
	}
	@sendq;
}

sub reload_moddef {
	my $net = shift;
	return unless $net->isa(__PACKAGE__);
	my @mods = keys %{$modules[$$net]};
	Log::info('Reloading module definitions for',$net->name,$net->gid);
	for my $mod (@mods) {
		$net->module_remove($mod);
		$net->module_add($mod, 1);
	}
}

Event::hook_add(
	MODRELOAD => 'act:1' => sub {
		my $act = shift;
		return unless $act->{module} =~ /^Server::/;
		for my $net (values %Janus::nets) {
			next unless $net->isa(__PACKAGE__);
			$net->reload_moddef();
		}
	}
);

sub umode_o_in {
	$_[1].'oper';
}

sub umode_o_out {
	my $net = $_[0];
	my $visible = $Janus::operlvl;
	$visible = Setting::get(oper_visibility => $net) if Setting::get(oper_visibility => $net) < $visible;
	return () unless $visible;
	return 'oH' if $visible == 1 && $net->hook(umode_in => 'H');
	return 'o';
}

1;
