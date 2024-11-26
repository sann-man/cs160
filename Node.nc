#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"
#include "includes/NeighborTable.h"
#include "includes/RoutingTable.h"

module Node {
   uses interface Boot;
   uses interface SplitControl as AMControl;
   uses interface Receive;
   uses interface SimpleSend as Sender;
   uses interface CommandHandler;
   uses interface NeighborDiscovery;
   uses interface Flooding;
   uses interface Timer<TMilli> as NeighborDiscoveryTimer;
   uses interface LinkState; 
   uses interface IP; 
}

implementation {
   pack sendPackage;
   uint16_t sequenceNumber = 0;
   neighbor_t neighborTable[MAX_NEIGHBORS];
   uint8_t neighborCount = 0;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted() {
      call AMControl.start();
      dbg(GENERAL_CHANNEL, "Booted\n");

      // Start neighbor discovery
      if (call NeighborDiscovery.start() == SUCCESS) {
         dbg("NeighborDiscovery", "NeighborDiscovery start command was successful.\n");
      } else {
         dbg("NeighborDiscovery", "NeighborDiscovery start command failed.\n");
      }

      if (call Flooding.start() == SUCCESS) {
         dbg("Flooding", "Flooding start command was successful.\n");
      } else {
         dbg("Flooding", "Flooding start command failed.\n");
      }

      // LinkState start
      if (call LinkState.start() == SUCCESS) {
         dbg(ROUTING_CHANNEL, "LinkState start command was successful.\n");
      } else {
         dbg(ROUTING_CHANNEL, "LinkState start command failed.\n");
      }

      // IP layer
      // Start IP
      if (call IP.start() == SUCCESS) {
         dbg(ROUTING_CHANNEL, "IP start command was successful.\n");
      } else {
         dbg(ROUTING_CHANNEL, "IP start command failed.\n");
      }

      // Start the neighbor discovery timer
      call NeighborDiscoveryTimer.startPeriodic(50000);
   }

   event void AMControl.startDone(error_t err) {
      if (err == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Radio On\n");
      } else {
         //Retry until successful
         call AMControl.start();
      }
   }

   event void NeighborDiscovery.done(){
      dbg(GENERAL_CHANNEL, "Neighbor Discovery DONE\n");
      // LinkState.floodLSA();
   }

   event void AMControl.stopDone(error_t err) {}

   event void Sender.sendDone(message_t* msg, error_t error) {
      // if (error == SUCCESS) {
      //    dbg(GENERAL_CHANNEL, "Packet sent successfully\n");
      // } else {
      //    dbg(GENERAL_CHANNEL, "Packet send failed\n");
      // }
   }

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len) {
      if (len == sizeof(pack)) {
         pack* myMsg = (pack*) payload;
         // dbg(GENERAL_CHANNEL, "Package Received from %d\n", myMsg->src);

         if (myMsg->type == TYPE_REQUEST) {
            // Handle neighbor discovery request
            dbg(NEIGHBOR_CHANNEL, "Received payload from %d\n", myMsg->src);

            // Send reply message
            sendPackage.src = TOS_NODE_ID;
            sendPackage.dest = myMsg->src;
            sendPackage.type = TYPE_REPLY;
            sendPackage.protocol = PROTOCOL_PING;
            memcpy(sendPackage.payload, "REPLY", 5);

            if (call Sender.send(sendPackage, myMsg->src) == SUCCESS) {
               dbg(NEIGHBOR_CHANNEL, "Reply sent to %d\n", myMsg->src);
            }

            // Add or update neighbor
            call NeighborDiscovery.handleNeighbor(myMsg->src, 100);
         } else if (myMsg->type == TYPE_REPLY) {
            // Handle neighbor discovery reply
            dbg(NEIGHBOR_CHANNEL, "Received REPLY from %d\n", myMsg->src);
            call NeighborDiscovery.handleNeighbor(myMsg->src, 100);
         }

         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }

   event void IP.receive(pack* msg) {
      dbg(ROUTING_CHANNEL, "Node %d: Received IP packet from %d with protocol %d\n", 
         TOS_NODE_ID, msg->src, msg->protocol);
         
      switch(msg->protocol) {
         case PROTOCOL_PING:
               // Handle ping packets
               dbg(GENERAL_CHANNEL, "Ping received from %d\n", msg->src);
               // Create ping reply
               makePack(&sendPackage, TOS_NODE_ID, msg->src, MAX_TTL, 
                     PROTOCOL_PINGREPLY, sequenceNumber++, 
                     (uint8_t*)"PING REPLY", PACKET_MAX_PAYLOAD_SIZE);
               // Changed from (&sendPackage, msg->src) to just sendPackage
               call IP.send(sendPackage);
               break;
               
         case PROTOCOL_PINGREPLY:
               dbg(GENERAL_CHANNEL, "Ping Reply from %d\n", msg->src);
               break;
               
         default:
               dbg(GENERAL_CHANNEL, "Unknown protocol %d\n", msg->protocol);
               break;
      }
   }

   event void NeighborDiscoveryTimer.fired() {
      
      // Prepare message
      makePack(&sendPackage, TOS_NODE_ID, AM_BROADCAST_ADDR, 1, PROTOCOL_PING, 0, (uint8_t*)"Payload", PACKET_MAX_PAYLOAD_SIZE);
      sendPackage.type = TYPE_REQUEST;

      // Send the package
      if (call Sender.send(sendPackage, AM_BROADCAST_ADDR) == SUCCESS) {
         dbg(NEIGHBOR_CHANNEL, "package sent successfully\n");
      } else {
         dbg(NEIGHBOR_CHANNEL, "Failed to send msg\n");
      }
   }

   event void CommandHandler.ping(uint16_t destination, uint8_t *payload) {
      dbg(GENERAL_CHANNEL, "Node %d: Initiating ping to Node %d\n", TOS_NODE_ID, destination);
      
      makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, 
               PROTOCOL_PING, sequenceNumber++, 
               payload, PACKET_MAX_PAYLOAD_SIZE);
               
      if(call IP.send(sendPackage) == SUCCESS) {
         dbg(GENERAL_CHANNEL, "Node %d: Successfully initiated ping to %d\n", 
               TOS_NODE_ID, destination);
      } else {
         dbg(GENERAL_CHANNEL, "Node %d: Failed to initiate ping to %d\n", 
               TOS_NODE_ID, destination);
      }
   }


   event void CommandHandler.printNeighbors() {
      uint8_t i;
      for (i = 0; i < neighborCount; i++) {
         dbg(NEIGHBOR_CHANNEL, "Neighbor: %d, Quality: %d, Active: %d\n", 
             neighborTable[i].neighborID, 
             neighborTable[i].linkQuality, 
             neighborTable[i].isActive);
      }
   }

   event void CommandHandler.printRouteTable() {
      routing_t routeTable[MAX_NODES];
      uint8_t tableSize;
      uint8_t i;

      // get the routing table from LinkState
      call LinkState.getRouteTable(routeTable, &tableSize);
      
      dbg(ROUTING_CHANNEL, "Node %d Routing Table:\n", TOS_NODE_ID);
      dbg(ROUTING_CHANNEL, "Dest\tNextHop\tCost\n");
      
      for(i = 0; i < tableSize; i++) {
         dbg(ROUTING_CHANNEL, "%d\t%d\t%d\n", 
               routeTable[i].dest,
               routeTable[i].nextHop,
               routeTable[i].cost);
      }

      if(tableSize == 0) {
         dbg(ROUTING_CHANNEL, "Node %d: Routing table is empty\n", TOS_NODE_ID);
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