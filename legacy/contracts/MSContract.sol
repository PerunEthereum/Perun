pragma solidity ^0.4.16;

import "./VPC.sol";

contract MSContract {
    event EventInitializing(address addressAlice, address addressBob);
    event EventInitialized(uint cashAlice, uint cashBob);
    event EventRefunded();
    event EventStateRegistering();
    event EventStateRegistered(uint blockedAlice, uint blockedBob);
    event EventClosing();
    event EventClosed();
    event EventNotClosed();

    modifier AliceOrBob { require(msg.sender == alice.id || msg.sender == bob.id); _;}

    //Data type for Internal Contract
    struct Party {
        address id;
        uint cash;
        bool waitForInput;
    }

    //Data type for Internal Contract
    struct InternalContract {
        bool active;
        VPC vpc;
        uint sid;
        uint blockedA;
        uint blockedB;
        uint version;
    }

    // State options
    enum ChannelStatus {Init, Open, InConflict, Settled, WaitingToClose, ReadyToClose}

    // MSContract variables
    Party public alice;
    Party public bob;
    uint public timeout;
    InternalContract public c;
    ChannelStatus public status;

    /*
    * Constructor for setting initial variables takes as input
    * addresses of the parties of the basic channel
    */
    function MSContract(address _addressAlice, address _addressBob) public {
        // set addresses
        alice.id = _addressAlice;
        bob.id = _addressBob;

        // set limit until which Alice and Bob need to respond
        timeout = now + 100 minutes;
        alice.waitForInput = true;
        bob.waitForInput = true;

        // set other initial values
        status = ChannelStatus.Init;
        c.active = false;
        EventInitializing(_addressAlice, _addressBob);
    }

    /*
    * This functionality is used to send funds to the contract during 100 minutes after channel creation
    */
    function confirm() public AliceOrBob payable {
        require(status == ChannelStatus.Init && now < timeout);

        // Response (in time) from Player A
        if (alice.waitForInput && msg.sender == alice.id) {
            alice.cash = msg.value;
            alice.waitForInput = false;
        }

        // Response (in time) from Player B
        if (bob.waitForInput && msg.sender == bob.id) {
            bob.cash = msg.value;
            bob.waitForInput = false;
        }

        // execute if both players responded
        if (!alice.waitForInput && !bob.waitForInput) {
            status = ChannelStatus.Open;
            timeout = 0;
            EventInitialized(alice.cash, bob.cash);
        }
    }

    /*
    * This function is used in case one of the players did not confirm the MSContract in time
    */
    function refund() public AliceOrBob {
        require(status == ChannelStatus.Init && now > timeout);

        // refund money
        if (alice.waitForInput && alice.cash > 0) {
            require(alice.id.send(alice.cash));
        }
        if (bob.waitForInput && bob.cash > 0) {
            require(bob.id.send(bob.cash));
        }
        EventRefunded();

        // terminate contract
        selfdestruct(alice.id); 
    }

    /*
    * This functionality is called whenever the channel state needs to be established
    * it is called by both, alice and bob
    * Afterwards the parties have to interact directly with the VPC
    * and at the end they should call the execute function
    * @param     contract address: vpc, _sid,
                 blocked funds from A and B: blockedA and blockedB,
                 version parameter: version,
    *            signature parameter (from A and B): sigA, sigB
    */
    function stateRegister(address _vpc, // vulnerable?
                           uint _sid, 
                           uint _blockedA, 
                           uint _blockedB, 
                           uint _version, 
                           bytes sigA, 
                           bytes sigB) public AliceOrBob {
        // check if the parties have enough funds in the contract
        require(alice.cash >= _blockedA && bob.cash >= _blockedB);

        // verfify correctness of the signatures
        bytes32 msgHash = keccak256(_vpc, _sid, _blockedA, _blockedB, _version);
        bytes32 gethPrefixHash = keccak256("\u0019Ethereum Signed Message:\n32", msgHash);

        require(LibSignatures.verify(alice.id, gethPrefixHash, sigA)
                && LibSignatures.verify(bob.id, gethPrefixHash, sigB));
        
        // execute on first call
        if (status == ChannelStatus.Open || status == ChannelStatus.WaitingToClose) {
            status = ChannelStatus.InConflict;
            alice.waitForInput = true;
            bob.waitForInput = true;
            timeout = now + 100 minutes;
            EventStateRegistering();
        }
        if (status != ChannelStatus.InConflict) return;

        // record if message is sent by alice and bob
        if (msg.sender == alice.id) alice.waitForInput = false;
        if (msg.sender == bob.id) bob.waitForInput = false;

        // set values of InternalContract
        if (_version > c.version) {
            c.active = true;
            c.vpc = VPC(_vpc);
            c.sid = _sid;
            c.blockedA = _blockedA;
            c.blockedB = _blockedB;
            c.version = _version;
        }

        // execute if both players responded
        if (!alice.waitForInput && !bob.waitForInput) {
            status = ChannelStatus.Settled;
            alice.waitForInput = false;
            bob.waitForInput = false;
            alice.cash -= c.blockedA;
            bob.cash -= c.blockedB;
            EventStateRegistered(c.blockedA, c.blockedB);
        }
    }

    /*
    * This function is used in case one of the players did not confirm the state
    */
    function finalizeRegister() public AliceOrBob {
        require(status == ChannelStatus.InConflict && now > timeout);

        status = ChannelStatus.Settled;
        alice.waitForInput = false;
        bob.waitForInput = false;
        alice.cash -= c.blockedA;
        bob.cash -= c.blockedB;
        EventStateRegistered(c.blockedA, c.blockedB);
    }

    /*
    * This functionality executes the internal VPC Machine when its state is settled
    * The function takes as input addresses of the parties of the virtual channel
    */
    function execute(address _alice, 
                     address _bob) public AliceOrBob {
        require(status == ChannelStatus.Settled);

        // call virtual payment machine on the params
        var (s, a, b) = c.vpc.finalize(_alice, _bob, c.sid);

        // check if the result makes sense
        if (!s) return;

        // update balances only if they make sense
        if (a + b == c.blockedA + c.blockedB) {
            alice.cash += a;
            c.blockedA -= a;
            bob.cash += b;
            c.blockedB -= b;
        }

        // send funds to A and B
        if (alice.id.send(alice.cash)) alice.cash = 0;
        if (bob.id.send(bob.cash)) bob.cash = 0;

        // terminate channel
        if (alice.cash == 0 && bob.cash == 0) {
            EventClosed();
            selfdestruct(alice.id);
        }
    }

    /*
    * This functionality closes the channel when there is no internal machine
    */
    function close() public AliceOrBob {
        if (status == ChannelStatus.Open) {
            status = ChannelStatus.WaitingToClose;
            timeout = now + 300 minutes;
            alice.waitForInput = true;
            bob.waitForInput = true;
            EventClosing();
        }

        if (status != ChannelStatus.WaitingToClose) return;

        // Response (in time) from Player A
        if (alice.waitForInput && msg.sender == alice.id)
            alice.waitForInput = false;

        // Response (in time) from Player B
        if (bob.waitForInput && msg.sender == bob.id)
            bob.waitForInput = false;

        if (!alice.waitForInput && !bob.waitForInput) {
            // send funds to A and B
            if (alice.id.send(alice.cash)) alice.cash = 0;
            if (bob.id.send(bob.cash)) bob.cash = 0;

            // terminate channel
            if (alice.cash == 0 && bob.cash == 0) {
                EventClosed();
                selfdestruct(alice.id);
            }
        }
    }

    function finalizeClose() public AliceOrBob {
        if (status != ChannelStatus.WaitingToClose) {
            EventNotClosed();
            return;
        }

        // execute if timeout passed
        if (now > timeout) {
            // send funds to A and B
            if (alice.id.send(alice.cash)) alice.cash = 0;
            if (bob.id.send(bob.cash)) bob.cash = 0;

            // terminate channel
            if (alice.cash == 0 && bob.cash == 0) {
                EventClosed();
                selfdestruct(alice.id);
            }
        }
    }
}

