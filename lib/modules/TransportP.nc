#include "../includes/socket.h"
#include "../includes/tcp.h"
#include "../includes/packet.h"


module TransportP{ 
    provides interface Transport; 

    uses { 
        interface Timer<TMilli> as AckTimer; 
        interface Timer<TMilli> as RtTimer; 
        interface Hashmap<socket_store_t> as SocketMap; 
        interface Queue<pack> as PacketQueue; 
        interface IP; 
    }
}

implementation{ 
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];  // sockets arr 

    typedef struct {
        uint16_t sequence;
        uint32_t timeout;
        uint8_t retries;
        uint8_t length;
        uint8_t data[SOCKET_BUFFER_SIZE];
    } transmit_queue_entry;

    enum {
        SLOW_START,
        CONGESTION_AVOIDANCE,
        FAST_RECOVERY
    };

    enum {
        FIN_WAIT_1 = 5,
        FIN_WAIT_2 = 6,
        CLOSE_WAIT = 7,
        LAST_ACK = 8,
        TIME_WAIT = 9
    };

    transmit_queue_entry txBuffer[MAX_NUM_OF_SOCKETS][SOCKET_BUFFER_SIZE];
    uint8_t txBufferHead[MAX_NUM_OF_SOCKETS];
    uint8_t txBufferTail[MAX_NUM_OF_SOCKETS];

    socket_t allocateSocket() { 
        uint8_t i; 
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++){ 
            if(sockets[i].state == CLOSED) { 
                sockets[i].state = LISTEN; 
                sockets[i].lastWritten = 0; 
                sockets[i].lastAck = 0; 
                sockets[i].lastSent = 0; 
                sockets[i].lastRead = 0; 
                sockets[i].lastRcvd = 0; 
                sockets[i].nextExpected = 0; 
                sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE; 
                return i; 
            }
        }
    }

    void initializeCongestion(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        sock->cwnd = 1;      // start with 1 MSS
        sock->ssthresh = 16; // initial threshold
        sock->dupAckCount = 0;
        sock->congestionState = SLOW_START;
    }

    // transport interface implementation
    command socket_t Transport.socket() {
        socket_t fd = allocateSocket(); 
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return NULL_SOCKET;
        }
        dbg("Transport", "Socket allocated with fd=%d\n", fd);
        return fd;
    }

    // bdinding 
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if(fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state == CLOSED) {
            return FAIL;
        }
        
        sockets[fd].src = addr->port;
        sockets[fd].dest.addr = addr->addr;
        sockets[fd].dest.port = addr->port;
        
        dbg("Transport", "Socket %d bound to port %d\n", fd, addr->port);
        return SUCCESS;
    }

    command error_t Transport.listen(socket_t fd) {
        if(fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != CLOSED) {
            return FAIL;
        }
        
        sockets[fd].state = LISTEN;
        dbg("Transport", "Socket %d now listening\n", fd);
        return SUCCESS;
    }

    // create the TCP packet 
    void createTcpPacket(tcp_packet* tcp, uint16_t srcPort, uint16_t destPort, uint16_t seq, uint16_t ack, uint8_t flags) {
        tcp->srcPort = srcPort;
        tcp->destPort = destPort;
        tcp->seq = seq;
        tcp->ack = ack;
        tcp->flags = flags;
        tcp->advertisedWindow = SOCKET_BUFFER_SIZE;  // start with full window 
    }

    void tcpPacketToPayload(tcp_packet* tcp, void* payload) {
        memcpy(payload, tcp, sizeof(tcp_packet));
    }

    void payloadToTcpPacket(void* payload, tcp_packet* tcp) {
        memcpy(tcp, payload, sizeof(tcp_packet));
    }

    // send a TCP packet
    error_t sendTCPPacket(socket_t fd, uint8_t flags) {
        pack packet;
        tcp_packet tcp;
        socket_store_t* sock = &sockets[fd];
        
        // create TCP packet
        createTcpPacket(&tcp, sock->src, sock->dest.port, sock->lastSent, sock->nextExpected, flags);
        
        // Package into network packet
        packet.src = TOS_NODE_ID;
        packet.dest = sock->dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;
        
        tcpPacketToPayload(&tcp, packet.payload);
        
        // send with IP for effeicieny 
        return call IP.send(packet);
    }

    // handle the received TCP packet
    void handleTCPPacket(socket_t fd, tcp_packet* tcp) {
        socket_store_t* sock = &sockets[fd];
        
        //  potenital states received states 
        switch(sock->state) {
            case LISTEN:
                if(tcp->flags & FLAG_SYN) {
                    sock->dest.port = tcp->srcPort;
                    sock->nextExpected = tcp->seq + 1;
                    sock->state = SYN_RCVD;
                    sendTCPPacket(fd, FLAG_SYN | FLAG_ACK);
                }
                break;
                
            case SYN_SENT:
                if((tcp->flags & (FLAG_SYN | FLAG_ACK)) == (FLAG_SYN | FLAG_ACK)) {
                    sock->nextExpected = tcp->seq + 1;
                    sock->state = ESTABLISHED;
                    sendTCPPacket(fd, FLAG_ACK);
                    dbg("Transport", "Connection Established for socket %d\n", fd);
                }
                break;
                
            case ESTABLISHED:
                // handle data or control packets
                if(tcp->flags & FLAG_ACK) {
                    sock->lastAck = tcp->ack;
                }
                if(tcp->flags & FLAG_FIN) {
                    sock->state = CLOSE_WAIT;
                    sock->nextExpected = tcp->seq + 1;
                    sendTCPPacket(fd, FLAG_ACK);
                }
                break;
        }
    }


    // ip receive 
    event void IP.receive(pack* packet) {
        tcp_packet tcp;
        uint8_t i;
        
        if(packet->protocol != PROTOCOL_TCP) {
            return;
        }
        
        // extract TCP packet
        payloadToTcpPacket(packet->payload, &tcp);
        
        // find matching socket and handle TCP packet
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].state != CLOSED && 
            sockets[i].src == tcp.destPort &&
            (sockets[i].state == LISTEN || 
                sockets[i].dest.port == tcp.srcPort)) {
                handleTCPPacket(i, &tcp);
                break;
            }
        }
    }

    // process outgoing connections
    command error_t Transport.connect(socket_t fd, socket_addr_t* addr) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != CLOSED) {
            return FAIL;
        }
        
        sock = &sockets[fd];
        sock->dest = *addr;
        sock->state = SYN_SENT;
        
        // send SYN packet
        sendTCPPacket(fd, FLAG_SYN);
        
        // start retransmission timer
        call RtTimer.startOneShot(2000); // 2 second timeout
        
        dbg("Transport", "iunitiating connection from socket %d to port %d\n", 
            fd, addr->port);
        
        return SUCCESS;
    }

    // handle received packets (NOT TCP packets )
    command error_t Transport.receive(pack* package) {
        socket_t fd;
        tcp_packet tcp;
        
        if(package->protocol != PROTOCOL_TCP) {
            return FAIL;
        }
        
        // extract TCP packet
        payloadToTcpPacket(package->payload, &tcp);
        
        // Find eth matching socket
        for(fd = 0; fd < MAX_NUM_OF_SOCKETS; fd++) {
            if(sockets[fd].state != CLOSED && sockets[fd].src == tcp.destPort && 
                (sockets[fd].state == LISTEN || sockets[fd].dest.port == tcp.srcPort)) {
                handleTCPPacket(fd, &tcp);
                break;
            }
        }
        
        return SUCCESS;
    }

    uint8_t getAvailableSpace(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        uint8_t usedSpace;
        
        if(sock->lastWritten >= sock->lastAck) {
            usedSpace = sock->lastWritten - sock->lastAck;
        } else {
            usedSpace = SOCKET_BUFFER_SIZE - (sock->lastAck - sock->lastWritten);
        }
        
        return SOCKET_BUFFER_SIZE - usedSpace;
    }

    void enqueueForTransmission(socket_t fd, uint8_t* data, uint8_t len) {
        socket_store_t* sock = &sockets[fd];
        uint8_t newTail = (txBufferTail[fd] + 1) % SOCKET_BUFFER_SIZE;
        
        if(newTail != txBufferHead[fd]) {
            transmit_queue_entry* entry = &txBuffer[fd][txBufferTail[fd]];
            entry->sequence = sock->lastSent;
            entry->timeout = call RtTimer.getNow() + 5000; // 5 sec timeout? 
            entry->retries = 0;
            entry->length = len;
            memcpy(entry->data, data, len);
            
            txBufferTail[fd] = newTail;
        }
    }

    // write implementation
    command uint16_t Transport.write(socket_t fd, uint8_t* buff, uint16_t bufflen) {
        
    }

    // read implementation
    command uint16_t Transport.read(socket_t fd, uint8_t* buff, uint16_t bufflen) {
        
    }

    // retransmission timer fired
    event void RtTimer.fired() {
        
        
        // check eachj all sockets for packets that need retransmission
        
        // if timeout try again up till a certain point 
        // if needTimer check agian in certian time period ... 
        
    }

    command error_t Transport.close(socket_t fd) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        
        sock = &sockets[fd];
        
        switch(sock->state) {
            case ESTABLISHED:
                // Initiate normal close
                sock->state = FIN_WAIT_1;
                sendTCPPacket(fd, FLAG_FIN | FLAG_ACK);
                call RtTimer.startOneShot(2000);  // Set timeout for FIN_WAIT_1
                break;
                
            case CLOSE_WAIT:
                // Respond to received FIN
                sock->state = LAST_ACK;
                sendTCPPacket(fd, FLAG_FIN | FLAG_ACK);
                call RtTimer.startOneShot(2000);  // Set timeout for LAST_ACK
                break;
                
            default:
                // Reset connection in other states
                sock->state = CLOSED;
                break;
        }
        
        dbg("Transport", "Socket %d closing, state: %d\n", fd, sock->state);
        return SUCCESS;
    }

    // hard close/reset connection
    command error_t Transport.release(socket_t fd) {
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        
        // clear socket data
        memset(&sockets[fd], 0, sizeof(socket_store_t));
        sockets[fd].state = CLOSED;
        
        // clear transmission buffers
        txBufferHead[fd] = txBufferTail[fd] = 0;
        
        dbg("Transport", "Socket %d forcefully released\n", fd);
        return SUCCESS;
    }

    ////// 
    void retransmitSegment(socket_t fd);

    // Congestion control event handlers
    void handleNewAck(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        
        switch(sock->congestionState) {
            case SLOW_START:
                sock->cwnd++;
                if(sock->cwnd >= sock->ssthresh) {
                    sock->congestionState = CONGESTION_AVOIDANCE;
                }
                break;
                
            case CONGESTION_AVOIDANCE:
                sock->cwnd += 1/sock->cwnd; // increase by 1/cwnd
                break;
                
            case FAST_RECOVERY:
                sock->congestionState = CONGESTION_AVOIDANCE;
                sock->cwnd = sock->ssthresh;
                break;
        }
    }

    void handleDupAck(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        sock->dupAckCount++;
        
        // if dupAckCount == 3 or something 
        // retrnasmit 
         
    }

    task void handleTimeout() {
        
    }

    // helper function for segment retransmission
    void retransmitSegment(socket_t fd) {
        // implementation details for retransmitting the lost segment
        
    }

    bool canSendData(socket_t fd, uint16_t dataLength) {
        socket_store_t* sock = &sockets[fd];
        uint16_t outstandingData = (sock->lastSent - sock->lastAck + SOCKET_BUFFER_SIZE) % SOCKET_BUFFER_SIZE;
        return outstandingData + dataLength <= sock->cwnd;
    }


    event void AckTimer.fired() {
        // Handle ACK timer expiration
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].state == ESTABLISHED) {
                sendTCPPacket(i, FLAG_ACK);
            }
        }
    }

    command socket_t Transport.accept(socket_t fd) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS) return MAX_NUM_OF_SOCKETS;
        sock = &sockets[fd];
        
        if(sock->state == LISTEN) {
            return fd;
        }
        
        return MAX_NUM_OF_SOCKETS;
    }


}