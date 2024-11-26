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

    command error_t IP.start() {
        dbg(ROUTING_CHANNEL, "Node %d: Starting IP module\n", TOS_NODE_ID);
        return SUCCESS;
    }

    // modified the send command:
    command error_t IP.send(pack message) {
        error_t sendResult;
        uint16_t nextHop = 0;
        bool routeFound = FALSE;
        pack sendPackage;
        uint8_t i;

        // get new routing table
        call LinkState.getRouteTable(routingTable, &routingTableSize);

        dbg(ROUTING_CHANNEL, "Node %d: Attempting to route packet src:%d dest:%d protocol:%d TTL:%d\n", 
            TOS_NODE_ID, message.src, message.dest, message.protocol, message.TTL);

        if(message.dest == AM_BROADCAST_ADDR) {
            memcpy(&sendPackage, &message, sizeof(pack));
            return call Sender.send(sendPackage, AM_BROADCAST_ADDR);
        }

        // log routing decision
        dbg(ROUTING_CHANNEL, "Node %d: checking routing table (%d entries):\n", 
            TOS_NODE_ID, routingTableSize);
        for(i = 0; i < routingTableSize; i++) {
            dbg(ROUTING_CHANNEL, "\tDest: %d, NextHop: %d, Cost: %d\n",
                routingTable[i].dest, routingTable[i].nextHop, routingTable[i].cost);
        }

        // find next hop
        for(i = 0; i < routingTableSize; i++) {
            if(routingTable[i].dest == message.dest) {
                nextHop = routingTable[i].nextHop;
                routeFound = TRUE;
                dbg(ROUTING_CHANNEL, "Node %d: Found route to %d via %d (cost %d)\n",
                    TOS_NODE_ID, message.dest, nextHop, routingTable[i].cost);
                break;
            }
        }

        if(!routeFound) {
            dbg(ROUTING_CHANNEL, "Node %d: No route to destination %d\n", 
                TOS_NODE_ID, message.dest);
            return FAIL;
        }

        if(message.TTL == 0) {
            dbg(ROUTING_CHANNEL, "Node %d: TTL expired\n", TOS_NODE_ID);
            return FAIL;
        }

        memcpy(&sendPackage, &message, sizeof(pack));
        sendPackage.TTL--;
        
        sendResult = call Sender.send(sendPackage, nextHop);
        dbg(ROUTING_CHANNEL, "Node %d: Forwarded packet to %d (result: %d)\n", 
            TOS_NODE_ID, nextHop, sendResult);
            
        return sendResult;
    }

    // recieve 
    event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
        pack* receivedMsg;
        pack forwardPack;

        if(len != sizeof(pack)) return msg;

        receivedMsg = (pack*)payload;

        dbg(ROUTING_CHANNEL, "Node %d: IP received packet - src:%d dest:%d protocol:%d TTL:%d\n", 
            TOS_NODE_ID, receivedMsg->src, receivedMsg->dest, receivedMsg->protocol, receivedMsg->TTL);

        if(receivedMsg->TTL == 0) {
            dbg(ROUTING_CHANNEL, "Node %d: Dropping packet - TTL expired\n", TOS_NODE_ID);
            return msg;
        }

        if(receivedMsg->dest == TOS_NODE_ID || receivedMsg->dest == AM_BROADCAST_ADDR) {
            dbg(ROUTING_CHANNEL, "Node %d: Packet reached destination\n", TOS_NODE_ID);
            signal IP.receive(receivedMsg);
            return msg;
        }

        memcpy(&forwardPack, receivedMsg, sizeof(pack));
        forwardPack.TTL = receivedMsg->TTL - 1;

        dbg(ROUTING_CHANNEL, "Node %d: Forwarding packet from %d to %d (TTL=%d)\n",
            TOS_NODE_ID, forwardPack.src, forwardPack.dest, forwardPack.TTL);

        if(call IP.send(forwardPack) == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: Successfully initiated forward\n", TOS_NODE_ID);
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Failed to forward packet\n", TOS_NODE_ID);
        }

        return msg;
    }

    // send done
    event void Sender.sendDone(message_t* msg, error_t error) {
        if(error == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: IP packet sent successfully\n", TOS_NODE_ID);
        } else {
            dbg(ROUTING_CHANNEL, "Node %d: Failed to send IP packet\n", TOS_NODE_ID);
        }
    }
}