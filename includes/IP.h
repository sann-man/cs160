#ifndef IP_H
#define IP_H

#include "packet.h"

#define IP_MAX_ROUTES 20
#define IP_ROUTE_TIMEOUT 300000 // 5 minutes in milliseconds

typedef nx_struct ip_route {
    nx_uint16_t dest;
    nx_uint16_t nextHop;
    nx_uint32_t cost;
    nx_uint32_t timestamp;
} ip_route_t;

#endif