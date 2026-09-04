// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract PrivateTreasury {
    // ERC-20 metadata
    string public constant name = "Private Treasury Bond";
    string public constant symbol = "pTBOND";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    address public owner; 
    address public attestor; 

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AttestorUpdated(address indexed previousAttestor, address indexed newAttestor);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAttestor() {
        if (msg.sender != attestor) revert NotAttestor();
        _;
    }

    error NotOwner();
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
        uint64 expiry;
        bytes32 jurisdiction;
        uint256 nonce;
    }

    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256("Attestation(address investor,uint64 expiry,bytes32 jurisdiction,uint256 nonce)");

    bytes32 private immutable DOMAIN_SEPARATOR;

    mapping(bytes32 => bool) public revokedAttestations;

    event AttestationRevokedEvent(bytes32 indexed attestationHash);

    constructor(address initialOwner, address initialAttestor) {
        if (initialOwner == address(0) || initialAttestor == address(0)) revert ZeroAddress();
        owner = initialOwner;
        attestor = initialAttestor;
        emit OwnershipTransferred(address(0), initialOwner);
        emit AttestorUpdated(address(0), initialAttestor);

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function hashAttestation(Attestation calldata att) public pure returns (bytes32) {
        return keccak256(abi.encode(ATTESTATION_TYPEHASH, att.investor, att.expiry, att.jurisdiction, att.nonce));
    }

    function digestAttestation(Attestation calldata att) external view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, hashAttestation(att)));
    }

    function _checkAttestation(Attestation calldata att, bytes calldata signature, address expectedInvestor)
        internal
        view
    {
        if (att.investor != expectedInvestor) revert AttestationInvestorMismatch();
        if (block.timestamp > att.expiry) revert AttestationExpired();

        bytes32 attHash = hashAttestation(att);
        if (revokedAttestations[attHash]) revert AttestationRevoked();

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, attHash));
        if (_recoverSigner(digest, signature) != attestor) revert InvalidSignature();
    }

    function _recoverSigner(bytes32 digest, bytes calldata signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        return ecrecover(digest, v, r, s);
    }

    function issue(address investor, uint256 amount, Attestation calldata att, bytes calldata signature)
        external
        onlyOwner
    {
        _checkAttestation(att, signature, investor);
        totalSupply += amount;
        balanceOf[investor] += amount;
        emit Transfer(address(0), investor, amount);
    }

    function transferWithAttestation(
        address to,
        uint256 amount,
        Attestation calldata att,
        bytes calldata signature
    ) external returns (bool) {
        _checkAttestation(att, signature, to);

        uint256 fromBalance = balanceOf[msg.sender];
        if (fromBalance < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[msg.sender] = fromBalance - amount;
        }
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }


    function revokeAttestation(bytes32 attestationHash) external onlyAttestor {
        revokedAttestations[attestationHash] = true;
        emit AttestationRevokedEvent(attestationHash);
    }

    function setAttestor(address newAttestor) external onlyOwner {
        if (newAttestor == address(0)) revert ZeroAddress();
        emit AttestorUpdated(attestor, newAttestor);
        attestor = newAttestor;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }


    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        revert DirectTransferDisabled();
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert DirectTransferDisabled();
    }
}