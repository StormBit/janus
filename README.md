What is this?
-------------

This is a fork of the Sourceforge version of Janus IRC Linker by Daniel De Graaf with the Trix-Janus Mods. I've done this because the older code lacks some of the bugs introduced in the Github version. I've stopped updating trix-janus, so use this one instead ;)

What changes did you make?
--------------------------

In short? Most of the annoying messages have been disabled. The Controller bot and it's features have been made more configurable from the conf file. A few features like custom (branded) domain names for the Janus bots, forced network tagging, colour code stripping and oper sharing level have been added in. The conf file also have been modified a bit to give a better working example and several notes have been added in to avoid confusion.

Note: There is now only ONE Inspircd file instead of three which works with 1.2+ and 2.0+. Please change your janus.conf to reflect this change!

How do I get a copy?
--------------------

The recommended way is to use `git clone git://github.com/Trixarian/janus.git` to create a copy on your server. Using this method will give you access to the up-git command and make all future upgrades easier.

You can however also download a copy from https://github.com/Trixarian/janus/archive/master.tar.gz and try using up-tar to upgrade it, but it's not as effective as the up-git way.

Quick start:
------------

Run ./configure to check module dependencies and compile multiplex.

See the example configuration for a description of what is needed there.
After editing the configuration start janus by running ./janus.pl

Note: Look in the /doc directory for more help regarding Janus and it's parts.