Janus Configuration
===================

Janus will not start without a properly configured janus.conf in its root directory (traditionally ~/janus). This file contains an example configuration. You should never leave default values. If you do, the whole world has your information! If you don't know what something does then the default value should work fine and has been crafted in a such a way that it works with the majority of servers without any problems.


Set Block
=========
The set block contains unique information about your Janus service:

name: Your Janus's "name" in a InterJanus network. This should be short and not a domain name.  

save: Where Janus will save multiple types of information gathered via runtime.

janus_nick: The nickname of the Janus Bot. This is what you will /msg <ClientNick> HELP to. (Default: Janus)  
janus_ident: The user/ident used by the Janus Bot. (Default: janus)  
janus_name: The Real Name used by the Janus Bot. (Default: Janus Control Interface)  
janus_host: The vHost used by the Janus Bot. (Default: services)  
janus_rhost: The interface host used by the Janus Bot. (Default: service.janus)

janus_type: The interface response type used by the Janus Bot. (Default: privmsg)  
    * notice: Sends Interface responses to the user as notices.  
    * privmsg: Sends Interface responses to the user as private messages.

password: The password the admin account will have. You will identify as IDENTIFY <password>, where "password" is set here.

lmode: This is how Janus will treat linking. Valid parameters include link and bridge. (Default: link)  
    * link: The traditional method of linking; links only specific channels.  
    * bridge: Will link all channels between servers, making opers more global. You should use 1 set of services here!

linkreq: This is the minimum access level required to create, link and destroy channels with Janus. (Default: owner)  
    * owner: User needs to be atleast an owner of the channel to add/link it  
    * op: User needs to be atleast an op on the channel to add/link it  
    * oper: User needs to be atleast an oper on the network to add/link channels

laddy: Defines the domain name used by Janus in /links and /map when linked. (Default: janus)

septag: Defines the seperatator used between a user's nick and the network tag. (Default: /)

tagall: If enabled, this will force Janus to tag all nicknames from other networks with network tags. (Default: 0)  
    * 0: Disables Forced Network Tagging  
    * 1: Enables Forced Network Tagging

operlvl: Controls how Janus shares opers between Janus Linked networks. (Default: 0)  
    * 0: Disables all Oper Status Sharing  
    * 1: Adds +H (hide oper stats mode) to all Opers it shares  
    * 2: Complete Oper Status Sharing without restrictions

cclvl: Controls how Janus forwards Channel messages with mIRC control codes in them. (Default: 1)
    * 0: Allows Colours, Bold and Underline
    * 1: Removes only Colours
    * 2: Removes all Colours, Bold and Underline

pidfile: Janus will create this file with its running PID.

datefmt: Defines logging style.

runmode: mplex(-daemon) or uproc(-daemon). (Default: mplex)  
    * mplex: Multiplex support. Running './configure' will tell you if Multiplex is supported. This is recommended.  
    * uproc: Used if Multiplex is not available  
    * -daemon: Daemonize the process


Below is an example of the minimum required settings that NEED to be set for Janus to work:  
	set {
		name yourserver
		save janus.dat
		password verysecret
        pidfile janus.pid
	}


Modules Block
=============

Modules allow Janus to function. Without many of these modules, you will have a misconfigured or malfunctional Janus Client. Anything prefixed with Modules:: is optional. We've configured with some recommended ones.

"::" indicates folder in relation to the src/ folder. For example, Modules::Ban points to src/Modules/Ban.pm. "*" indicates all files in the directory ending with ".pm". Commands::* will load all modules in src/Commands/.

Example Module block shown below with all available modules:  
    modules {
        Commands::*
        Modules::Ban
        Modules::Claim
        Modules::Signals
        Modules::Spamfilter
        Modules::WhoisFilter
        Modules::Global
    }


Modules
-------

Janus is a modular system. Though not fully modular, anything can be loaded and unloaded runtime - even specific commands. Janus also has modules that are not always desirable with all networks, but prove useful in many situations. Networks should decide whether which modules to use before starting Janus for the first time, so each module will learn its environment.

Janus's modular nature makes module writing fairly easy. Full Module API documentation is not available yet; this is for those who are slightly more versed in Perl and can read the code and learn from it. Development on Janus generally requires advanced experience in Perl and the core modules used, but the same cannot be said for custom module creation.

Module Example:
---------------
    package Modules::Ping;
    use strict;
    use warnings;
     
    Event::command_add({
        cmd => 'ping',
        help => 'Allow users to see if their connection is still alive.',
        section => 'Other',
        details => [
            'Janus will reply "Pong!" to users who issue the command.',
        ],
        acl => 'none',
        code => sub {
            my($src, $dst) = @_;
            Janus::jmsg($dst, "Ping!"); 
        }
    });
     
    1;

Ban
---
Allows per-network bans of specific expressions matching users. Causes an auto-kickban when the user joins a remote channel.

BanSet
------
Faster ban implementation for large ban lists (hundreds) by using exact matches rather than a linear search of regular expressions.

Claim
-----
Prevents opers and other network's services from changing modes in a shared channel if that channel has been claimed by certain network(s).

Global
------
Send a global message to all channels or all users on the network. This module should be used lightly, as it's very annoying to ClientBot Networks. If you're a large network, Janus may attempt to notice non-existant users in the event of a desync.

KeepMode
--------
Stores the modes of a channel and restores them on a relink. Useful if you use "setmode" to change mode not available on the home network's ircd.

Services
--------
Prevents communication to and from remote services, and prevents services kills from being translated into kicks unless they are repeated.

