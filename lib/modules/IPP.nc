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
        call LinkState.getRouteTable(routingTable, &routingTableSize);
        
        dbg(ROUTING_CHANNEL, "Node %d: Updated routing table with %d entries\n", 
            TOS_NODE_ID, routingTableSize);
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

        // Create a copy of the message to send
        memcpy(&sendPackage, &message, sizeof(pack));

        dbg(ROUTING_CHANNEL, "Node %d: Attempting to send packet src:%d dest:%d protocol:%d TTL:%d\n", 
            TOS_NODE_ID, sendPackage.src, sendPackage.dest, sendPackage.protocol, sendPackage.TTL);

        // Handle broadcast and special protocol packets
        if(sendPackage.dest == AM_BROADCAST_ADDR || 
           sendPackage.protocol == PROTOCOL_LINKSTATE || 
           sendPackage.protocol == PROTOCOL_PING) {
            dbg(ROUTING_CHANNEL, "Node %d: Broadcasting packet protocol=%d\n", 
                TOS_NODE_ID, sendPackage.protocol);
            return call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        }

        // Check TTL
        if(sendPackage.TTL == 0) {
            dbg(ROUTING_CHANNEL, "Node %d: Dropping packet - TTL expired\n", TOS_NODE_ID);
            return FAIL;
        }

        // Update routing table before looking up route
        updateRoutingTable();

        // Find next hop in routing table
        for(i = 0; i < routingTableSize; i++) {
            if(routingTable[i].dest == sendPackage.dest) {
                nextHop = routingTable[i].nextHop;
                routeFound = TRUE;
                break;
            }
        }

        if(!routeFound) {
            dbg(ROUTING_CHANNEL, "Node %d: No route to destination %d\n", 
                TOS_NODE_ID, sendPackage.dest);
            return FAIL;
        }

        // Decrease TTL
        sendPackage.TTL--;
        
        // Send to next hop
        sendResult = call Sender.send(sendPackage, nextHop);
        
        if(sendResult == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: Successfully forwarded packet to next hop %d\n", 
                TOS_NODE_ID, nextHop);
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Failed to forward packet to next hop %d\n", 
                TOS_NODE_ID, nextHop);
        }
            
        return sendResult;
    }

    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* receivedMsg;

        if(len != sizeof(pack)) return msg;

        receivedMsg = (pack*)payload;

        dbg(ROUTING_CHANNEL, "Node %d: Received packet - src:%d dest:%d protocol:%d TTL:%d\n", 
            TOS_NODE_ID, receivedMsg->src, receivedMsg->dest, receivedMsg->protocol, receivedMsg->TTL);

        // Handle packet based on protocol
        switch(receivedMsg->protocol) {
            case PROTOCOL_LINKSTATE:
                dbg(ROUTING_CHANNEL, "Node %d: Processing LINKSTATE packet\n", TOS_NODE_ID);
                signal IP.receive(receivedMsg);
                break;
                
            case PROTOCOL_PING:
            case PROTOCOL_PINGREPLY:
                if(receivedMsg->dest == TOS_NODE_ID || 
                   receivedMsg->dest == AM_BROADCAST_ADDR) {
                    dbg(ROUTING_CHANNEL, "Node %d: Processing PING/REPLY packet\n", TOS_NODE_ID);
                    signal IP.receive(receivedMsg);
                } else if(receivedMsg->TTL > 0) {
                    // Forward the packet
                    pack forwardPack = *receivedMsg;
                    forwardPack.TTL--;
                    call IP.send(forwardPack);
                }
                break;
                
            default:
                if(receivedMsg->dest == TOS_NODE_ID) {
                    signal IP.receive(receivedMsg);
                } else if(receivedMsg->TTL > 0) {
                    pack forwardPack = *receivedMsg;
                    call IP.send(forwardPack);
                }
                break;
        }

        return msg;
    }

    event void Sender.sendDone(message_t* msg, error_t error) {
        if(error == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: Packet sent successfully\n", TOS_NODE_ID);
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Failed to send packet\n", TOS_NODE_ID);
        }
    }
}