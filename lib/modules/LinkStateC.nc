#include "../../includes/packet.h"
#include "../../includes/LSA.h"

configuration LinkStateC {
    provides interface LinkState;
}
implementation {
    components LinkStateP;
    components new SimpleSendC(AM_PACK);
    components new HashmapC(LSA, 20) as CacheC;
    components NeighborDiscoveryC;
    components new TimerMilliC() as LSATimerC;
    
    LinkState = LinkStateP.LinkState;
    
    LinkStateP.Sender -> SimpleSendC;
    LinkStateP.Cache -> CacheC;
    LinkStateP.Neighbor -> NeighborDiscoveryC;
    LinkStateP.LSATimer -> LSATimerC;
}