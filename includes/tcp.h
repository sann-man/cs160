#ifndef TCP_H
#define TCP_H

#include "socket.h"

enum {
    FLAG_SYN = 0x1,    // 00000001
    FLAG_ACK = 0x2,    // 00000010
    FLAG_FIN = 0x4,    // .... 
    FLAG_DATA = 0x8    
};

// 
typedef enum {
    TCP_CLOSED,
    TCP_LISTEN,
    TCP_SYN_SENT,
    TCP_SYN_RCVD,
    TCP_ESTABLISHED,
    TCP_FIN_WAIT_1,
    TCP_FIN_WAIT_2,
    TCP_CLOSING,
    TCP_TIME_WAIT,
    TCP_CLOSE_WAIT,
    TCP_LAST_ACK
} tcp_state_t;

typedef nx_struct tcp_packet {
    nx_uint16_t srcPort;
    nx_uint16_t destPort;
    nx_uint16_t seq;
    nx_uint16_t ack;
    nx_uint8_t flags;
    nx_uint16_t advertisedWindow;
    nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
} tcp_packet;

#endif