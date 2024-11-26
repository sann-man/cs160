#include "../includes/packet.h"
#include "../includes/protocol.h"
#include "../includes/am_types.h"
#include "../includes/NeighborTable.h" 

configuration NeighborDiscoveryC {
    provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    components new SimpleSendC(AM_PACK);
    components new TimerMilliC() as NeighborDiscoveryTimer;
    components RandomC;

    NeighborDiscovery = NeighborDiscoveryP.NeighborDiscovery;

    NeighborDiscoveryP.Sender -> SimpleSendC;
    NeighborDiscoveryP.NeighborDiscoveryTimer -> NeighborDiscoveryTimer;
    NeighborDiscoveryP.Random -> RandomC;
}