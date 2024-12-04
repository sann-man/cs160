interface Test {
    command error_t startServer(uint16_t port);
    command error_t startClient(uint16_t destAddr, uint16_t destPort, uint16_t srcPort);
}