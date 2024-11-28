#include "../../includes/packet.h"
#include "../../includes/channels.h"
#include "../../includes/NeighborTable.h"

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses {
        interface SimpleSend as Sender;
        interface Timer<TMilli> as NeighborDiscoveryTimer;
        interface Random;
    }
}

implementation {
    pack sendPackage;
    neighbor_t neighborTable[MAX_NEIGHBORS]; 
    uint8_t count = 0;
    bool neighborDiscoveryStarted = FALSE;
    uint16_t sequenceNumber = 0;
    uint8_t discoveryCount = 0;

    void checkInactiveNeighbors() {
        uint8_t i;
        uint8_t j = 0;
        neighbor_t tempTable[MAX_NEIGHBORS];

        dbg(NEIGHBOR_CHANNEL, "Node %d: Checking inactive neighbors\n", TOS_NODE_ID);

        // First pass: Update link qualities and check active status
        for(i = 0; i < count; i++) {
            if(neighborTable[i].linkQuality > 0) {
                neighborTable[i].linkQuality -= QUALITY_DECREMENT;
            }

            if(neighborTable[i].linkQuality < QUALITY_THRESHOLD) {
                neighborTable[i].isActive = INACTIVE;
                dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor %d marked inactive (quality: %d)\n", 
                    TOS_NODE_ID, neighborTable[i].neighborID, neighborTable[i].linkQuality);
            }
        }

        // Second pass: Keep only active neighbors or those with non-zero quality
        for(i = 0; i < count; i++) {
            if(neighborTable[i].isActive == ACTIVE || neighborTable[i].linkQuality > 0) {
                tempTable[j] = neighborTable[i];
                j++;
            } else {
                dbg(NEIGHBOR_CHANNEL, "Node %d: Removing inactive neighbor %d\n", 
                    TOS_NODE_ID, neighborTable[i].neighborID);
            }
        }

        // Update table
        memcpy(neighborTable, tempTable, sizeof(neighbor_t) * j);
        count = j;
        
        dbg(NEIGHBOR_CHANNEL, "Node %d: Active neighbors after cleanup: %d\n", 
            TOS_NODE_ID, count);
    }

    void addNeighbor(uint16_t id, uint8_t quality) {
        uint8_t i;
        bool updated = FALSE;

        // Update existing neighbor if found
        for(i = 0; i < count; i++) {
            if(neighborTable[i].neighborID == id) {
                neighborTable[i].linkQuality += QUALITY_INCREMENT;
                if(neighborTable[i].linkQuality > 100) {
                    neighborTable[i].linkQuality = 100;
                }
                neighborTable[i].isActive = ACTIVE;
                updated = TRUE;
                dbg(NEIGHBOR_CHANNEL, "Node %d: Updated neighbor %d quality to %d\n",
                    TOS_NODE_ID, id, neighborTable[i].linkQuality);
                break;
            }
        }

        // Add new neighbor if not found and there's space
        if(!updated && count < MAX_NEIGHBORS) {
            neighborTable[count].nodeID = TOS_NODE_ID;
            neighborTable[count].neighborID = id;
            neighborTable[count].linkQuality = quality;
            neighborTable[count].isActive = (quality >= QUALITY_THRESHOLD) ? ACTIVE : INACTIVE;
            count++;
            dbg(NEIGHBOR_CHANNEL, "Node %d: Added new neighbor %d with quality %d\n",
                TOS_NODE_ID, id, quality);
        }
    }

    command error_t NeighborDiscovery.start() {
        uint32_t offset = call Random.rand16() % 1000;
        
        if(!neighborDiscoveryStarted) {
            neighborDiscoveryStarted = TRUE;
            dbg(NEIGHBOR_CHANNEL, "Node %d: Starting neighbor discovery (offset: %d)\n", 
                TOS_NODE_ID, offset);
            call NeighborDiscoveryTimer.startPeriodicAt(offset, 50000);
            return SUCCESS;
        }
        return FAIL;
    }

    command void NeighborDiscovery.checkStartStatus() {
        dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor discovery status: %s\n",
            TOS_NODE_ID, neighborDiscoveryStarted ? "Started" : "Not Started");
    }

    command void NeighborDiscovery.handleNeighbor(uint16_t id, uint8_t quality) {
        addNeighbor(id, quality);
        discoveryCount++;
        
        if(discoveryCount >= 5) {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor discovery round complete\n", TOS_NODE_ID);
            signal NeighborDiscovery.done();
            discoveryCount = 0;
        }
    }

    command void NeighborDiscovery.getNeighbor(neighbor_t* tableToFill) {
        uint8_t i;
        for(i = 0; i < count; i++) {
            tableToFill[i] = neighborTable[i];
        }
    }

    event void NeighborDiscoveryTimer.fired() {
        sendPackage.src = TOS_NODE_ID;
        sendPackage.dest = AM_BROADCAST_ADDR;
        sendPackage.seq = sequenceNumber++;
        sendPackage.TTL = 1;  // Only immediate neighbors should receive this
        sendPackage.protocol = PROTOCOL_PING;
        memcpy(sendPackage.payload, "DISCOVERY", 10);

        if(call Sender.send(sendPackage, AM_BROADCAST_ADDR) == SUCCESS) {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Sent discovery packet (seq: %d)\n", 
                TOS_NODE_ID, sendPackage.seq);
        }

        checkInactiveNeighbors();
    }

    event void Sender.sendDone(message_t* msg, error_t error) {
        if(error == SUCCESS) {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Discovery packet sent successfully\n", TOS_NODE_ID);
        } else {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Failed to send discovery packet\n", TOS_NODE_ID);
        }
    }
}