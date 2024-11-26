/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"

configuration NodeC {
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;
    components ActiveMessageC;
    components new SimpleSendC(AM_PACK);
    components CommandHandlerC;

    // 1 
    components FloodingC; 
    components NeighborDiscoveryC;
    components new TimerMilliC() as NeighborDiscoveryTimer;
    

    // 2
    components LinkStateC; 
    components IPC; 



    Node -> MainC.Boot;
    Node.Receive -> GeneralReceive;
    Node.AMControl -> ActiveMessageC;
    Node.Sender -> SimpleSendC;
    Node.CommandHandler -> CommandHandlerC;
    // 1
    Node.NeighborDiscovery -> NeighborDiscoveryC;
    Node.Flooding -> FloodingC; 
    // 2 
    Node.LinkState -> LinkStateC; 
    Node.IP -> IPC; 
    
    // Add the NeighborDiscoveryTimer
    Node.NeighborDiscoveryTimer -> NeighborDiscoveryTimer;
}