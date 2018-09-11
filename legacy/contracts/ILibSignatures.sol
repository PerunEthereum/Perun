pragma solidity ^0.4.24;

interface ILibSignatures {
    function verify(address addr, bytes32 message, bytes signature) constant returns(bool);
}
