pragma solidity ^0.4.24;

import "./LibSignatures.sol";

contract VPC {
    event EventVpcClosing(bytes32 indexed _id);
    event EventVpcClosed(bytes32 indexed _id, uint cashAlice, uint cashBob);

    // datatype for virtual state
    struct VpcState {
        uint AliceCash;
        uint BobCash;
        uint seqNo;
        uint validity;
        uint extendedValidity;
        bool open;
        bool waitingForAlice;
        bool waitingForBob;
        bool init;
    }

    // datatype for virtual state
    mapping (bytes32 => VpcState) public states;
    VpcState public s;
    bytes32 public id;

    /*
    * This function is called by any participant of the virtual channel
    * It is used to establish a final distribution of funds in the virtual channel
    */
    function close(address alice, address bob, uint sid, uint version, uint aliceCash, uint bobCash,
            bytes signA, bytes signB) public {
        require(msg.sender == alice || msg.sender == bob);

        id = keccak256(alice, bob, sid);
        s = states[id];
        
        // verfiy signatures
        bytes32 msgHash = keccak256(abi.encodePacked(id, version, aliceCash, bobCash));
        bytes32 gethPrefixHash = keccak256(abi.encodePacked("\u0019Ethereum Signed Message:\n32", msgHash));
        //require(LibSignatures.verify(alice, gethPrefixHash, signA) 
          //       && LibSignatures.verify(bob, gethPrefixHash, signB));

        // if such a virtual channel state does not exist yet, create one
        if (!s.init) {
            uint validity = now + 10 minutes;
            uint extendedValidity = validity + 10 minutes;
            s = VpcState(aliceCash, bobCash, version, validity, extendedValidity, true, true, true, true);
            EventVpcClosing(id);
        }

        // if channel is closed or timeouted do nothing
        if (!s.open || s.extendedValidity < now) return;
        if ((s.validity < now) && (msg.sender == alice || msg.sender == bob)) return;
 
        // check if the message is from alice or bob
        if (msg.sender == alice) s.waitingForAlice = false;
        if (msg.sender == bob) s.waitingForBob = false;

        // set values of Internal State
        if (version > s.seqNo) {
            s = VpcState(aliceCash, bobCash, version, s.validity, s.extendedValidity, 
                         true, s.waitingForAlice, s.waitingForBob, true);
        }

        // execute if both players responded
        if (!s.waitingForAlice && !s.waitingForBob) {
            s.open = false;
            EventVpcClosed(id, s.AliceCash, s.BobCash);
        }
        states[id] = s;
    }

    /*
    * For the virtual channel with id = (alice, ingrid, bob, sid) this function:
    *   returns (false, 0, 0) if such a channel does not exist or is neither closed nor timeouted, or
    *   return (true, a, b) otherwise, where (a, b) is a final distribution of funds in this channel
    */
    function finalize(address alice, address bob, uint sid) public returns (bool s, uint a, uint b) {
        id = keccak256(abi.encodePacked(alice, bob, sid));
        if (states[id].init) {
            if (states[id].extendedValidity < now) {
                states[id].open = false;
                EventVpcClosed(id, states[id].AliceCash, states[id].BobCash);
            }
            if (states[id].open)
                return (false, 0, 0);
            else
                return (true, states[id].AliceCash, states[id].BobCash);
        }
        else
            return (false, 0, 0);
    }
}
