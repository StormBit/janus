Why use Janus?
==============

Janus allows server administrators the chance to link their channels to another server and visa-versa without having to share ALL channels on the network. Each network still have their own IRC ops, although those channels which are shared can be controlled by any IRC op, unless the channel is claimed with Janus.


Do I have to install Janus too?
===============================

No! Only one person needs to host Janus. We estimate between 250-360 different networks can be hosted on Janus before someone has to edit the source code. Janus runs on its own, and links to two or more IRC Daemons.


Is it easy to link a Janus?
===========================

Yes! You add Janus just like you would another server by linking with a link block. It can link to multiple networks and selectively share channels with various network on a per share and link basis.


How do I use Janus once it's installed?
=======================================

First thing you should do is run ./configure to compile multiplex and then configure janus.conf using the `Configuration Guide`.  
Once it's running, use the `Getting Started` guide to learn how to use Janus.


What IRCds can link with a Janus?
=================================

InspIRCd, UnrealIRCd, Charybdis, Ircd-seven, Ratbox IRCd, ShadowIRCd and most TS6 based IRCds have been known to work with Janus. For unsupported IRCds, you can just use a ClientBot.