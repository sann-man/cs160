#ifndef NEIGHBOR_TABLE_H
#define NEIGHBOR_TABLE_H

#include <stdint.h>

// Define constants
#define MAX_NEIGHBORS 20 // Maximum number of neighbors to track
#define ACTIVE 1
#define INACTIVE 0
#define MAX_TTL 1
#define NEIGHBOR_TIMEOUT 300000 // time that node can be INACTIVE for before being removed
#define QUALITY_THRESHOLD 50 // min quality amount for neighbor to be active
#define QUALITY_INCREMENT 10
#define QUALITY_DECREMENT 5 // used when node not seen

// Define the structure for neighbor information
typedef struct {
    uint16_t nodeID;
    uint16_t neighborID;  // ID of the neighbor
    uint16_t linkQuality;  // Link quality 
    uint16_t isActive;     // status of the link (ACTIVE/INACTIVE)
  
} neighbor_t;


#endif 

// NEIGHBOR_TABLE_H
