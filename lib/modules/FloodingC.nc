#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components FloodingP;
    components new AMSenderC(AM_PACK);
    components new TimerMilliC() as FloodingTimer;
    components new AMReceiverC(AM_FLOODING); 
    components RandomC;
    components ActiveMessageC;

    Flooding = FloodingP.Flooding;
    
   
    FloodingP.Receive -> AMReceiverC;
    FloodingP.AMSend -> AMSenderC;
    FloodingP.AMControl -> ActiveMessageC;
    FloodingP.Packet -> AMSenderC;
    FloodingP.AMPacket -> AMSenderC;
    FloodingP.FloodingTimer -> FloodingTimer;
    FloodingP.Random -> RandomC;
}