interface CommandHandler {
    event void ping(uint16_t destination, uint8_t *payload);
    event void printNeighbors();
    event void printRouteTable();
    event void printLinkState();
    event void printDistanceVector();
    event void setTestServer();
    event void setTestClient();
    event void setAppServer();
    event void setAppClient();

    // event void chatHello(uint8_t* payload);
    // event void chatMsg(uint8_t* payload);
    // event void chatWhisper(uint8_t* payload);
    // event void chatListUsers();
}