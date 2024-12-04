#ifndef __SOCKET_H__
#define __SOCKET_H__

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,
    // * 
    NULL_SOCKET = 0xFF, 
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    SYN_SENT,
    SYN_RCVD,
};


typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t {
    uint8_t state;
    uint8_t src;
    socket_addr_t dest;
    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten;
    uint8_t lastAck;
    uint8_t lastSent;
    uint8_t lastRead;
    uint8_t lastRcvd;
    uint8_t nextExpected;
    uint8_t effectiveWindow;
    uint16_t cwnd;
    uint16_t ssthresh;
    uint8_t dupAckCount;
    uint8_t congestionState;
    uint8_t retries;
} socket_store_t;

#endif
