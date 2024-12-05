#include "../includes/socket.h"
#include "../includes/tcp.h"
#include "../includes/packet.h"

module TransportP {
    provides interface Transport;

    uses {
        interface Timer<TMilli> as AckTimer;
        interface Timer<TMilli> as RtTimer;
        interface Hashmap<socket_store_t> as SocketMap;
        interface Queue<pack> as PacketQueue;
        interface IP;
    }
}

implementation {

    void handleNewAck(socket_t fd);
    void handleDupAck(socket_t fd);
    bool canSendData(socket_t fd, uint16_t dataLength);
    void retransmitSegment(socket_t fd);
    void initializeCongestion(socket_t fd);
    socket_t allocateSocket();
    void createTcpPacket(tcp_packet* tcp, uint16_t srcPort, uint16_t destPort, 
                        uint16_t seq, uint16_t ack, uint8_t flags);
    void tcpPacketToPayload(tcp_packet* tcp, void* payload);
    void payloadToTcpPacket(void* payload, tcp_packet* tcp);
    error_t sendTCPPacket(socket_t fd, uint8_t flags);
    void handleTCPPacket(socket_t fd, tcp_packet* tcp);


    // uint8_t getAvailableSpace(socket_t fd);
    // void enqueueForTransmission(socket_t fd, uint8_t* data, uint8_t len);

    // store all active connectiosn 
    socket_store_t sockets[MAX_NUM_OF_SOCKETS];

    typedef struct {
        uint16_t sequence;
        uint32_t timeout;
        uint8_t retries;
        uint8_t length;
        uint8_t data[SOCKET_BUFFER_SIZE];
    } transmit_queue_entry;

    // dif states 
    enum {
        SLOW_START = 0,
        CONGESTION_AVOIDANCE = 1,
        FAST_RECOVERY = 2
    };

    enum {
        FIN_WAIT_1 = 5,
        FIN_WAIT_2 = 6,
        CLOSE_WAIT = 7,
        LAST_ACK = 8,
        TIME_WAIT = 9
    };

    // transmission buffer management
    transmit_queue_entry txBuffer[MAX_NUM_OF_SOCKETS][SOCKET_BUFFER_SIZE];
    uint8_t txBufferHead[MAX_NUM_OF_SOCKETS];
    uint8_t txBufferTail[MAX_NUM_OF_SOCKETS];

    // helper function for starting new connectioms 
    socket_t allocateSocket() {
        socket_t fd = NULL_SOCKET;
        uint8_t i;
        
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].state == CLOSED) {
                memset(&sockets[i], 0, sizeof(socket_store_t));
                sockets[i].state = LISTEN;
                sockets[i].lastWritten = 0;
                sockets[i].lastAck = 0;
                sockets[i].lastSent = 0;
                sockets[i].lastRead = 0;
                sockets[i].lastRcvd = 0;
                sockets[i].nextExpected = 0;
                sockets[i].effectiveWindow = SOCKET_BUFFER_SIZE;
                fd = i;
                break;
            }
        }

        return fd;
    }

    // new pack arrives 
    // send more packs 
