interface IP {
    command error_t start();
    command error_t send(pack message);
    event void receive(pack* message);
}