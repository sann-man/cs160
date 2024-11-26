interface LinkState {
    command error_t start();
    // event void NeighborDiscovery.done();
    command void getRouteTable(routing_t* table, uint8_t* size); 
    command void floodLSA();
}