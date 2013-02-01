Getting Started
================

This guide should teach you the basics of how to use Janus the right way ;)


Introducing Your Channel
========================

Before your channel can be brought to other parts of the network, introducing your channel to Janus is necessary. To communicate with Janus, you simply PM the user "Janus" (or as set by the nickname in Janus' config)

Now, ensure that you are +q in the channel you would like to bring to Janus, and once you have done so, execute:  
`/msg Janus create <channel name>`

After executing this, Janus is now aware of your channel.

To protect your channel so other networks cannot modify permissions, first find out which network you are on. To do so, run:

/msg Janus linked

Now, look at the first line it displays. The bolded network, or first listed network, is your current network.

Example:

Linked Networks:	'''fn'''		rtn xr zn   

The above displays /msg Janus Linked, indicating “fn” being the current network.

Now that we have the network, execute:

/msg Janus claim <#channel name> <Home Network>

Please note, the <Home Network> is the network abbreviation for the network, not it's full name.
[edit] Linking into Other Networks (Same Chan Name)

After introducing your channel, now it is time to link your channel into other networks. Depending on the network, prior permission may need to be granted. First, find out the other network's server address – it is required to log into the other network to do this.

Now, join the channel you want to link your channel into. If I had #Generic on “fn”, and I wanted it to be named “#Generic” on “zz”, I log into “zz”'s servers, and  
`/join #Generic`  
and then possibly registering it.

Now that you are in the other network's servers, privage message Janus, and link the channel:  
`/msg Janus link <#channel name> <Home Network>`

Like:

/msg Janus link #Generic fn

[edit] Linking into Other Networks (Differing Chan Names)

If you wanted to rename your channel on other networks, such as if I wanted “#Generic” to link to “#Bland”, I simply:

/join #Bland<pre>

Now, on the other network, execute:
<pre>/msg Janus link <#New Name> <Home Network> <#Home Network's Channel Name>

Like:

/msg Janus link #Bland fn #Generic

[edit] Delinking a Channel from a Network

Sometimes, channel owners may need to pull their channel from a certain network. From the home network, simply run:

/msg Janus delink <#Channel> <Home Network>

[edit] Removing a channel from Janus

Removing a channel from Janus is even easier, it destroys all links. To recreate the links, you must re-create it, and re-link it again.

/msg Janus destroy <#Channel>