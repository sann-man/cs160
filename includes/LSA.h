#ifndef LSA_H
#define LSA_H

#include <AM.h>
#include "packet.h"
#include "NeighborTable.h"

// #define MAX_TUPLE 10
#define LSA_TTL 15
#define LSA_REFRESH_INTERVAL 30000 
#define LSA_EXPIRE_TIME 100000      

enum {
    MAX_TUPLE = 4  // change size to fit payload
};

typedef nx_struct tuple {
    nx_uint8_t neighbor;  // changed from uint16_t to uint8_t
    nx_uint8_t cost;
} tuple_t;

typedef nx_struct LSA {
    nx_uint8_t src;      
    nx_uint8_t seq;  
    nx_uint8_t numTuples;
    tuple_t tupleList[MAX_TUPLE];
} LSA;

#endif