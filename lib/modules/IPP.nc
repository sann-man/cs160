#include "../../includes/packet.h"
#include "../../includes/RoutingTable.h"
#include "../../includes/channels.h"

module IPP {
    provides interface IP;
    
    uses {
        interface SimpleSend as Sender;
        interface Receive;
        interface LinkState;
    }
}

implementation {
    routing_t routingTable[MAX_NODES];
    uint8_t routingTableSize = 0;

    // Function to update routing table
    void updateRoutingTable() {
        uint8_t i;
        
        call LinkState.getRouteTable(routingTable, &routingTableSize);
        
        dbg(ROUTING_CHANNEL, "Node %d: Updated routing table with %d entries:\n", 
            TOS_NODE_ID, routingTableSize);
        
        for(i = 0; i < routingTableSize; i++) {
            dbg(ROUTING_CHANNEL, "\tDest: %d, NextHop: %d, Cost: %d\n",
                routingTable[i].dest, routingTable[i].nextHop, routingTable[i].cost);
        }
    }

    command error_t IP.start() {
        dbg(ROUTING_CHANNEL, "Node %d: Starting IP module\n", TOS_NODE_ID);
        updateRoutingTable();
        return SUCCESS;
    }

    command error_t IP.send(pack message) {
        error_t sendResult;
        uint16_t nextHop = 0;
        bool routeFound = FALSE;
        pack sendPackage;
        uint8_t i;

        // Update routing table before sending
        updateRoutingTable();

        // Create a copy of the message to send
        memcpy(&sendPackage, &message, sizeof(pack));

        dbg(ROUTING_CHANNEL, "Node %d: Attempting to route packet src:%d dest:%d protocol:%d TTL:%d\n", 
            TOS_NODE_ID, sendPackage.src, sendPackage.dest, sendPackage.protocol, sendPackage.TTL);

        // Handle broadcast packets differently
        if(sendPackage.protocol == PROTOCOL_LINKSTATE || 
           sendPackage.protocol == PROTOCOL_PING || 
           sendPackage.dest == AM_BROADCAST_ADDR) {
            dbg(ROUTING_CHANNEL, "Node %d: Broadcasting packet (protocol=%d)\n", 
                TOS_NODE_ID, sendPackage.protocol);
            return call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        }

        // Check TTL
        if(sendPackage.TTL == 0) {
            dbg(ROUTING_CHANNEL, "Node %d: TTL expired\n", TOS_NODE_ID);
            return FAIL;
        }

        // Find next hop in routing table
        for(i = 0; i < routingTableSize; i++) {
            if(routingTable[i].dest == sendPackage.dest) {
                nextHop = routingTable[i].nextHop;
                routeFound = TRUE;
                dbg(ROUTING_CHANNEL, "Node %d: Found route to %d via %d (cost %d)\n",
                    TOS_NODE_ID, sendPackage.dest, nextHop, routingTable[i].cost);
                break;
            }
        }

        if(!routeFound) {
            dbg(ROUTING_CHANNEL, "Node %d: No route to destination %d\n", 
                TOS_NODE_ID, sendPackage.dest);
            return FAIL;
        }

        // Decrease TTL before forwarding
        sendPackage.TTL--;
        
        // Send to next hop
        sendResult = call Sender.send(sendPackage, nextHop);
        
        if(sendResult == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: Forwarded packet to %d\n", 
                TOS_NODE_ID, nextHop);
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Failed to forward packet to %d\n", 
                TOS_NODE_ID, nextHop);
        }
            
        return sendResult;
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* receivedMsg;
        pack forwardPack;

        if(len != sizeof(pack)) return msg;

        receivedMsg = (pack*)payload;

        dbg(ROUTING_CHANNEL, "Node %d: IP received packet - src:%d dest:%d protocol:%d TTL:%d\n", 
            TOS_NODE_ID, receivedMsg->src, receivedMsg->dest, receivedMsg->protocol, receivedMsg->TTL);

        // Process link state packets
        if(receivedMsg->protocol == PROTOCOL_LINKSTATE) {
            signal IP.receive(receivedMsg);  // Process locally
            if(receivedMsg->TTL > 0) {
                // Forward link state packets
                memcpy(&forwardPack, receivedMsg, sizeof(pack));
                forwardPack.TTL--;
                call Sender.send(forwardPack, AM_BROADCAST_ADDR);
            }
            return msg;
        }

        // Check if packet is for us or broadcast
        if(receivedMsg->dest == TOS_NODE_ID || receivedMsg->dest == AM_BROADCAST_ADDR) {
            dbg(ROUTING_CHANNEL, "Node %d: Packet reached destination\n", TOS_NODE_ID);
            signal IP.receive(receivedMsg);
            return msg;
        }

        // Forward packet if TTL allows
        if(receivedMsg->TTL > 0) {
            memcpy(&forwardPack, receivedMsg, sizeof(pack));
            if(call IP.send(forwardPack) == SUCCESS) {
                dbg(ROUTING_CHANNEL, "Node %d: Successfully forwarded packet\n", TOS_NODE_ID);
            } else {
                dbg(ROUTING_CHANNEL, "Node %d: Failed to forward packet\n", TOS_NODE_ID);
            }
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Dropping packet - TTL expired\n", TOS_NODE_ID);
        }

        return msg;
    }

    event void Sender.sendDone(message_t* msg, error_t error) {
        if(error == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: IP packet sent successfully\n", TOS_NODE_ID);
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Failed to send IP packet\n", TOS_NODE_ID);
        }
    }
}