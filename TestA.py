from TestSim import TestSim

def main():
    # get simulation ready to run.
    s = TestSim()
    s.runTime(1)
    
    # Load the topology
    s.loadTopo("pizza.topo")
    s.loadNoise("meyer-heavy.txt")
    s.bootAll()
    
    # Add channels for debugging
    s.addChannel(s.COMMAND_CHANNEL)
    s.addChannel(s.GENERAL_CHANNEL)
    s.addChannel(s.TRANSPORT_CHANNEL) 
    s.addChannel("TestP")           
    s.addChannel("Transport")      
    
    # wait for network to stabilize
    print("Waiting for network to stabilize...")
    s.runTime(300)
    
    # start test sequence
    print("Starting test server on node 1...")
    s.testServer(1)
    s.runTime(60)
    
    print("Starting test client on node 13...")
    s.testClient(13)
    s.runTime(1000)

if __name__ == '__main__':
    main()