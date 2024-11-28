interface LinkState {
    command error_t start();
    command void floodLSA();
    command void getRouteTable(routing_t* table, uint8_t* size);
}