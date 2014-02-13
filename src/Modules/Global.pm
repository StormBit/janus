# Copyright (c) 2010 Samuel Hoffman
# Modificiations (C) 2011 - 2014 Brenton Edgar Scott
package Modules::Global;
use strict;
use warnings;
use Persist;

Event::command_add({
  cmd => 'global',
  help => 'Send a global message to all channels/users.',
  section => 'Network managment',
  details => [
    "Sends a global PRIVMSG to all channels Janus is in."
  ],
  acl => 'netop',
  syntax => '<message>',
  code => sub {
    my ($src, $dst, @global) = @_;

    if (!defined $global[0])
    {
      Janus::jmsg($dst, "Not enough arguments. See \002HELP GLOBAL\002 for usage.");
      return;
    }
    my $msg = (join ' ', @global);

    $msg = "[\00303".$dst->homenick."\003] $msg";

    foreach (keys %Janus::gchans)
    {
      Event::insert_full({
        type => 'MSG',
        dst => $Janus::gchans{$_},
        msgtype => 'PRIVMSG',
        src => $Interface::janus,
        msg => $msg
      });
    }
    Janus::jmsg($dst, "Successfully sent.");
  }
});

1;
