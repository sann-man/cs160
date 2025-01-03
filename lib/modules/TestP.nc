module TestP {
    provides interface Test;
    
    uses {
        interface Transport;
        interface Timer<TMilli> as TestTimer;
    }
}

implementation {
    // Test state tracking
    socket_t serverSocket; 

    enum {
        TEST_IDLE = 0,
        TEST_CONNECTING = 1,
        TEST_ESTABLISHED = 2,
        TEST_SENDING = 3,
        TEST_RECEIVING = 4,
        TEST_CLOSING = 5
    };

    typedef struct {
        socket_t socket;
        uint16_t testDataSent;
        uint16_t testDataReceived; // # bytes received 
        uint8_t testState;
        bool isServer;
    } test_info_t;
    
    test_info_t testInfo;
    uint8_t testData[SOCKET_BUFFER_SIZE];

    // just update and log state changes 
    void updateTestState(uint8_t newState) {
        testInfo.testState = newState;
        dbg("TestP", "Node %d: test state changed to %d\n", TOS_NODE_ID, newState);
    }

    void handleConnectionEstablished(socket_t fd) {
        dbg("TestP", "Node %d: connection established for socket %d\n", TOS_NODE_ID, fd);
        updateTestState(TEST_ESTABLISHED);
    }    
    
    // creates new cocket using t.scoket()
    command error_t Test.startServer(uint16_t port) {
        socket_addr_t addr;
        dbg("TestP", "Node %d: starting TCP server on port %d\n", TOS_NODE_ID, port);
    
        // initialize test info
        testInfo.isServer = TRUE;
        testInfo.testState = TEST_IDLE;
        testInfo.testDataSent = 0;
        testInfo.testDataReceived = 0;
        
        // create socket
        serverSocket = call Transport.socket();
        if(serverSocket == NULL_SOCKET) {
            dbg("TestP", "Node %d: server socket creation failed\n", TOS_NODE_ID);
            return FAIL;
        }
        dbg("TestP", "Node %d: server socket created: %d\n", TOS_NODE_ID, serverSocket);
        
        // bind to address
        addr.port = port;
        addr.addr = TOS_NODE_ID;
        
        if(call Transport.bind(serverSocket, &addr) != SUCCESS) {
            dbg("TestP", "Node %d: Server bind failed\n", TOS_NODE_ID);
            return FAIL;
        }
        dbg("TestP", "Node %d: server socket bound successfully\n", TOS_NODE_ID);
        
        // start listening
        if(call Transport.listen(serverSocket) != SUCCESS) {
            dbg("TestP", "Node %d: erver listen failed\n", TOS_NODE_ID);
            return FAIL;
        }
        dbg("TestP", "Node %d: server listening on port %d\n", TOS_NODE_ID, port);
        
        // start timer to check for connections periodically 
        call TestTimer.startPeriodic(500);
        return SUCCESS;
    }


    command error_t Test.startClient(uint16_t destAddr, uint16_t srcPort, uint16_t destPort) {
        socket_t clientSocket;
        socket_addr_t addr;
        
        dbg("TestP", "Node %d: starting TCP client connecting to %d:%d\n", 
            TOS_NODE_ID, destAddr, destPort);
    
        // initialize  more test info (maybe repetative? )
        testInfo.isServer = FALSE;
        testInfo.testState = TEST_IDLE;
        testInfo.testDataSent = 0;
        testInfo.testDataReceived = 0;
        
        // create socket
        clientSocket = call Transport.socket();
        if(clientSocket == NULL_SOCKET) {
            dbg("TestP", "Node %d: client socket creation failed\n", TOS_NODE_ID);
            return FAIL;
        }
        dbg("TestP", "Node %d: client socket created: %d\n", TOS_NODE_ID, clientSocket);
        
    // set up destination address and initiate connection
        addr.port = srcPort;
        addr.addr = TOS_NODE_ID;
        if(call Transport.bind(clientSocket, &addr) != SUCCESS) {
            dbg("TestP", "Node %d: client bind failed\n", TOS_NODE_ID);
            return FAIL;
        }
        dbg("TestP", "Node %d: c socket bound to port %d\n", TOS_NODE_ID, srcPort);
        
        // connect to server
        addr.port = destPort;
        addr.addr = destAddr;
        if(call Transport.connect(clientSocket, &addr) != SUCCESS) {
            dbg("TestP", "Node %d: client connect failed\n", TOS_NODE_ID);
            return FAIL;
        }
        dbg("TestP", "Node %d: client initiating connection to %d:%d\n", 
            TOS_NODE_ID, destAddr, destPort);
        
        testInfo.socket = clientSocket;
        testInfo.isServer = FALSE;
        updateTestState(TEST_CONNECTING);
        
        return SUCCESS;
    }

    event void TestTimer.fired() {
        if(!testInfo.isServer) {
            uint8_t i;
            // client specific debug at each state
            dbg("TestP", "Node %d: client Timer fired, state=%d socket=%d\n", 
                TOS_NODE_ID, testInfo.testState, testInfo.socket);
                
            switch(testInfo.testState) {
                case TEST_CONNECTING:
                    dbg("TestP", "Node %d: client still waiting for connection establishment\n", TOS_NODE_ID);
                    break;
                    
                case TEST_ESTABLISHED: {
                    uint8_t data[10];
                    uint16_t written;
                    
                    dbg("TestP", "Node %d: client connection established, sending data\n", TOS_NODE_ID);
                    
                    for(i = 0; i < 10; i++) {
                        data[i] = testInfo.testDataSent + i;
                    }
                    
                    written = call Transport.write(testInfo.socket, data, 10);
                    if(written > 0) {
                        dbg("TestP", "Node %d: successfully wrote %d bytes\n", TOS_NODE_ID, written);
                        testInfo.testDataSent += written;
                    } else {
                        dbg("TestP", "Node %d: Failed to write data\n", TOS_NODE_ID);
                    }
                    break;
                }
                    
                default:
                    dbg("TestP", "Node %d: client in unexpected state %d\n", TOS_NODE_ID, testInfo.testState);
                    break;
            }
        } else {
            socket_t clientSocket;
            // server specific debug
            dbg("TestP", "Node %d: Server Timer fired, checking for connections\n", TOS_NODE_ID);
            
            clientSocket = call Transport.accept(serverSocket);
            if(clientSocket != NULL_SOCKET) {
                uint8_t buffer[SOCKET_BUFFER_SIZE];
                uint16_t bytesRead;
                uint8_t i;
                
                dbg("TestP", "Node %d: server accepted new connection: %d\n", TOS_NODE_ID, clientSocket);
                
                bytesRead = call Transport.read(clientSocket, buffer, SOCKET_BUFFER_SIZE);
                if(bytesRead > 0) {
                    dbg("TestP", "Node %d: server read %d bytes: ", TOS_NODE_ID, bytesRead);
                    for(i = 0; i < bytesRead && i < 10; i++) {
                        dbg_clear("TestP", "%d ", buffer[i]);
                    }
                    dbg_clear("TestP", "\n");
                }
            } else {
                dbg("TestP", "Node %d: No new connections\n", TOS_NODE_ID);
            }
        }
    }
}