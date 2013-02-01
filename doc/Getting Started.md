Getting Started
===============

This guide should teach you the basics of how to use Janus the right way ;)


Introducing Your Channel
------------------------

Before your channel can be brought to other parts of the Janus network, introducing your channel to Janus is necessary. To communicate with Janus, you simply PM the user "Janus" (or as set by the nickname in janus.conf)

First ensure that you are atleast an op in the channel you would like to bring to Janus then run:  
`/msg Janus create <channel name>`

Janus should now be able to share your channel with other networks in the Janus network.

To protect your channel so other networks cannot modify permissions, first find out which network you are on. To do so run:  
`/msg Janus linked`

Now, look at the first line it displays. The bolded network, or first listed network, is your current network.

Example:  Linked Networks:	**fn**		rtn xr zn  

The above displays `/msg Janus Linked` indicating "fn" being the current network.

Now that we have the network claim the channel to your network with:  
`/msg Janus claim <#channel name> <Home Network>`

Please note: The <Home Network> is the network abbreviation of the network and not it's full name.


Linking into Channels
---------------------

After introducing your channel, now it is time to link your channel into other networks. Depending on the network, prior permission may need to be granted. First, find out the other network's server address - it is required to log into the other network to do this.

Now join the channel you want to link your channel into. If I had #Generic on "fn", and I wanted it to be named "#Generic" on "zz", I log into "zz"'s servers, and '/join #Generic` and then possibly registering it. Registration of both channels aren't required, but is generally suggested for the network that's sharing it. The linking network doesn't have to have the channel registered.

Now that you are in the other network's servers, privage message Janus, and link the channel:  
`/msg Janus link <#channel name> <Home Network>`

Example:  
`/msg Janus link #Generic fn`

Now if I wanted to link two differently named channels, such as linking "#Generic" on Network A to "#Bland" on Network B, I would join #Bland on the other network and type:  
`/msg Janus link <#New Name> <Home Network> <#Home Network's Channel Name>`

Example:  
`/msg Janus link #Bland fn #Generic`  


Delinking a Channel from a Network
-----------------------------------

Sometimes, channel owners may need to pull their channel from a certain network. From the home network run:  
`/msg Janus delink <#Channel> <Home Network>`


Removing a channel from Janus
-----------------------------

Removing a channel from Janus is even easier because it automatically delinks all network linked to a channel if the channel is destroyed. You remove a channel by running the folowing command:  
`/msg Janus destroy <#Channel>`