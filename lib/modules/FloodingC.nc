#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

configuration FloodingC {
    provides interface Flooding;
}

implementation {
    components MainC;
    components FloodingP;
    components new SimpleSendC(AM_PACK);
    components new AMSenderC(AM_PACK);
    components new TimerMilliC() as FloodingTimer;
    components new AMReceiverC(AM_PACK);
    components RandomC;
    components ActiveMessageC;

    // Wire the provided interface
    Flooding = FloodingP.Flooding;

    // Wire boot sequence
    FloodingP.Boot -> MainC;

    // Wire communication interfaces
    FloodingP.Receive -> AMReceiverC;
    FloodingP.AMSend -> AMSenderC;
    FloodingP.AMControl -> ActiveMessageC;
    FloodingP.Packet -> AMSenderC;
    FloodingP.AMPacket -> AMSenderC;
    
    // Wire timer and random number generator
    FloodingP.FloodingTimer -> FloodingTimer;
    FloodingP.Random -> RandomC;
}