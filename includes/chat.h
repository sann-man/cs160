#ifndef CHAT_H
#define CHAT_H

typedef nx_struct chat_packet {
    nx_uint8_t type;
    nx_uint8_t username[16];
    nx_uint8_t message[128];
} chat_packet;

enum {
    CHAT_PORT = 41,
    CHAT_HELLO = 0,
    CHAT_MSG = 1,
    CHAT_WHISPER = 2,
    CHAT_LISTUSR = 3
};

#endif