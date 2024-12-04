interface CommandHandler {
    // Existing events
    event void ping(uint16_t destination, uint8_t *payload);
    event void printNeighbors();
    event void printRouteTable();
    event void printLinkState();
    event void printDistanceVector();
    
    // Test events - now correctly defined as commands
    command error_t setTestServer();
    command error_t setTestClient();
    command error_t setAppServer();
    command error_t setAppClient();
}