Signals
-------
Rehashes the Janus server on reciept of a SIGHUP.

Spamfilter
----------
Kills users sending a message matching a hardcoded regular expression. It is planned to replace this with a proper word-based filter in the future.

QLine
-----
Caches Q-lines for all networks, and optionally applies them to incoming nicks. This module must be loaded when Janus starts to cache all lines; if loaded while running, it will only cache new lines, or will learn of all lines on the next netsplit.

Whoisfilter
-----------
Filters the /whois notification sent for remote nicks. These notices can be an annoyance because opers may not even be able to see a nick that can /whois them, and are often not interested in the activity of users not on their network.


Log Block
=========

Janus logs all events it sees, including errors, commands, and simple connections. The log block defines where it will store and write this information. Logging is supported to a channel, and to files.

`log log/janus-%m-%d.log {` is an example of logging to a file. The second parameter (`log/janus-%m-%d.log`) indicates which folder to save the information to, in relation to the root directory. If your root directory is janus/, it will be stored in janus/log. `%m` is a variable for month, while `%d` is a variable for the day.

`log Hub#Services {` will log to #Services on the Hub network. The second parameter ("Hub") is the shortname for the network's channel to log to. This is defined in a link block, later on in the configuration.

Example Log Blocks below:  
    log log/%Y%m%d.log {
        type File
        filter debug info warn err audit debug_in info_in warn_in err_in hook_err poison
        # dump 1
        rotate 86400
        # closeact gzip
    }

    log gig#Services {
        type Channel
        filter err audit err_in
    }


Listen Block
============

Similar to UnrealIRCd's listen block, this defines which IP and port to bind to. Multiple listen blocks may be defined at once. If that is so, Janus will take precedent to the first IP it has bound to when linking to networks.

Listen Blocks Examples:

	listen *:8005 # Can be used if there is only one ip available on the machine
	listen 0.0.0.0:8005 # Can be used if there are one or more ip's available on the machine


Link Block
==========

You must have one link block for each network. This is how Janus links to your IRCd. Two link blocks are required for a functioning Janus. Any less and its just wasted space.

link <name>: This is the unique identifier for the network. It will be referred to this way when linking channels, settings, etc. It is the tag used on conflicting nicks as well. This should be very short and may only contain characters A-Z / a-z.  
type: The protocol of the server.  
    * Unreal: UnrealIRCd 3.2.x+  
    * Inspircd: InspIRCd 1.2+  
    * TS6: TS6 Generic IRCd (ShadowIRCd, Charybdis, ircd-ratbox, etc.)  
    * ClientBot: Relay Bot for Unsupported IRCds
    * InterJanus: For Linking two Janus Servers together
linkaddr: IP of the server we're connecting to.  
linkbind: IP Address to bind to when connecting. Used for multi-homed hosts. (Optional).  
linkport: Port to connect on.  
linktype: Use plaintext or SSL.  
    * plain: No special encryption. Plain Text.  
    * ssl: Use Secure Socket Layers or GnuTLS.   
sendpass: Password to send to the server on authentication.  
recvpass: Password to accept from the server on authentication.  
linkname: Pseudo-Server to create and connect with. The uplink will receive a connection from this server name.  
netname: Network Name for the uplink. This will show up in /WHOIS for users connected on that network.  
autoconnect: Turn autoconnect on or off  
    * 1: Autoconnect on start, on rehash, and after so many seconds (defined with /msg Janus AUTOCONNECT)  
    * 0: Do not autoconnect; wait for the server to try to connect to us.  
untrusted: Hide all users real-hosts and IPs from Operators on this network.  
    * 1: Hidden as 0.0.0.0. This does not conflict with anything.  
    * 0: IPs and hosts will be visible.  
numeric_range: Only needed for UnrealIRCd and attributes a range of numerics Janus may use on a network.  

Example Link Blocks:
--------------------

Unreal Link Block
-----------------
    link unreal {
        type Unreal
        linkaddr 127.0.0.1
        linkbind 255.255.255.0
        linkport 8005
        linktype plain
        sendpass PaSs
        recvpass pAsS
        linkname net.domain.com
        netname MyNetwork
        autoconnect 1
        untrusted 0
        numeric_range 42-43
    }


InspIRCd Link Block
--------------------
    link insp {
        type InspIRCd
        linkaddr 127.0.0.1
        linkbind 255.255.255.0
        linkport 8005
        linktype plain
        sendpass PaSs
        recvpass pAsS
        linkname net.domain.com
        netname MyNetwork
        autoconnect 1
        untrusted 0
    }


TS6 Link Block
--------------
    link ts6 {
        type TS6
        linkaddr 127.0.0.1
        linkbind 255.255.255.0
        linkport 8005
        linktype plain
        sendpass PaSs
        recvpass pAsS
        linkname net.domain.com
        netname MyNetwork
        autoconnect 1
        untrusted 0
    }


ClientBot Link Block
--------------------
    link cbot {
        type ClientBot
        linkaddr 1.2.3.4
        linkport 6667
        linktype plain
        nick jmirror
        name Janus IRC Bot
        servpass ServerPassWord
        nspass NickServPassWord
        netname RelayBot
        autoconnect 1
        untrusted 0
    }


InterJanus Link Block
---------------------
Note: This link id must match the set::name of the Janus server your linking yours to!
    link myserver {
        type InterJanus
        linkaddr 1.2.3.4
        linkport 8009
        linktype plain
        sendpass pass
        recvpass ssap
        netname JLinkHub
        autoconnect 1
    }