pragma solidity ^0.4.24;

import "./ILibSignatures.sol";

contract LibSignatures is ILibSignatures {

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

        return ecrecover(message, v, r, s) == addr;
    }
}
