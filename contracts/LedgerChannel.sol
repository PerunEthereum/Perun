pragma solidity ^0.4.8;

import "./ILibSignatures.sol";

contract LedgerChannel {
    uint constant confirmTime = 100 minutes;
    uint constant closingTime = 100 minutes;
    string constant alreadyClosed = " already closed";

    event EventLCOpening(uint id);
    event EventLCOpened();
    event EventLCNotOpened();
    event EventLCClosing();
    event EventClosed();
    
    event EventVCClosingInit(uint vid);
    event EventVCClosing(uint vid);
    event EventVCClose(uint vid, uint cash1, uint cash2, uint ver, bytes sig, bytes sigB);
    event EventVCCloseFinal(uint vid, uint cash1A, uint cash2A, uint versionA, bytes sigA, bytes sigAB,
                                      uint cash1B, uint cash2B, uint versionB, bytes sigB, bytes sigBA);

    modifier AliceOrBob {require(msg.sender == alice.id || msg.sender == bob.id); _;}

    struct Party {
        address id;
        int totalTransfers;
        uint cash;
    }

    enum LCStatus {Init, Open, ClosingByAlice, ClosingByBob}

    enum VCStatus {Empty, Closing, WaitingToClose, ClosingFinal, Timeouted, Closed}

    struct VirtualContract {
        address p1;
        uint cash1;
        uint subchan1;
        address Ingrid;
        address p2;
        uint cash2;
        uint subchan2;
        uint validity;
        VCStatus status;
        uint cashFinal1;
        uint cashFinal2;
        uint timeout;
    }

    Party public alice;
    Party public bob;
    uint id;
    uint public timeout;
    
    uint lastVersion;
    uint lastCash1;
    uint lastCash2;
    
    mapping (uint => VirtualContract) public virtual;
    LCStatus public status;
    ILibSignatures libSignatures;

    function LedgerChannel(address addressBob, uint lcId, ILibSignatures libSignaturesAddress) public payable {
        alice.id = msg.sender;
        alice.cash = msg.value;
        bob.id = addressBob;
        id = lcId;
        libSignatures = ILibSignatures(libSignaturesAddress);
        timeout = now + confirmTime;

        status = LCStatus.Init;
        EventLCOpening(id);
    }

    function LCOpen() public payable {
        require(msg.sender == bob.id && status == LCStatus.Init);

        bob.cash = msg.value;
        status = LCStatus.Open;
        timeout = 0;
        EventLCOpened();
    }

    function LCOpenTimeout() public {
        require(msg.sender == alice.id && status == LCStatus.Init);
        if (now > timeout) {
            EventLCNotOpened();
            selfdestruct(alice.id);
        }
    }
    
    function CheckSignature(address verifier, uint vid, address p1, uint cash1, uint subchan1, address Ingrid,
                                    address p2, uint cash2, uint subchan2, uint validity, uint version, bytes sig) private view returns (bool) {
        bytes32 msgHash = keccak256(vid, p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, version);
        return libSignatures.verify(verifier, msgHash, sig);                                
    }
    
    function CheckVersion(address verifierA, address verifierB, uint vid, VirtualContract memory vc, uint version, bytes sigA, bytes sigB) private view returns (bool) {
        if (!CheckSignature(verifierA, vid, vc.p1, vc.cash1, vc.subchan1, vc.Ingrid, vc.p2, vc.cash2, vc.subchan2, vc.validity, version, sigA))
            return false;
        bytes32 msgHash = keccak256(vid, vc.p1, vc.cash1, vc.subchan1, vc.Ingrid, vc.p2, vc.cash2, vc.subchan2, vc.validity, version, sigA);
        return libSignatures.verify(verifierB, msgHash, sigB); 
    }

    function CheckVC(uint vid, address p1, uint cash1, uint subchan1, address Ingrid,
                               address p2, uint cash2, uint subchan2, uint validity, bytes sig) private view {
        require(id == subchan1 || id == subchan2);
        require(Ingrid == alice.id || Ingrid == bob.id);
        require(Other(Ingrid, alice.id, bob.id) == p1 || Other(Ingrid, alice.id, bob.id) == p2);
        require(CheckSignature(Other(msg.sender, alice.id, bob.id), vid, p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, 0, sig));
    }

    function Other(address p, address p1, address p2) private pure returns (address) {
        if (p == p1) return p2;
        else return p1;
    }

    function VCCloseInit(uint vid, address p1, uint cash1, uint subchan1, address Ingrid,
                                   address p2, uint cash2, uint subchan2, uint validity, bytes sig) AliceOrBob public {
        require(now > validity && Ingrid == msg.sender && virtual[vid].status == VCStatus.Empty);
        CheckVC(vid, p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, sig);
        
        virtual[vid] = VirtualContract(p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, VCStatus.Closing, 0, 0, now + closingTime);
        EventVCClosingInit(vid);
    }
    
    function VCAlreadyClosed(uint vid, bytes sig) AliceOrBob public {
        require((msg.sender != virtual[vid].Ingrid && (virtual[vid].status == VCStatus.Closing || virtual[vid].status == VCStatus.ClosingFinal)) ||
                (msg.sender == virtual[vid].Ingrid && virtual[vid].status == VCStatus.Timeouted));
        bytes32 msgHash = keccak256(vid, alreadyClosed);
        require(libSignatures.verify(Other(msg.sender, alice.id, bob.id), msgHash, sig));
        EventClosed();
        selfdestruct(msg.sender);
    }
    
    function VCClose(uint vid, uint cash1, uint cash2, uint version, bytes sig, bytes sigB) AliceOrBob public {
        VirtualContract memory vc = virtual[vid];
        require(vc.status == VCStatus.Closing);
        require(msg.sender != vc.Ingrid);
        vc.cashFinal1 = cash1;
        vc.cashFinal2 = cash2;
        require(CheckVersion(Other(msg.sender, vc.p1, vc.p2), msg.sender, vid, vc, version, sig, sigB));
        EventVCClose(vid, cash1, cash2, version, sig, sigB);
        vc.status = VCStatus.WaitingToClose;
        virtual[vid] = vc;
    }
    
    function VCCloseInitTimeout(uint vid) AliceOrBob public {
        require(virtual[vid].status == VCStatus.Closing && msg.sender == virtual[vid].Ingrid);
        if (now > virtual[vid].timeout) {
            EventClosed();
            selfdestruct(msg.sender);
        }
    }
    
    // Ingrid needs to call VCCloseInit before she can call VCCloseFinal.
    function VCCloseFinal(uint vid, uint cash1A, uint cash2A, uint versionA, bytes sigA, bytes sigAB,
                                    uint cash1B, uint cash2B, uint versionB, bytes sigB, bytes sigBA) AliceOrBob public {
        VirtualContract memory vc = virtual[vid];
        require(msg.sender == vc.Ingrid && (vc.status == VCStatus.WaitingToClose || vc.status == VCStatus.Closing));
        
        require(CheckVersion(vc.p1, vc.p2, vid, vc, versionA, sigA, sigAB));
        require(CheckVersion(vc.p2, vc.p1, vid, vc, versionB, sigB, sigBA));
        if (versionA >= versionB) {
            vc.cashFinal1 = cash1A;
            vc.cashFinal2 = cash2A;
        }
        else {
            vc.cashFinal1 = cash1B;
            vc.cashFinal2 = cash2B;
        }
        vc.status = VCStatus.ClosingFinal;
        vc.timeout = now + closingTime;
        virtual[vid] = vc;
        EventVCCloseFinal(vid, cash1A, cash2A, versionA, sigA, sigAB, cash1B, cash2B, versionB, sigB, sigBA);
    }
    
    function VCCloseFinalTimeout(uint vid) AliceOrBob public {
        VirtualContract memory vc = virtual[vid];
        require(vc.status == VCStatus.ClosingFinal && msg.sender == vc.Ingrid);
        if (now > vc.timeout) {
          alice.totalTransfers += int(vc.cashFinal1) - int(vc.cash1);
          bob.totalTransfers += int(vc.cashFinal2) - int(vc.cash2);
          virtual[vid].status = VCStatus.Closed;
          EventClosed();
        }
    }
    
    function VCCloseTimeout(uint vid, address p1, uint cash1, uint subchan1, address Ingrid,
                                      address p2, uint cash2, uint subchan2, uint validity, bytes sig) AliceOrBob public {
        require(virtual[vid].status != VCStatus.Closed && virtual[vid].status != VCStatus.Timeouted && msg.sender != Ingrid);
        CheckVC(vid, p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, sig);
        if (now > validity + 2 * closingTime) {
          virtual[vid].status = VCStatus.Timeouted;
          virtual[vid].Ingrid = Ingrid;
          virtual[vid].timeout = now + closingTime;
          EventVCClosing(vid);
        }
    }
    
    function VCCloseTimeoutTimeout(uint vid) AliceOrBob public {
        VirtualContract memory vc = virtual[vid];
        require(vc.status == VCStatus.Timeouted && msg.sender != vc.Ingrid);
        if (now > vc.timeout) {
            EventClosed();
            selfdestruct(msg.sender);
        }
    }
    
    function LCClose(uint cash1, uint cash2, uint version, bytes sig) AliceOrBob public {
        require(status == LCStatus.Open || (status == LCStatus.ClosingByAlice && msg.sender == bob.id) ||
                                           (status == LCStatus.ClosingByBob && msg.sender == alice.id));
        bytes32 msgHash = keccak256(id, alice.id, cash1, bob.id, cash2, version);
        require(libSignatures.verify(Other(msg.sender, alice.id, bob.id), msgHash, sig));
        if (status == LCStatus.Open) {
            lastVersion = version;
            lastCash1 = cash1;
            lastCash2 = cash2;
            if (msg.sender == alice.id) {
                status = LCStatus.ClosingByAlice;
            }
            else {
                status = LCStatus.ClosingByBob;
            }
            timeout = now + 3*closingTime;
            EventLCClosing();
        }
        else {
            if (version > lastVersion) {
                lastCash1 = cash1;
                lastCash2 = cash2;
            }
            require(alice.id.send(uint(int(lastCash1) + alice.totalTransfers)));
            require(bob.id.send(uint(int(lastCash2) + bob.totalTransfers)));
            EventClosed();
            selfdestruct(msg.sender);
        }
    }
    
    function VCActive(uint vid, address p1, uint cash1, uint subchan1, address Ingrid,
                                address p2, uint cash2, uint subchan2, uint validity, bytes sig) AliceOrBob public {
        require((status == LCStatus.ClosingByAlice && msg.sender == bob.id) ||
                (status == LCStatus.ClosingByBob && msg.sender == alice.id));
        CheckVC(vid, p1, cash1, subchan1, Ingrid, p2, cash2, subchan2, validity, sig);
        require(now < validity + closingTime);
        EventClosed();
        selfdestruct(msg.sender);
    }
    
    function LCCloseTimeout() AliceOrBob public {
        require((status == LCStatus.ClosingByAlice && msg.sender == alice.id) || 
                (status == LCStatus.ClosingByBob && msg.sender == bob.id));
        if (now > timeout) {
            require(alice.id.send(uint(int(lastCash1) + alice.totalTransfers)));
            require(bob.id.send(uint(int(lastCash2) + bob.totalTransfers)));
            EventClosed();
            selfdestruct(msg.sender);
        }
    }
}

