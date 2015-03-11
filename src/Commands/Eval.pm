# Copyright (C) 2007-2009 Daniel De Graaf
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
# Released under the GNU Affero General Public License v3
package Commands::Eval;
use strict;
use warnings;
use Data::Dumper;

Event::command_add({
	cmd => 'eval',
	help => "Evaluates a perl expression. \002DANGEROUS\002",
	section => 'Admin',
	acl => 'eval',
	api => '=src =replyto =raw *',
	code => sub {
		my($src, $dst, $expr) = @_;
		print "EVAL: $expr\n";
		Log::audit('EVAL by '.$src->netnick.': '.$expr);
		$expr =~ /^eval (.*)/i; # go around taint mode
		$expr = $1;
		my $r = eval $expr;
		$r = $@ if $@ && !$r;
		if ($r) {
			$_ = eval {
				my $d = new Data::Dumper([$r]);
				$d->Indent(0)->Terse(1)->Dump;
			};
			s/\n/ /g;
			Janus::jmsg($dst, $_);
		}
	},
});

1;
