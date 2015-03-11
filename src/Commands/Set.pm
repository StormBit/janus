# Copyright (C) 2008-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Commands::Set;
use strict;
use warnings;
use integer;

Event::command_add({
	cmd => 'listsettings',
	help => 'Shows the list of janus settings',
	section => 'Info',
	api => '=replyto',
	code => sub {
		my $dst = shift;
		my @table = [ qw/Type Name Default Description/ ];
		for my $set (sort { $a->{name} cmp $b->{name} } values %Event::settings) {
			my($desc,@ifo) = @$set{qw/help type name default/};
			$ifo[0] =~ s/^Server:://;
			$ifo[0] = 'Janus' if $ifo[0] eq 'Interface';
			my @desc = ref $desc ? @$desc : $desc;
			push @table, [ @ifo, shift @desc ];
			push @table, map [ '', '', '', $_ ], @desc;
		}
		Interface::msgtable($dst, \@table);
	},
}, {
	cmd => 'set',
	help => 'Change network or channel settings',
	syntax => '<network|channel> <setting> [<value>]',
	details => [
		'Changes the requested setting of the network or channel',
		'See the LISTSETTINGS command for the available settings',
	],
	api => 'act =src =replyto $ $ ?$',
	code => sub {
		my($act,$src,$dst,$item,$key,$value) = @_;
		my $set = $Event::settings{$key} or do {
			Janus::jmsg($dst, "Setting $key not found");
			return;
		};
		my $acl;
		if ($set->{type} eq 'Channel') {
			$item = Interface::api_parse($act, 'localchan', $item) or return;
			$acl = ($item->homenet == $src->homenet) ? 'set/channel' : 'setall/channel';
		} else {
			$item = Interface::api_parse($act, 'localnet', $item) or return;
			unless ($item->isa($set->{type})) {
				Janus::jmsg($dst, 'That setting does not apply to that network');
				return;
			}
			$acl = ($item == $src->homenet) ? 'set/network' : 'setall/network';
		}
		if ($acl && !Account::acl_check($src, $acl)) {
			Janus::jmsg($dst, "Changing this setting requires access to '$acl'");
			return;
		}
		Setting::set($key, $item, $value);
		Janus::jmsg($dst, 'Done');
	},
});

1;
