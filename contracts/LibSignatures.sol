pragma solidity ^0.4.0;

import "./ILibSignatures.sol";

contract LibSignatures is ILibSignatures {
    event EventVerificationSucceeded(bytes Signature, bytes32 Message, address Key);
    event EventVerificationFailed(bytes Signature, bytes32 Message, address Key);

    /*
    * This functionality verifies ECDSA signatures
    * @returns true if the signature of addr over message is correct
    */
    function verify(address addr, bytes32 message, bytes signature) constant returns(bool) {
        if (signature.length != 65)
            return (false);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27)
            v += 27;

        if (v != 27 && v != 28)
            return (false);

        address pk = ecrecover(message, v, r, s);

        if (pk == addr) {
            EventVerificationSucceeded(signature, message, pk);
            return (true);
        } else {
            EventVerificationFailed(signature, message, pk);
            return (false);
        }
    }
}
