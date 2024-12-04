#include "../../includes/socket.h"
#include "../../includes/tcp.h"
#include "../../includes/packet.h"

module TestP {
    provides interface Test;
    
    uses {
        interface Transport;
        interface Timer<TMilli> as TestTimer;
        interface Timer<TMilli> as DataTimer;
    }
}

implementation {
    // test state tracking
    socket_t serverSocket; 

    typedef struct {
        socket_t socket;
        uint16_t testDataSent;
        uint16_t testDataReceived;
        uint8_t testState;
        bool isServer;
    } test_info_t;
    
    test_info_t testInfo;
    uint8_t testData[SOCKET_BUFFER_SIZE];
    
    enum {
        TEST_IDLE,
        TEST_CONNECTING,
        TEST_SENDING,
        TEST_RECEIVING,
        TEST_CLOSING
    };
    
    // initialize test data
    void initializeTestData() {
        uint16_t i;
        for(i = 0; i < SOCKET_BUFFER_SIZE; i++) {
            testData[i] = i & 0xFF;
        }
    }
    
    // server implementation
    command error_t Test.startServer(uint16_t port) {
        socket_addr_t addr;
        
        serverSocket = call Transport.socket();
        
        if(serverSocket >= MAX_NUM_OF_SOCKETS) {
            return FAIL;
        }
        
        addr.port = port;
        addr.addr = TOS_NODE_ID;
        
        if(call Transport.bind(serverSocket, &addr) != SUCCESS) {
            return FAIL;
        }
        
        if(call Transport.listen(serverSocket) != SUCCESS) {
            return FAIL;
        }
        
        call TestTimer.startPeriodic(1000);
        return SUCCESS;
    }
    
    // client implementation
    command error_t Test.startClient(uint16_t destAddr, uint16_t destPort, uint16_t srcPort) {
        socket_t clientSocket;
        socket_addr_t addr;
        
        // clear test state
        memset(&testInfo, 0, sizeof(test_info_t));
        testInfo.isServer = FALSE;
        testInfo.testState = TEST_CONNECTING;
        
        // initialize test data
        initializeTestData();
        
        // create and bind socket
        clientSocket = call Transport.socket();
        if(clientSocket == NULL_SOCKET) {
            dbg("TestP", "Client socket creation failed\n");
            return FAIL;
        }
        
        addr.port = srcPort;
        addr.addr = TOS_NODE_ID;
        if(call Transport.bind(clientSocket, &addr) != SUCCESS) {
            dbg("TestP", "Client bind failed\n");
            return FAIL;
        }
        
        // connect to server
        addr.port = destPort;
        addr.addr = destAddr;
        if(call Transport.connect(clientSocket, &addr) != SUCCESS) {
            dbg("TestP", "Client connect failed\n");
            return FAIL;
        }
        
        testInfo.socket = clientSocket;
        dbg("TestP", "Client connecting to %d:%d\n", destAddr, destPort);
        
        // start data transmission timer
        call DataTimer.startPeriodic(500);
        return SUCCESS;
    }
    
    // timer events
    event void TestTimer.fired() {
        socket_t clientSocket;
        uint8_t buffer[SOCKET_BUFFER_SIZE];
        uint16_t bytesRead;
        
        // try to accept new connection
        clientSocket = call Transport.accept(serverSocket);
        if(clientSocket < MAX_NUM_OF_SOCKETS) {
            // Successfully accepted connection
            bytesRead = call Transport.read(clientSocket, buffer, SOCKET_BUFFER_SIZE);
            if(bytesRead > 0) {

                
                // Process received data
                dbg("Transport", "Server received %d bytes\n", bytesRead);
            }
        }
    }
    
    event void DataTimer.fired() {
        if(!testInfo.isServer && testInfo.testState == TEST_SENDING) {
            uint16_t bytesToSend = 10; // Send 10 bytes at a time
            uint16_t bytesSent;
            
            bytesSent = call Transport.write(testInfo.socket, 
                                           &testData[testInfo.testDataSent % SOCKET_BUFFER_SIZE],
                                           bytesToSend);
            
            if(bytesSent > 0) {
                testInfo.testDataSent += bytesSent;
                dbg("TestP", "Client sent %d bytes, total: %d\n", 
                    bytesSent, testInfo.testDataSent);
                
                // If we've sent enough data, start closing
                if(testInfo.testDataSent >= 1000) {
                    testInfo.testState = TEST_CLOSING;
                    call Transport.close(testInfo.socket);
                    call DataTimer.stop();
                    dbg("TestP", "Client initiating close\n");
                }
            }
        }
    }
}