configuration TestC {
    provides interface Test;
}

implementation {
    components TestP;
    components TransportC;
    components new TimerMilliC() as TestTimer;
    // components new TimerMilliC() as DataTimer; 

    Test = TestP.Test;
    TestP.Transport -> TransportC;
    TestP.TestTimer -> TestTimer;
    // TestP.DataTimer -> DataTimer; 
}