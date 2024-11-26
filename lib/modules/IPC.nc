configuration IPC {
    provides interface IP;
}

implementation {
    components IPP;
    components new SimpleSendC(AM_PACK);
    components new AMReceiverC(AM_PACK);
    components LinkStateC;

    // Export the IP interface
    IP = IPP.IP;

    // Wire internal components
    IPP.Sender -> SimpleSendC;
    IPP.Receive -> AMReceiverC;
    IPP.LinkState -> LinkStateC;
}