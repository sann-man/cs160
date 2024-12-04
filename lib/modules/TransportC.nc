configuration TransportC {
    provides interface Transport;
}

implementation {
    components TransportP;
    components new TimerMilliC() as RtTimer;
    components new TimerMilliC() as AckTimer;
    components IPP;

    Transport = TransportP;
    
    TransportP.RtTimer -> RtTimer;
    TransportP.AckTimer -> AckTimer;
    TransportP.IP -> IPP;
}