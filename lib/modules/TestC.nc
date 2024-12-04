configuration TestC {
    provides interface Test;
}

implementation {
    components TestP;
    components TransportC;
    components new TimerMilliC() as TestTimer;

    Test = TestP.Test;
    TestP.Transport -> TransportC;
    TestP.TestTimer -> TestTimer;
}