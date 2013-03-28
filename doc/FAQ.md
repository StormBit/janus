Why use Janus?
--------------

Janus allows server administrators the chance to link their channels to another server and visa-versa without having to share ALL channels on the network. Each network still have their own IRC ops, although those channels which are shared can be controlled by any IRC op, unless the channel is claimed with Janus.


Do I have to install Janus too?
-------------------------------

No! Only one person needs to host Janus. We estimate between 250-360 different networks can be hosted on Janus before someone has to edit the source code. Janus runs on its own, and links to two or more IRC Daemons.


Is it easy to link a Janus?
---------------------------

Yes! You add Janus just like you would another server by linking with a link block. It can link to multiple networks and selectively share channels with various network on a per share and link basis.


How do I use Janus once it's installed?
---------------------------------------

First thing you should do is run `./configure` to compile multiplex and then configure `janus.conf` using the `Configuration Guide`. Then just type `./janus` to start it.
Once it's running, use the `Getting Started` guide to learn how to use Janus.


What IRCds can link with a Janus?
---------------------------------

InspIRCd, UnrealIRCd, Charybdis, Ircd-seven, Ratbox IRCd, ShadowIRCd and most TS6 based IRCds have been known to work with Janus. For unsupported IRCds, you can just use a ClientBot Link.


What is different between Janus v1.10 and this version? 
-------------------------------------------------------

This version has several bug fixes and new features. It's a hybrid of trix-janus and the the old sourceforge version, being more like the prior without all the bugs that comes with it. 

**New features:** Custom Domain for links, Forced Network Tagging, mIRC Control Code Control and the ability to set how the bot responds to you - either by NOTICE or PRIVMSG.  
**Improvements:** ClientBot has more sane defaults, more configurable and doesn't flood a channel on join or netsplit. Most of Janus' defaults can now be set from the conf file like Oper Visibility, Link Requirement and the Tag Separator. InterJanus links can now be up to 70 seconds out of sync before refusing to connect compared to the default 20 seconds.  
**Major Changes:** There is only one TS6 module and one InspIRCd module to simplify the configuration process. `janus.pl` has been renamed to `janus`. The configuration file has a better working example and this Janus includes better documentation in /doc to get you started quickly. Most of the features have been ported to all Server modules. The TS6 module doesn't use `ircd` anymore and uses the Charybdis/ShadowIRCd features by default.  
**Bug Fixes:** Most of the annoying or insane error messages have been disabled or removed and a fix for compiling Multiplex on Ubuntu with a broken copy of OpenSLL has been added. The missing channel owner(s) bug found in the latest github version is NOT preset in this version ;)