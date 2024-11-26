#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/NeighborTable.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface SimpleSend as Sender;
    uses interface Timer<TMilli> as NeighborDiscoveryTimer;
    uses interface Random;
}

implementation {
    pack sendPackage;
    neighbor_t neighborTable[MAX_NEIGHBORS]; 
    uint8_t count = 0;
    bool neighborDiscoveryStarted = FALSE;
    uint16_t sequenceNumber = 0;
    uint8_t discoveryCount = 0; // for LS
    // moved define to nt.h 

    // function prototypes 
    void checkInactiveNeighbors();
    void addNeighbor(uint16_t id, uint8_t quality);

    command error_t NeighborDiscovery.start() {
        uint32_t offset; // 
        neighborDiscoveryStarted = TRUE; 
        dbg(NEIGHBOR_CHANNEL, "NeighborDiscovery started\n");
        
        // start the timer with a random offset to avoid synchronization
        offset = call Random.rand16() % 1000;
        call NeighborDiscoveryTimer.startPeriodicAt(offset, 50000); 
        return SUCCESS; 
    }

    command void NeighborDiscovery.checkStartStatus() {
        if (neighborDiscoveryStarted) {
            dbg(NEIGHBOR_CHANNEL, "NeighborDiscovery has been started.\n");
        } else {
            dbg(NEIGHBOR_CHANNEL, "NeighborDiscovery has not been started.\n");
        }
    }

    event void Sender.sendDone(message_t* msg, error_t error) {
        if (error == SUCCESS) {
            dbg(NEIGHBOR_CHANNEL, "Neighbor discovery packet sent successfully\n");
        } else {
            dbg(NEIGHBOR_CHANNEL, "Neighbor discovery packet send failed\n");
        }
    }

    event void NeighborDiscoveryTimer.fired() {
        dbg(NEIGHBOR_CHANNEL, "Sending discovery packet\n");
        
        discoveryCount++; 

        sendPackage.src = TOS_NODE_ID;
        sendPackage.dest = AM_BROADCAST_ADDR;
        sendPackage.seq = sequenceNumber++;
        sendPackage.TTL = MAX_TTL;
        sendPackage.protocol = PROTOCOL_PING;
        memcpy(sendPackage.payload, "DISCOVERY", 10); // payload 

        if (call Sender.send(sendPackage, AM_BROADCAST_ADDR) == SUCCESS) {
            dbg(NEIGHBOR_CHANNEL, "Discovery packet sent successfully\n");
        } else {
            dbg(NEIGHBOR_CHANNEL, "Failed to send discovery packet\n");
        }

        if(discoveryCount >= 5){  // added for LS (discoveryCount)
            dbg("NeighborDiscovery", "Neighbor Discovery Complete\n");
            signal NeighborDiscovery.done();
        }
        checkInactiveNeighbors(); // checks neighbors and update
    }

    // add neighbor / update neighbor 
    void addNeighbor(uint16_t id, uint8_t quality) {
        uint8_t i;

        for (i = 0; i < count; i++) { 
            if (neighborTable[i].neighborID == id) { // already a neighbor 
                neighborTable[i].linkQuality = quality;
                if (quality >= QUALITY_THRESHOLD) {
                    neighborTable[i].isActive = ACTIVE;
                }
                dbg(NEIGHBOR_CHANNEL, "Updated neighbor: ID = %d, Quality = %d\n", id, quality);
                return;
            }
        }

        if (count < MAX_NEIGHBORS) { // If there is more space for new neighbors 
            neighborTable[count].nodeID = TOS_NODE_ID;
            neighborTable[count].neighborID = id;
            neighborTable[count].linkQuality = quality;
            
            if (quality >= QUALITY_THRESHOLD) { 
                neighborTable[count].isActive = ACTIVE;
            } else {
                neighborTable[count].isActive = INACTIVE;
            }
            count++;
            dbg(NEIGHBOR_CHANNEL, "New neighbor added: ID = %d, Quality = %d\n", id, quality);
        } else {
            dbg(NEIGHBOR_CHANNEL, "Neighbor table is full\n");
        }
    }

    void checkInactiveNeighbors() {
        uint8_t i;
        uint8_t j;
        uint8_t activeCount = 0;
        neighbor_t tempTable[MAX_NEIGHBORS]; 

        for (i = 0; i < count; i++) {
            if (neighborTable[i].linkQuality > 0) {
                neighborTable[i].linkQuality -= QUALITY_DECREMENT;
            }

            if (neighborTable[i].linkQuality < QUALITY_THRESHOLD) {
                neighborTable[i].isActive = INACTIVE;
                dbg(NEIGHBOR_CHANNEL, "Neighbor %d marked as inactive\n", neighborTable[i].neighborID);
            }

            if (neighborTable[i].isActive) {
                tempTable[activeCount++] = neighborTable[i]; // Keep active neighbors
            }
        }

        memcpy(neighborTable, tempTable, sizeof(neighbor_t) * activeCount); // Update neighbor table
        count = activeCount; // Update count
    }


    command void NeighborDiscovery.handleNeighbor(uint16_t id, uint8_t quality) {
        uint8_t i;
        for (i = 0; i < count; i++) {
            if (neighborTable[i].neighborID == id) {
                neighborTable[i].linkQuality += QUALITY_INCREMENT;
                if (neighborTable[i].linkQuality > 100) {
                    neighborTable[i].linkQuality = 100;
                }
                neighborTable[i].isActive = ACTIVE;
                dbg(NEIGHBOR_CHANNEL, "Updated neighbor: ID = %d, Quality = %d\n", id, neighborTable[i].linkQuality);
                return;
            }
        }
        addNeighbor(id, quality); // If not found add new neighbor 
    }

    command void NeighborDiscovery.getNeighbor(neighbor_t* tableFlood) {
        uint8_t i;
        for (i = 0; i < count; i++) {
            tableFlood[i] = neighborTable[i];
        }
    }
}