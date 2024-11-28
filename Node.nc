#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/NeighborTable.h"
#include "includes/RoutingTable.h"

module Node {
   uses {
       interface Boot;
       interface SplitControl as AMControl;
       interface Receive;
       interface SimpleSend as Sender;
       interface CommandHandler;
       interface NeighborDiscovery;
       interface Flooding;
       interface Timer<TMilli> as NeighborDiscoveryTimer;
       interface LinkState;
       interface IP;
       interface Hashmap<uint32_t> as Seen;
   }
}

implementation {
   pack sendPackage;
   uint16_t sequenceNumber = 0;
   neighbor_t neighborTable[MAX_NEIGHBORS];
   uint8_t neighborCount = 0;
   bool initialized = FALSE;

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted() {
      call AMControl.start();
      dbg(GENERAL_CHANNEL, "Node %d: Booted\n", TOS_NODE_ID);
   }

   event void AMControl.startDone(error_t err) {
      if (err == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Node %d: Radio On\n", TOS_NODE_ID);
         initialized = TRUE;
         
         if (call NeighborDiscovery.start() == SUCCESS) {
            dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor Discovery started\n", TOS_NODE_ID);
         }
         
         if (call Flooding.start() == SUCCESS) {
            dbg(FLOODING_CHANNEL, "Node %d: Flooding started\n", TOS_NODE_ID);
         }
         
         if (call LinkState.start() == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: Link State started\n", TOS_NODE_ID);
         }
         
         if (call IP.start() == SUCCESS) {
            dbg(ROUTING_CHANNEL, "Node %d: IP started\n", TOS_NODE_ID);
         }
      } else {
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err) {}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      pack* myMsg;
      
      if (len != sizeof(pack)) return msg;
      myMsg = (pack*) payload;
      
      dbg(GENERAL_CHANNEL, "Node %d: Received packet from %d\n", TOS_NODE_ID, myMsg->src);

      switch(myMsg->protocol) {
         case PROTOCOL_PING:
            dbg(GENERAL_CHANNEL, "Node %d: PING packet received from %d\n", TOS_NODE_ID, myMsg->src);
            
            if(myMsg->dest == AM_BROADCAST_ADDR) {
               call NeighborDiscovery.handleNeighbor(myMsg->src, 100);
               
               makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, 
                       PROTOCOL_PINGREPLY, sequenceNumber++, 
                       (uint8_t*)"REPLY", PACKET_MAX_PAYLOAD_SIZE);
               
               call IP.send(sendPackage);
            } else if(myMsg->dest == TOS_NODE_ID) {
               signal IP.receive(myMsg);
            }
            break;

         case PROTOCOL_PINGREPLY:
            dbg(GENERAL_CHANNEL, "Node %d: PINGREPLY received from %d\n", TOS_NODE_ID, myMsg->src);
            call NeighborDiscovery.handleNeighbor(myMsg->src, 100);
            signal IP.receive(myMsg);
            break;

         case PROTOCOL_LINKSTATE:
            dbg(ROUTING_CHANNEL, "Node %d: LINKSTATE packet received from %d\n", TOS_NODE_ID, myMsg->src);
            signal IP.receive(myMsg);
            break;

         default:
            dbg(GENERAL_CHANNEL, "Node %d: Unknown protocol %d from %d\n", 
                TOS_NODE_ID, myMsg->protocol, myMsg->src);
            break;
      }
      return msg;
   }

   event void IP.receive(pack* msg) {
      switch(msg->protocol) {
         case PROTOCOL_PING:
            dbg(GENERAL_CHANNEL, "Node %d: Processing ping from %d\n", TOS_NODE_ID, msg->src);
            makePack(&sendPackage, TOS_NODE_ID, msg->src, MAX_TTL, 
                  PROTOCOL_PINGREPLY, sequenceNumber++, 
                  (uint8_t*)"PING REPLY", PACKET_MAX_PAYLOAD_SIZE);
            call IP.send(sendPackage);
            break;
            
         case PROTOCOL_PINGREPLY:
            dbg(GENERAL_CHANNEL, "Node %d: Processing ping reply from %d\n", TOS_NODE_ID, msg->src);
            break;
            
         case PROTOCOL_LINKSTATE:
            dbg(ROUTING_CHANNEL, "Node %d: Processing LSA from %d\n", TOS_NODE_ID, msg->src);
            call LinkState.floodLSA();
            break;
      }
   }

   event void Sender.sendDone(message_t* msg, error_t error) {
      if(error == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Node %d: Packet sent successfully\n", TOS_NODE_ID);
      } else {
         dbg(GENERAL_CHANNEL, "Node %d: Failed to send packet\n", TOS_NODE_ID);
      }
   }

   event void NeighborDiscoveryTimer.fired() {
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, 
               PROTOCOL_PING, sequenceNumber++, 
               (uint8_t*)"DISCOVERY", PACKET_MAX_PAYLOAD_SIZE);
      
      if (call Sender.send(sendPackage, AM_BROADCAST_ADDR) == SUCCESS) {
         dbg(NEIGHBOR_CHANNEL, "Node %d: Discovery packet sent\n", TOS_NODE_ID);
      }
   }

   event void NeighborDiscovery.done() {
      dbg(GENERAL_CHANNEL, "Node %d: Neighbor Discovery complete\n", TOS_NODE_ID);
      call LinkState.floodLSA();
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
      dbg(GENERAL_CHANNEL, "Node %d: Sending ping to %d\n", TOS_NODE_ID, destination);
      
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 
               PROTOCOL_PING, sequenceNumber++, 
               payload, PACKET_MAX_PAYLOAD_SIZE);
      
      call IP.send(sendPackage);
   }

   event void CommandHandler.printNeighbors() {
      uint8_t i;
      neighbor_t neighbors[MAX_NEIGHBORS];
      call NeighborDiscovery.getNeighbor(neighbors);
      
      dbg(NEIGHBOR_CHANNEL, "Node %d: Neighbor List:\n", TOS_NODE_ID);
      for(i = 0; i < MAX_NEIGHBORS; i++) {
         if(neighbors[i].isActive) {
            dbg(NEIGHBOR_CHANNEL, "\tNeighbor %d: Quality %d\n", 
                neighbors[i].neighborID, neighbors[i].linkQuality);
         }
      }
   }

   event void CommandHandler.printRouteTable() {
      routing_t routeTable[MAX_NODES];
      uint8_t tableSize;
      uint8_t i;

      call LinkState.getRouteTable(routeTable, &tableSize);
      
      if(tableSize == 0) {
         dbg(ROUTING_CHANNEL, "Node %d: No routes in table\n", TOS_NODE_ID);
         return;
      }
      
      dbg(ROUTING_CHANNEL, "Node %d Routing Table:\n", TOS_NODE_ID);
      dbg(ROUTING_CHANNEL, "   Dest\tNext\tCost\n");
      dbg(ROUTING_CHANNEL, "   ----\t----\t----\n");
      
      for(i = 0; i < tableSize; i++) {
         dbg(ROUTING_CHANNEL, "   %d\t%d\t%d\n", 
               routeTable[i].dest,
               routeTable[i].nextHop,
               routeTable[i].cost);
      }
   }

   event void CommandHandler.printLinkState() {}
   event void CommandHandler.printDistanceVector() {}
   event void CommandHandler.setTestServer() {}
   event void CommandHandler.setTestClient() {}
   event void CommandHandler.setAppServer() {}
   event void CommandHandler.setAppClient() {}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}