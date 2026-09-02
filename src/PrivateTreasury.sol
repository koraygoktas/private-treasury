//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

contract PrivateTreasury {
    string public constant name = "Private Treasury Bond";
    string public constant sybmbol = "pTBOND";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public owner;
    address public attestor;

    event OwnershipTransfered(address indexed previousOwner, address indexed newOwner);
    event AttestorTranfered(address indexed previousAttestor, address indexed newAttestor);

    modifier onlyOwner() {
        if(msg.sender != owner) revert NotOnwner();
        _;
    }
    modifier onlyAttestor(){
        if(msg.sender != attestor) revert NotAttestor();
        _;
    }
    error NotOnwner();
    error NotAttestor();
    error ZeroAddress();
    error AttestationExpired();
    error AttestationRevoked();
    error AttestationInvestorMismatch();
    error InvalidSignature();
    error DirectTransferDisabled();
    error InsufficientBalance();

    struct Attestation {
        address investor;
        uint256 expiry;
        bytes32 jurisdiction;
        uint256 nonce;
    }
}