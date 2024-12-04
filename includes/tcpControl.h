#ifndef TCP_CONTROL_H
#define TCP_CONTROL_H

#include "socket.h"

// TCP Segment Structure
typedef nx_struct tcp_segment {
    nx_uint16_t srcPort;
    nx_uint16_t destPort;
    nx_uint32_t seqNum;
    nx_uint32_t ackNum;
    nx_uint8_t flags;
    nx_uint16_t windowSize;
    nx_uint16_t checksum;
    nx_uint8_t data[SOCKET_BUFFER_SIZE];
} tcp_segment;

// TcP Connection States
enum {
    TCP_STATE_CLOSED,
    TCP_STATE_LISTEN,
    TCP_STATE_SYN_SENT,
    TCP_STATE_SYN_RCVD,
    TCP_STATE_ESTABLISHED,
    TCP_STATE_FIN_WAIT_1,
    TCP_STATE_FIN_WAIT_2,
    TCP_STATE_CLOSING,
    TCP_STATE_TIME_WAIT,
    TCP_STATE_CLOSE_WAIT,
    TCP_STATE_LAST_ACK
};

// TCP Flags
enum {
    TCP_FLAG_FIN = 1,
    TCP_FLAG_SYN = 2,
    TCP_FLAG_RST = 4,
    TCP_FLAG_PSH = 8,
    TCP_FLAG_ACK = 16,
    TCP_FLAG_URG = 32
};

// TCP Timer Values (in milliseconds)
enum {
    TCP_TIMER_RTT = 1000,   
    TCP_TIMER_PERSIST = 2000, // keep-alive (persit timer)
    TCP_TIMER_DACK = 200,    // delayed ACK timer
    TCP_MSL = 2000,          // maximum Segment Lifetime
    TCP_TIME_WAIT = 4000     // 2 * MSL
};

// TCP Control Block
typedef struct tcp_cb {
    uint8_t state;           
    uint16_t srcPort;        
    uint16_t destPort;       
    uint16_t destAddr;       
    
    // Sequence number variables
    uint32_t seqNum;         
    uint32_t lastAckSent;    
    uint32_t lastAckRcvd;    
    
    // window stuff 
    uint16_t sendWindow;     
    uint16_t rcvWindow;      
    uint16_t cwnd;           // Congestion window
    uint16_t ssthresh;       // slow start threshold
    
    // buffer management
    uint8_t* sendBuf;       
    uint16_t sendBufSize;    
    uint16_t sendBufHead;    
    uint16_t sendBufTail;    
    uint8_t* rcvBuf;         // receive buffer
    uint16_t rcvBufSize;     
    uint16_t rcvBufHead;     
    uint16_t rcvBufTail;     
    
    // Timers
    uint32_t rto;            // retransmission timeout
    uint32_t srtt;           // smoothed round trip time
    uint32_t rttvar;         // rnd trip time variation
} tcp_cb_t;

#endif