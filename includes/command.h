/* 
 * Author: UCM ANDES Lab
 * $author$
 * $LastChangedDate: 2014-06-16 13:16:24 -0700 (Mon, 16 Jun 2014) $
 * Description: Processes commands and returns an Command ID Number.
 */

#ifndef COMMAND_H
#define COMMAND_H

#define CMD_CHAT_MSG 11
#define CMD_CHAT_WHISPER 12
#define CMD_CHAT_LIST 13
#define CMD_CHAT_HELLO 14

// command ID Numbers
enum {
    CMD_PING = 0,
    CMD_NEIGHBOR_DUMP = 1,
    CMD_LINKSTATE_DUMP = 2,
    CMD_ROUTETABLE_DUMP = 3,
    CMD_TEST_CLIENT = 4,
    CMD_TEST_SERVER = 5,
    CMD_KILL = 6,
    CMD_ERROR = 9
};

enum {
    CMD_LENGTH = 1,
};

#endif /* COMMAND_H */