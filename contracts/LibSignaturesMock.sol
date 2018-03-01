pragma solidity ^0.4.0;

import "./ILibSignatures.sol";

contract LibSignaturesMock is ILibSignatures {
    function verify(address addr, bytes32 message, bytes signature) constant returns(bool) {
        return bytes(signature)[0] != 0;
    }
}

