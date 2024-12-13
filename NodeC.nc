/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
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
    components FloodingC;
    components NeighborDiscoveryC;
    components new TimerMilliC() as NeighborDiscoveryTimer;
    components LinkStateC;
    components IPC;
    components new HashmapC(uint32_t, 20) as SeenTable;
    components TransportC;
    components TestC;
    components ChatC; 

    Node.Seen -> SeenTable;
    Node -> MainC.Boot;
    Node.Receive -> GeneralReceive;
    Node.AMControl -> ActiveMessageC;
    Node.Sender -> SimpleSendC;
    Node.CommandHandler -> CommandHandlerC;
    Node.NeighborDiscovery -> NeighborDiscoveryC;
    Node.Flooding -> FloodingC;
    Node.LinkState -> LinkStateC;
    Node.IP -> IPC;
    Node.NeighborDiscoveryTimer -> NeighborDiscoveryTimer;
    Node.Test -> TestC;    
    Node.Transport -> TransportC;  
    Node.Chat -> ChatC; 
}