configuration ChatC {
    provides interface Chat;
}

implementation {
    components ChatP;
    components new TimerMilliC() as ChatTimer;
    components TransportC;

    Chat = ChatP.Chat;
    ChatP.ChatTimer -> ChatTimer;
    ChatP.Transport -> TransportC;
}