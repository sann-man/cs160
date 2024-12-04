#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module FloodingP {
  uses {
    interface Boot;
    interface Receive;
    interface AMSend;
    interface Timer<TMilli> as FloodingTimer;
    interface Random;
    interface SplitControl as AMControl;
    interface Packet;
    interface AMPacket;
  }
  
  provides interface Flooding;
}


implementation {

    uint16_t sequence = 0;
    bool busy = FALSE; // for radio busy or not busy 
    message_t pkt;

    typedef nx_struct {
    nx_uint16_t src;
    nx_uint16_t seq;
    nx_uint32_t timestamp;
    } FloodingEntry;

    FloodingEntry floodingTable[20];
    uint8_t floodingTableSize = 0; // cur number of entries 

    // function to check if a packet has been seen before
    bool isPacketSeen(uint16_t src, uint16_t seq) {
    uint8_t i;
    uint32_t currentTime = call FloodingTimer.getNow();
    for (i = 0; i < floodingTableSize; i++) {
        if (floodingTable[i].src == src && floodingTable[i].seq == seq) {
            // check if the entry is not too old 
            if (currentTime - floodingTable[i].timestamp < 300000) {
                return TRUE;
            }
        }
    }
    return FALSE; // packet not seen before 
    }

    // function to add a packet to the flooding table
    void addPacketToFloodingTable(uint16_t src, uint16_t seq) {
        uint8_t i;
        uint32_t currentTime = call FloodingTimer.getNow();
        if (floodingTableSize < 20) {
            floodingTable[floodingTableSize].src = src;
            floodingTable[floodingTableSize].seq = seq;
            floodingTable[floodingTableSize].timestamp = currentTime;
            floodingTableSize++; 
        } else {
            // Replace the oldest entry 
            uint8_t oldestIndex = 0;
            uint32_t oldestTime = floodingTable[0].timestamp;
            for (i = 1; i < 20; i++) {
                if (floodingTable[i].timestamp < oldestTime) { // find oldest one 
                    oldestIndex = i;
                    oldestTime = floodingTable[i].timestamp;
                }
            }
            floodingTable[oldestIndex].src = src;
            floodingTable[oldestIndex].seq = seq;
            floodingTable[oldestIndex].timestamp = currentTime;
        }
    }

    // Event handler for receiving a message
   // Updated the flood packet handling for LSA packets
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        if (len == sizeof(pack)) {
            pack* myMsg = (pack*) payload;
            
            if (isPacketSeen(myMsg->src, myMsg->seq)) {
                dbg(FLOODING_CHANNEL, "Node %d already saw this packet, discarding\n", TOS_NODE_ID);
                return msg;
            }
            
            addPacketToFloodingTable(myMsg->src, myMsg->seq); // Track the packet
            
            if (myMsg->TTL > 0) { 
                myMsg->TTL--;  // Decrease TTL
                if (!busy && call AMSend.send(AM_BROADCAST_ADDR, msg, sizeof(pack)) == SUCCESS) {
                    busy = TRUE;
                    dbg(FLOODING_CHANNEL, "Node %d: Forwarding LSA packet\n", TOS_NODE_ID);
                }
            } else {
                dbg(FLOODING_CHANNEL, "Node %d: TTL expired, dropping LSA packet\n", TOS_NODE_ID);
            }
        }
        return msg;
    }


    event void AMSend.sendDone(message_t* msg, error_t error) {
        if (&pkt == msg) {
            busy = FALSE; // radio us no longer busy 
            dbg(FLOODING_CHANNEL, "Node %d: Send completed with status %d\n", TOS_NODE_ID, error);
        }
    }

    // send flooding packet
    command error_t Flooding.send(pack msg, uint16_t dest) {
    dbg(FLOODING_CHANNEL, "Node %d: Entering Flooding.send() for dest %d\n", TOS_NODE_ID, dest);

    if (!busy) {
        pack* payload = (pack*)(call Packet.getPayload(&pkt, sizeof(pack)));
        if (payload == NULL) {
            dbg(FLOODING_CHANNEL, "Node %d: Failed to get payload\n", TOS_NODE_ID);
            return FAIL;
        }
        
        memcpy(payload, &msg, sizeof(pack)); // copy message to payload 
        payload->src = TOS_NODE_ID;
        payload->dest = dest;
        payload->seq = sequence++;
        payload->TTL = MAX_TTL;

        if (call AMSend.send(AM_BROADCAST_ADDR, &pkt, sizeof(pack)) == SUCCESS) {
            busy = TRUE;
            dbg(FLOODING_CHANNEL, "Node %d: Flooding initiated, seq %d\n", TOS_NODE_ID, payload->seq);
            return SUCCESS;
        } else {
            dbg(FLOODING_CHANNEL, "Node %d: AMSend.send() failed\n", TOS_NODE_ID);
            return FAIL;
        }
    } else {
        dbg(FLOODING_CHANNEL, "Node %d: Radio busy, cannot send\n", TOS_NODE_ID);
    }
    return EBUSY;
    }

    // ---- Start flooding --------- 
    command error_t Flooding.start() {
        // call FloodingTimer.startPeriodic(60000 + (call Random.rand16() % 10000));  // Start timer for periodic flooding test
        call FloodingTimer.startPeriodic(50000);
        dbg(FLOODING_CHANNEL, "Node %d: Flooding started\n", TOS_NODE_ID);
        return SUCCESS;
    }

    event void FloodingTimer.fired() {
        pack testPacket;
        dbg(FLOODING_CHANNEL, "Node %d: FloodingTimer fired, initiating test flood\n", TOS_NODE_ID);

        testPacket.src = TOS_NODE_ID;
        testPacket.dest = AM_BROADCAST_ADDR;
        testPacket.seq = sequence;
        testPacket.TTL = MAX_TTL;
        testPacket.protocol = PROTOCOL_PING;
        memcpy(testPacket.payload, "Test Flood", 10);  // copy payload data 

        call Flooding.send(testPacket, AM_BROADCAST_ADDR); // send test packet 
    }

    event void AMControl.startDone(error_t err) {
        if (err == SUCCESS) {
            dbg(FLOODING_CHANNEL, "Node %d: Radio on!\n", TOS_NODE_ID);
            call Flooding.start();
        } else {
            call AMControl.start();
        }
    }

    event void AMControl.stopDone(error_t err) {
    // Do nothing
    }

    event void Boot.booted() {
        dbg(FLOODING_CHANNEL, "Node %d: Booted\n", TOS_NODE_ID);
        call AMControl.start();
    }
}