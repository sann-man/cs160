#ifndef __CHANNELS_H__
#define __CHANNELS_H__

// These should really be const value, but the dbg command will spit out a ton
// of warnings.
char COMMAND_CHANNEL[]="command";
char GENERAL_CHANNEL[]="general";

// Project 1
char NEIGHBOR_CHANNEL[]="NeighborDiscovery";
char FLOODING_CHANNEL[]="Flooding";

// Project 2
char ROUTING_CHANNEL[]="routing";

// Project 3
char TRANSPORT_CHANNEL[]="transport";

// Personal Debuggin Channels for some of the additional models implemented.
char HASHMAP_CHANNEL[]="hashmap";
#endif
