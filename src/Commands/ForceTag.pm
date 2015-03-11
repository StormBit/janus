# Copyright (C) 2008-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Commands::ForceTag;
use strict;
use warnings;

Event::command_add({
	cmd => 'forcetag',
	help => 'Forces a user to use a tagged nick on a network',
	section => 'Network',
	syntax => '<nick> [<network>]',
	acl => 'forcetag',
	api => '=src =replyto nick localdefnet',
	code => sub {
		my ($src,$dst,$nick,$net) = @_;
		return Janus::jmsg($dst, 'Not on that network') unless $nick->is_on($net);
		Event::append({
			type => 'RECONNECT',
			src => $src,
			dst => $nick,
			net => $net,
			killed => 0,
			altnick => 1,
		});
		Janus::jmsg($dst, 'Done');
	},
});

1;
