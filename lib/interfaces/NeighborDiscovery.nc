#include "../../includes/NeighborTable.h"
interface NeighborDiscovery {
    command error_t start();
    command void checkStartStatus();  
    command void handleNeighbor(uint16_t id, uint8_t quality); 
    command void getNeighbor(neighbor_t* tableFlood);
    event void done(); // added for LS
}
