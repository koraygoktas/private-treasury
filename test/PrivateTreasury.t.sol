// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PrivateTreasury} from "../src/PrivateTreasury.sol";

contract PrivateTreasuryTest is Test {
    PrivateTreasury treasury;

    address owner;
    uint256 ownerKey;
    address attestor;
    uint256 attestorKey;
    address investor;
    uint256 investorKey;
    address stranger;

    bytes32 constant JURISDICTION_US = keccak256("US-ACCREDITED");

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");
        (attestor, attestorKey) = makeAddrAndKey("attestor");
        (investor, investorKey) = makeAddrAndKey("investor");
        stranger = makeAddr("stranger");

        treasury = new PrivateTreasury(owner, attestor);
    }

    function _buildAttestation(address inv, uint64 expiry, bytes32 jurisdiction, uint256 nonce)
        internal
        pure
        returns (PrivateTreasury.Attestation memory)
    {
        return PrivateTreasury.Attestation({investor: inv, expiry: expiry, jurisdiction: jurisdiction, nonce: nonce});
    }

    function _sign(uint256 signerKey, PrivateTreasury.Attestation memory att) internal view returns (bytes memory) {
        bytes32 digest = treasury.digestAttestation(att);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_IssueMintsWithValidAttestation() public {
        PrivateTreasury.Attestation memory att =
            _buildAttestation(investor, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory sig = _sign(attestorKey, att);

        vm.prank(owner);
        treasury.issue(investor, 1000e18, att, sig);

        assertEq(treasury.balanceOf(investor), 1000e18);
        assertEq(treasury.totalSupply(), 1000e18);
    }

    function test_IssueRevertsIfNotOwner() public {
        PrivateTreasury.Attestation memory att =
            _buildAttestation(investor, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory sig = _sign(attestorKey, att);

        vm.prank(stranger);
        vm.expectRevert(PrivateTreasury.NotOwner.selector);
        treasury.issue(investor, 1000e18, att, sig);
    }

    function test_IssueRevertsOnExpiredAttestation() public {
        PrivateTreasury.Attestation memory att =
            _buildAttestation(investor, uint64(block.timestamp), JURISDICTION_US, 1);
        bytes memory sig = _sign(attestorKey, att);

        vm.warp(block.timestamp + 1);

        vm.prank(owner);
        vm.expectRevert(PrivateTreasury.AttestationExpired.selector);
        treasury.issue(investor, 1000e18, att, sig);
    }

    function test_IssueRevertsOnWrongInvestor() public {
        PrivateTreasury.Attestation memory att =
            _buildAttestation(stranger, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory sig = _sign(attestorKey, att);

        vm.prank(owner);
        vm.expectRevert(PrivateTreasury.AttestationInvestorMismatch.selector);
        treasury.issue(investor, 1000e18, att, sig);
    }

    function test_IssueRevertsOnBadSignature() public {
        PrivateTreasury.Attestation memory att =
            _buildAttestation(investor, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        // signed by investor's own key instead of the attestor's -- invalid
        bytes memory sig = _sign(investorKey, att);

        vm.prank(owner);
        vm.expectRevert(PrivateTreasury.InvalidSignature.selector);
        treasury.issue(investor, 1000e18, att, sig);
    }

        function test_TransferWithAttestationWorks() public {
        PrivateTreasury.Attestation memory issueAtt =
            _buildAttestation(investor, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory issueSig = _sign(attestorKey, issueAtt);
        vm.prank(owner);
        treasury.issue(investor, 1000e18, issueAtt, issueSig);

        PrivateTreasury.Attestation memory transferAtt =
            _buildAttestation(stranger, uint64(block.timestamp + 1 days), JURISDICTION_US, 2);
        bytes memory sig = _sign(attestorKey, transferAtt);

        vm.prank(investor);
        treasury.transferWithAttestation(stranger, 400e18, transferAtt, sig);

        assertEq(treasury.balanceOf(investor), 600e18);
        assertEq(treasury.balanceOf(stranger), 400e18);
    }

    function test_TransferWithAttestationRevertsOnInsufficientBalance() public {
        PrivateTreasury.Attestation memory transferAtt =
            _buildAttestation(stranger, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory sig = _sign(attestorKey, transferAtt);

        vm.prank(investor);
        vm.expectRevert(PrivateTreasury.InsufficientBalance.selector);
        treasury.transferWithAttestation(stranger, 1e18, transferAtt, sig);
    }

    function test_DirectTransferIsDisabled() public {
        vm.expectRevert(PrivateTreasury.DirectTransferDisabled.selector);
        treasury.transfer(stranger, 1);
    }

    function test_DirectTransferFromIsDisabled() public {
        vm.expectRevert(PrivateTreasury.DirectTransferDisabled.selector);
        treasury.transferFrom(investor, stranger, 1);
    }

    function test_RevokedAttestationCannotBeUsed() public {
        PrivateTreasury.Attestation memory att =
            _buildAttestation(investor, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory sig = _sign(attestorKey, att);

        bytes32 attHash = treasury.hashAttestation(att);
        vm.prank(attestor);
        treasury.revokeAttestation(attHash);

        vm.prank(owner);
        vm.expectRevert(PrivateTreasury.AttestationRevoked.selector);
        treasury.issue(investor, 1000e18, att, sig);
    }

    function test_RevokeRevertsIfNotAttestor() public {
        bytes32 fakeHash = keccak256("whatever");
        vm.prank(stranger);
        vm.expectRevert(PrivateTreasury.NotAttestor.selector);
        treasury.revokeAttestation(fakeHash);
    }

    function test_SetAttestorRotatesSigner() public {
        (address newAttestor, uint256 newAttestorKey) = makeAddrAndKey("newAttestor");

        vm.prank(owner);
        treasury.setAttestor(newAttestor);
        assertEq(treasury.attestor(), newAttestor);

        PrivateTreasury.Attestation memory att =
            _buildAttestation(investor, uint64(block.timestamp + 1 days), JURISDICTION_US, 1);
        bytes memory oldSig = _sign(attestorKey, att);

        vm.prank(owner);
        vm.expectRevert(PrivateTreasury.InvalidSignature.selector);
        treasury.issue(investor, 1000e18, att, oldSig);

        bytes memory newSig = _sign(newAttestorKey, att);
        vm.prank(owner);
        treasury.issue(investor, 1000e18, att, newSig);
        assertEq(treasury.balanceOf(investor), 1000e18);
    }

    function test_TransferOwnership() public {
        (address newOwner,) = makeAddrAndKey("newOwner");
        vm.prank(owner);
        treasury.transferOwnership(newOwner);
        assertEq(treasury.owner(), newOwner);
    }

    function test_ApproveEmitsAndStores() public {
        vm.prank(investor);
        treasury.approve(stranger, 500e18);
        assertEq(treasury.allowance(investor, stranger), 500e18);
    }
}