// checks for stable newtowrk 

    void handleNewAck(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        
        switch(sock->congestionState) {
            case SLOW_START:
                sock->cwnd++; // send pack 
                if(sock->cwnd >= sock->ssthresh) {
                    sock->congestionState = CONGESTION_AVOIDANCE;
                }
                break;
                
            case CONGESTION_AVOIDANCE:
                sock->cwnd += 1/sock->cwnd;
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
        
        if(sock->dupAckCount == 3) { 
            sock->ssthresh = sock->cwnd/2;
            sock->cwnd = sock->ssthresh + 3;
            sock->congestionState = FAST_RECOVERY;
            retransmitSegment(fd);
        } else if(sock->congestionState == FAST_RECOVERY) {
            sock->cwnd++;
        }
    }


    // lost packets 

    void retransmitSegment(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        
        if(txBufferHead[fd] != txBufferTail[fd]) {
            transmit_queue_entry* entry = &txBuffer[fd][txBufferHead[fd]];
            tcp_packet tcp;
            pack packet;
            
            createTcpPacket(&tcp, sock->src, sock->dest.port,
                        entry->sequence, sock->nextExpected, FLAG_ACK);
            
            memcpy(tcp.payload, entry->data, entry->length);
            
            packet.src = TOS_NODE_ID;
            packet.dest = sock->dest.addr;
            packet.protocol = PROTOCOL_TCP;
            packet.TTL = MAX_TTL;
            
            tcpPacketToPayload(&tcp, packet.payload);
            call IP.send(packet);
        }
    }


    bool canSendData(socket_t fd, uint16_t dataLength) {
        socket_store_t* sock = &sockets[fd];
        uint16_t outstandingData;
        
        if(sock->lastSent >= sock->lastAck) {
            outstandingData = sock->lastSent - sock->lastAck;
        } else {
            outstandingData = SOCKET_BUFFER_SIZE - (sock->lastAck - sock->lastSent);
        }
        
        return (outstandingData + dataLength <= sock->cwnd) && 
               (outstandingData + dataLength <= sock->effectiveWindow);
    }


    void initializeCongestion(socket_t fd) {
        socket_store_t* sock = &sockets[fd];
        sock->cwnd = 1;
        sock->ssthresh = 16;
        sock->dupAckCount = 0;
        sock->congestionState = SLOW_START;
    }

    // TCP packet Management
    void createTcpPacket(tcp_packet* tcp, uint16_t srcPort, uint16_t destPort, uint16_t seq, uint16_t ack, uint8_t flags) {
        tcp->srcPort = srcPort;
        tcp->destPort = destPort;
        tcp->seq = seq;
        tcp->ack = ack;
        tcp->flags = flags;
        tcp->advertisedWindow = SOCKET_BUFFER_SIZE;
        
        dbg("Transport", "Node %d: Creating TCP [src=%d dst=%d seq=%d ack=%d flags=%d win=%d]\n",
            TOS_NODE_ID, srcPort, destPort, seq, ack, flags, tcp->advertisedWindow);
    }


    void tcpPacketToPayload(tcp_packet* tcp, void* payload) {
        dbg("Transport", "Node %d: TCP->Payload conversion\n", TOS_NODE_ID);
        memcpy(payload, tcp, sizeof(tcp_packet));
    }


    void payloadToTcpPacket(void* payload, tcp_packet* tcp) {
        dbg("Transport", "Node %d: Payload->TCP conversion\n", TOS_NODE_ID);
        memcpy(tcp, payload, sizeof(tcp_packet));
    }

    // send tcp pack 
    // use IP 

    error_t sendTCPPacket(socket_t fd, uint8_t flags) {
        pack packet;
        tcp_packet tcp;
        socket_store_t* sock = &sockets[fd];
        
        dbg("Transport", "Node %d: Sending TCP [fd=%d flags=%d] to node %d\n", 
            TOS_NODE_ID, fd, flags, sock->dest.addr);
        
    //  create pack 
        createTcpPacket(&tcp, sock->src, sock->dest.port, 
                       sock->lastSent, sock->nextExpected, flags);
        
        packet.src = TOS_NODE_ID;
        packet.dest = sock->dest.addr;
        packet.protocol = PROTOCOL_TCP;
        packet.TTL = MAX_TTL;
        
        tcpPacketToPayload(&tcp, packet.payload);
        
        return call IP.send(packet);
    }
    /////////////////////////////

    command error_t Transport.receive(pack* package) {
        tcp_packet tcp;
        socket_t fd;
        
        if(package->protocol != PROTOCOL_TCP) {
            return FAIL;
        }
        
        payloadToTcpPacket(package->payload, &tcp);
        
        for(fd = 0; fd < MAX_NUM_OF_SOCKETS; fd++) {
            if(sockets[fd].state != CLOSED && 
               sockets[fd].src == tcp.destPort &&
               (sockets[fd].state == LISTEN || 
                sockets[fd].dest.port == tcp.srcPort)) {
                handleTCPPacket(fd, &tcp);
                break;
            }
        }
        
        return SUCCESS;
    }

    command uint16_t Transport.read(socket_t fd, uint8_t* buff, uint16_t bufflen) {
        socket_store_t* sock;
        uint16_t available;
        uint16_t bytesToRead;
        uint16_t i;
        
        if(fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != ESTABLISHED) {
            return 0;
        }
        
        sock = &sockets[fd];
        
        // Calculate available data
        if(sock->lastRcvd >= sock->lastRead) {
            available = sock->lastRcvd - sock->lastRead;
        } else {
            available = SOCKET_BUFFER_SIZE - (sock->lastRead - sock->lastRcvd);
        }
        
        bytesToRead = (bufflen < available) ? bufflen : available;
        
        // Copy data from receive buffer
        for(i = 0; i < bytesToRead; i++) {
            buff[i] = sock->rcvdBuff[(sock->lastRead + i) % SOCKET_BUFFER_SIZE];
        }
        
        // Update read pointer and window
        sock->lastRead = (sock->lastRead + bytesToRead) % SOCKET_BUFFER_SIZE;
        sock->effectiveWindow = SOCKET_BUFFER_SIZE - 
            ((sock->lastRcvd - sock->lastRead + SOCKET_BUFFER_SIZE) % SOCKET_BUFFER_SIZE);
        
        return bytesToRead;
    }

    command uint16_t Transport.write(socket_t fd, uint8_t* buff, uint16_t bufflen) {
        socket_store_t* sock;
        uint8_t spaceAvailable;
        uint16_t bytesToWrite;
        uint16_t i;
        
        if(fd >= MAX_NUM_OF_SOCKETS || buff == NULL || bufflen == 0) {
            return 0;
        }
        
        sock = &sockets[fd];
        
        if(sock->state != ESTABLISHED || !canSendData(fd, bufflen)) {
            return 0;
        }
        
        // spaceAvailable = getAvailableSpace(fd);
        bytesToWrite = (bufflen < spaceAvailable) ? bufflen : spaceAvailable;
        
        if(bytesToWrite > 0) {
            tcp_packet tcp;
            pack packet;
            
            // Copy to send buffer
            for(i = 0; i < bytesToWrite; i++) {
                sock->sendBuff[(sock->lastWritten + i) % SOCKET_BUFFER_SIZE] = buff[i];
            }
            
            // Create and send TCP packet
            createTcpPacket(&tcp, sock->src, sock->dest.port, 
                          sock->lastSent, sock->nextExpected, FLAG_ACK);
            
            memcpy(tcp.payload, buff, bytesToWrite);
            
            packet.src = TOS_NODE_ID;
            packet.dest = sock->dest.addr;
            packet.protocol = PROTOCOL_TCP;
            packet.TTL = MAX_TTL;
            
            tcpPacketToPayload(&tcp, packet.payload);
            
            // enqueueForTransmission(fd, buff, bytesToWrite);
            
            if(call IP.send(packet) == SUCCESS) {
                sock->lastWritten = (sock->lastWritten + bytesToWrite) % SOCKET_BUFFER_SIZE;
                sock->lastSent = (sock->lastSent + bytesToWrite) % SOCKET_BUFFER_SIZE;
                dbg("Transport", "Node %d: Wrote %d bytes to socket %d\n", 
                    TOS_NODE_ID, bytesToWrite, fd);
            }
        }
        
        return bytesToWrite;
    }

    command error_t Transport.close(socket_t fd) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        
        sock = &sockets[fd];
        
        switch(sock->state) {
            case ESTABLISHED:
                sock->state = FIN_WAIT_1;
                sendTCPPacket(fd, FLAG_FIN | FLAG_ACK);
                call RtTimer.startOneShot(2000);
                break;
                
            case CLOSE_WAIT:
                sock->state = LAST_ACK;
                sendTCPPacket(fd, FLAG_FIN | FLAG_ACK);
                call RtTimer.startOneShot(2000);
                break;
                
            default:
                sock->state = CLOSED;
                break;
        }
        
        dbg("Transport", "Node %d: Closing socket %d, state=%d\n", 
            TOS_NODE_ID, fd, sock->state);
        return SUCCESS;
    }

    command error_t Transport.release(socket_t fd) {
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        
        atomic {
            // Clear all socket data
            memset(&sockets[fd], 0, sizeof(socket_store_t));
            sockets[fd].state = CLOSED;
            
            // Reset transmission buffers
            txBufferHead[fd] = 0;
            txBufferTail[fd] = 0;
        }
        
        dbg("Transport", "Node %d: Released socket %d\n", TOS_NODE_ID, fd);
        return SUCCESS;
    }

    /////////////////////////////
    command socket_t Transport.socket() {
        socket_t fd;
        dbg("Transport", "Node %d: Creating new socket\n", TOS_NODE_ID);
        
        atomic {
            fd = allocateSocket(); // try for free slot 
            // check if we have enough sockets
            if(fd >= MAX_NUM_OF_SOCKETS) {  // out of sockets 
                dbg("Transport", "Node %d: Socket allocation failed\n", TOS_NODE_ID);
                return NULL_SOCKET;
            }
            
            //buffers for sending and recieving 
            txBufferHead[fd] = 0;
            txBufferTail[fd] = 0;
            memset(&txBuffer[fd], 0, sizeof(transmit_queue_entry) * SOCKET_BUFFER_SIZE);
            memset(&sockets[fd], 0, sizeof(socket_store_t));
            
            sockets[fd].state = CLOSED;
            sockets[fd].effectiveWindow = SOCKET_BUFFER_SIZE;
            
            dbg("Transport", "Node %d: Socket %d created\n", TOS_NODE_ID, fd);
        }
        return fd;
    }

    // bind
    // socket -> address 
    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if(fd >= MAX_NUM_OF_SOCKETS || addr == NULL) {
            dbg("Transport", "Node %d: Bind failed - invalid params\n", TOS_NODE_ID);
            return FAIL;
        }
        
        // can only bind if listening or clsoed state 
        if(sockets[fd].state == LISTEN || sockets[fd].state == CLOSED) {
            sockets[fd].src = addr->port;
            sockets[fd].dest.addr = addr->addr;
            sockets[fd].dest.port = addr->port;
            if(sockets[fd].state == CLOSED) {
                sockets[fd].state = LISTEN;
            }
            dbg("Transport", "Node %d: Socket %d bound to port %d\n", 
                TOS_NODE_ID, fd, addr->port);
            return SUCCESS;
        }


        return FAIL;
    }

    // listen fuinctino HERE //////////////////////
    command error_t Transport.listen(socket_t fd) {
        if(fd >= MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        
        if(sockets[fd].state == CLOSED || sockets[fd].state == LISTEN) {
            sockets[fd].state = LISTEN;
            dbg("Transport", "Node %d: Socket %d listening\n", TOS_NODE_ID, fd);
            return SUCCESS;
        }

        return FAIL;
    }


    // start connection 
    // socket has to be closed 
    // V

    command error_t Transport.connect(socket_t fd, socket_addr_t* addr) {
        socket_store_t* sock;
        
        if(fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != CLOSED) {
            return FAIL;
        }
        
        sock = &sockets[fd];
        sock->dest = *addr;
        sock->state = SYN_SENT;
        
        dbg("Transport", "Node %d: Initiating connection from socket %d to %d:%d\n", 
            TOS_NODE_ID, fd, addr->addr, addr->port);
        
        // Initialize connection state
        sock->lastSent = 0;
        sock->lastAck = 0;
        sock->lastRcvd = 0;
        sock->lastRead = 0;
        sock->nextExpected = 0;
        sock->lastWritten = 0;
        
        // initial SYN
        sendTCPPacket(fd, FLAG_SYN);
        
        // Start retransmission timer
        call RtTimer.startOneShot(2000);
        
        return SUCCESS;
    }


    command socket_t Transport.accept(socket_t fd) {
        uint8_t i;
        
        if(fd >= MAX_NUM_OF_SOCKETS || sockets[fd].state != LISTEN) {
            return NULL_SOCKET; // cant accept if not listening 
        }
        
        // look for connections awating  acceptance
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].state == SYN_RCVD && sockets[i].src == sockets[fd].src) {
                sockets[i].state = ESTABLISHED;
                dbg("Transport", "Node %d: Accepted connection on socket %d\n", 
                    TOS_NODE_ID, i);
                return i;
            }
        }
        
        return NULL_SOCKET;
    }

    // handle all packet types 

    void handleTCPPacket(socket_t fd, tcp_packet* tcp) {
        socket_store_t* sock = &sockets[fd];
        
        if(fd >= MAX_NUM_OF_SOCKETS || tcp == NULL) return;
        
        dbg("Transport", "Node %d: Handling TCP [state=%d flags=%d seq=%d ack=%d]\n", 
            TOS_NODE_ID, sock->state, tcp->flags, tcp->seq, tcp->ack);
        
        // set window based on advertised window 
        sock->effectiveWindow = tcp->advertisedWindow;
        
        // handle data acks
        if(tcp->flags & FLAG_ACK && sock->state >= SYN_SENT) {
            if(tcp->ack > sock->lastAck && tcp->ack <= sock->lastSent) {
                sock->lastAck = tcp->ack;
                sock->dupAckCount = 0;
                handleNewAck(fd);
            } else if(tcp->ack == sock->lastAck) {
                handleDupAck(fd);
            }
        }

        // state machine
        switch(sock->state) {
            case LISTEN:
                if(tcp->flags & FLAG_SYN) {
                    socket_t newfd = allocateSocket();
                    if(newfd != NULL_SOCKET) {
                        socket_store_t* newsock = &sockets[newfd];
                        newsock->src = sock->src;
                        newsock->dest.addr = TOS_NODE_ID;
                        newsock->dest.port = tcp->srcPort;
                        newsock->state = SYN_RCVD;
                        newsock->nextExpected = tcp->seq + 1;
                        
                        initializeCongestion(newfd);
                        sendTCPPacket(newfd, FLAG_SYN | FLAG_ACK);
                        
                        dbg("Transport", "Node %d: New connection pending on socket %d\n", 
                            TOS_NODE_ID, newfd);
                    }
                }
                break;
                
            case SYN_SENT:
                if((tcp->flags & (FLAG_SYN | FLAG_ACK)) == (FLAG_SYN | FLAG_ACK)) {
                    sock->nextExpected = tcp->seq + 1;
                    sock->state = ESTABLISHED;
                    sendTCPPacket(fd, FLAG_ACK);
                    dbg("Transport", "Node %d: Connection established\n", TOS_NODE_ID);
                }
                break;
                
            case SYN_RCVD:
                if(tcp->flags & FLAG_ACK) {
                    sock->state = ESTABLISHED;
                }
                break;
                
            case ESTABLISHED:
                // hgandle incoming data
                if(tcp->payload[0] != '\0') {
                    uint8_t dataLen = strlen((char*)tcp->payload);
                    if(dataLen > 0) {
                        memcpy(&sock->rcvdBuff[sock->lastRcvd], tcp->payload, dataLen);
                        sock->lastRcvd = (sock->lastRcvd + dataLen) % SOCKET_BUFFER_SIZE;
                        sock->nextExpected = tcp->seq + dataLen;
                        sendTCPPacket(fd, FLAG_ACK);
                    }
                }
                if(tcp->flags & FLAG_FIN) {
                    sock->state = CLOSE_WAIT;
                    sock->nextExpected = tcp->seq + 1;
                    sendTCPPacket(fd, FLAG_ACK);
                }
                break;

            // cnnection teardown states
            case FIN_WAIT_1:
            case FIN_WAIT_2:
            case LAST_ACK:
            case TIME_WAIT:
                if(tcp->flags & FLAG_ACK) {
                    if(sock->state == FIN_WAIT_1) {
                        sock->state = FIN_WAIT_2;
                    } else if(sock->state == LAST_ACK) {
                        sock->state = CLOSED;
                    }
                }
                if(tcp->flags & FLAG_FIN) {
                    if(sock->state == FIN_WAIT_1 || sock->state == FIN_WAIT_2) {
                        sock->state = TIME_WAIT;
                        sock->nextExpected = tcp->seq + 1;
                        sendTCPPacket(fd, FLAG_ACK);
                        call RtTimer.startOneShot(120000);
                    }
                }
                break;
        }
    }

    event void RtTimer.fired() {
        uint8_t fd;
        uint32_t now = call RtTimer.getNow();
        bool needTimer = FALSE;
        
        // retransmission checks
        // checks all oackets that need to be resent
        for(fd = 0; fd < MAX_NUM_OF_SOCKETS; fd++) {
            if(sockets[fd].state == ESTABLISHED) {
                while(txBufferHead[fd] != txBufferTail[fd]) {
                    transmit_queue_entry* entry = &txBuffer[fd][txBufferHead[fd]];

                    
                    if(entry->timeout <= now) {
                        if(entry->retries < 5) {
                            retransmitSegment(fd);
                            entry->timeout = now + (2000 << entry->retries);
                            entry->retries++;
                            needTimer = TRUE;
                        } else {
                            txBufferHead[fd] = (txBufferHead[fd] + 1) % SOCKET_BUFFER_SIZE;
                        }
                    } else {
                        needTimer = TRUE;
                        break;
                    }
                }
            }
        }
        
        if(needTimer) {
            call RtTimer.startOneShot(1000);
        }
    }

    event void AckTimer.fired() {
        uint8_t i;
        for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
            if(sockets[i].state == ESTABLISHED) {
                sendTCPPacket(i, FLAG_ACK);
            }
        }
    }

    event void IP.receive(pack* packet) {
        if(packet->protocol == PROTOCOL_TCP) {
            tcp_packet tcp;
            uint8_t i;
            
            payloadToTcpPacket(packet->payload, &tcp);
            
            for(i = 0; i < MAX_NUM_OF_SOCKETS; i++) {
                if(sockets[i].state != CLOSED && 
                   sockets[i].src == tcp.destPort &&
                   (sockets[i].state == LISTEN || sockets[i].dest.port == tcp.srcPort)) {
                    handleTCPPacket(i, &tcp);
                    break;
                }
            }
        }
    }

    
}