interface Chat {
    command error_t startServer();
    command error_t handleMsg(char* username, char* msg);
    command error_t handleWhisper(char* username, char* target, char* msg);
    command error_t listUsers();
}