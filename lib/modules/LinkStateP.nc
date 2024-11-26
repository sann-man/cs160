#include "../../includes/packet.h"
#include "../../includes/RoutingTable.h"
#include "../../includes/NeighborTable.h"
#include "../../includes/LSA.h"
#include <Timer.h>

module LinkStateP {
    provides interface LinkState;
    
    uses {
        interface SimpleSend as Sender;
        interface Receive as Receiver;
        interface Hashmap<LSA> as Cache;
        interface NeighborDiscovery as Neighbor;
        interface Timer<TMilli> as LSATimer;
    }
}

implementation {
    uint16_t sequenceNum = 1;
    neighbor_t neighborTable[MAX_NEIGHBORS];
    LSA lsa;
    routing_t routingTable[MAX_NODES];
    uint8_t routingTableSize = 0;
    bool initialized = FALSE;

    void initLSA() {
        uint8_t i;
        uint8_t neighborCount = 0;
        
        dbg(ROUTING_CHANNEL, "Node %d: Initializing LSA\n", TOS_NODE_ID);
        
        // Get current neighbors
        call Neighbor.getNeighbor(neighborTable);
        
        // Clear LSA
        memset(&lsa, 0, sizeof(LSA));
        lsa.src = TOS_NODE_ID;
        lsa.seq = sequenceNum++;
        
        // Add active neighbors to LSA
        for(i = 0; i < MAX_NEIGHBORS; i++) {
            if(neighborTable[i].isActive == ACTIVE) {
                lsa.tupleList[neighborCount].neighbor = neighborTable[i].neighborID;
                lsa.tupleList[neighborCount].cost = neighborTable[i].linkQuality;
                neighborCount++;
                dbg(ROUTING_CHANNEL, "Node %d: Added neighbor %d with cost %d to LSA\n",
                    TOS_NODE_ID, neighborTable[i].neighborID, neighborTable[i].linkQuality);
            }
        }
        
        lsa.numTuples = neighborCount;
        
        // Store our own LSA in cache
        call Cache.insert(TOS_NODE_ID, lsa);
    }

    command error_t LinkState.start() {
        dbg(ROUTING_CHANNEL, "Node %d: Starting LinkState\n", TOS_NODE_ID);
        initialized = TRUE;
        call LSATimer.startPeriodic(30000); // Send LSA every 30 seconds
        return SUCCESS;
    }

    void floodLSAPacket(LSA* lsaToFlood) {
        pack sendPackage;
        
        sendPackage.src = TOS_NODE_ID;
        sendPackage.dest = AM_BROADCAST_ADDR;
        sendPackage.TTL = 20; // Increased TTL to ensure network coverage
        sendPackage.protocol = PROTOCOL_LINKSTATE;
        sendPackage.seq = sequenceNum;
        
        memcpy(sendPackage.payload, lsaToFlood, sizeof(LSA));
        
        if(call Sender.send(sendPackage, AM_BROADCAST_ADDR) == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: Flooding LSA from node %d\n", 
                TOS_NODE_ID, lsaToFlood->src);
        }
    }

    command void LinkState.floodLSA() {
        if(!initialized) return;
        
        initLSA();
        floodLSAPacket(&lsa);
    }

    void runDijkstra() {
        typedef struct {
            uint16_t cost;
            uint16_t nextHop;
            bool known;
        } DijkstraEntry;

        DijkstraEntry dij[MAX_NODES];
        uint16_t i;
        uint16_t currentNode;
        uint16_t minCost;
        bool done;
        LSA currentLSA;

        // Initialize Dijkstra entries
        for(i = 0; i < MAX_NODES; i++) {
            dij[i].cost = INFINITE_COST;
            dij[i].nextHop = INVALID_NODE;
            dij[i].known = FALSE;
        }

        // Set source node
        dij[TOS_NODE_ID].cost = 0;
        dij[TOS_NODE_ID].nextHop = TOS_NODE_ID;

        do {
            minCost = INFINITE_COST;
            currentNode = INVALID_NODE;
            done = TRUE;

            // Find closest unknown node
            for(i = 0; i < MAX_NODES; i++) {
                if(!dij[i].known && dij[i].cost < minCost && call Cache.contains(i)) {
                    minCost = dij[i].cost;
                    currentNode = i;
                    done = FALSE;
                }
            }

            if(done) break;

            dij[currentNode].known = TRUE;
            
            // Get LSA for current node
            currentLSA = call Cache.get(currentNode);
            
            // Process all neighbors
            for(i = 0; i < currentLSA.numTuples; i++) {
                uint16_t neighborId = currentLSA.tupleList[i].neighbor;
                uint16_t linkCost = currentLSA.tupleList[i].cost;
                uint16_t totalCost = dij[currentNode].cost + linkCost;

                if(totalCost < dij[neighborId].cost) {
                    dij[neighborId].cost = totalCost;
                    if(currentNode == TOS_NODE_ID) {
                        dij[neighborId].nextHop = neighborId;
                    } else {
                        dij[neighborId].nextHop = dij[currentNode].nextHop;
                    }
                }
            }
        } while(!done);

        // Update routing table
        routingTableSize = 0;
        for(i = 0; i < MAX_NODES; i++) {
            if(i != TOS_NODE_ID && dij[i].cost != INFINITE_COST) {
                routingTable[routingTableSize].dest = i;
                routingTable[routingTableSize].nextHop = dij[i].nextHop;
                routingTable[routingTableSize].cost = dij[i].cost;
                routingTableSize++;
            }
        }

        // Log routing table
        dbg(ROUTING_CHANNEL, "Node %d: Updated Routing Table (%d entries):\n", 
            TOS_NODE_ID, routingTableSize);
        for(i = 0; i < routingTableSize; i++) {
            dbg(ROUTING_CHANNEL, "\tDest: %d, NextHop: %d, Cost: %d\n",
                routingTable[i].dest,
                routingTable[i].nextHop,
                routingTable[i].cost);
        }
    }

    command void LinkState.getRouteTable(routing_t* table, uint8_t* size) {
        uint8_t i;
        for(i = 0; i < routingTableSize; i++) {
            table[i] = routingTable[i];
        }
        *size = routingTableSize;
    }

    event message_t* Receiver.receive(message_t* msg, void* payload, uint8_t len) {
        pack* myMsg;
        LSA receivedLSA;
        
        if(len != sizeof(pack)) return msg;
            
        myMsg = (pack*) payload;
            
        if(myMsg->protocol != PROTOCOL_LINKSTATE) return msg;
            
        memcpy(&receivedLSA, myMsg->payload, sizeof(LSA));
            
        // Check if this is new LSA information
        if(!call Cache.contains(receivedLSA.src) || 
           receivedLSA.seq > ((LSA)call Cache.get(receivedLSA.src)).seq) {
                
            dbg(ROUTING_CHANNEL, "Node %d: Received new LSA from %d\n", 
                TOS_NODE_ID, receivedLSA.src);
                
            // Update cache
            call Cache.insert(receivedLSA.src, receivedLSA);
                
            // Forward LSA
            if(myMsg->TTL > 0) {
                pack forwardPackage = *myMsg;
                forwardPackage.TTL--;
                call Sender.send(forwardPackage, AM_BROADCAST_ADDR);
            }
                
            // Recalculate routes
            runDijkstra();
        }
        
        return msg;
    }

    event void LSATimer.fired() {
        call LinkState.floodLSA();
    }

    event void Sender.sendDone(message_t* msg, error_t error) {}

    event void Neighbor.done() {
        call LinkState.floodLSA();
    }
}