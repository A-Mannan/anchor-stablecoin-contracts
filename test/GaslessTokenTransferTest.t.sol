// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";

contract GaslessTokenTransferTest is Test {
    AnchorUSD public anchorUSD;
    address public anchorEngine = makeAddr("anchorEngine");
    address public feeReceiver = makeAddr("feeReceiver");

    address public user1;
    uint256 user1PrivateKey;

    address public user2 = makeAddr("user2");

    uint256 public constant USER_MINT_AMOUNT = 100 ether;

    function setUp() public {
        anchorUSD = new AnchorUSD(anchorEngine, feeReceiver);
        (user1, user1PrivateKey) = makeAddrAndKey("user1");

        // Mint tokens to user
        vm.prank(anchorEngine);
        anchorUSD.mint(user1, USER_MINT_AMOUNT);
    }

    function test_ItPermitsAndApprovesSpenderCorrectlyAndIncrementsNonce()
        public
    {
        uint256 value = 100 * 10 ** 18; // Approve 100 tokens
        uint256 nonce = anchorUSD.nonces(user1);
        uint256 deadline = block.timestamp + 1 days;

        bytes32 digest = _getPermitDigest(user1, user2, value, nonce, deadline);

        // Sign the digest with the owner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1PrivateKey, digest);

        // Call permit with the signature
        vm.prank(user2);
        anchorUSD.permit(user1, user2, value, deadline, v, r, s);

        // Check allowance
        uint256 allowance = anchorUSD.allowance(user1, user2);
        assertEq(allowance, value);

        // Check nonce increment
        assertEq(anchorUSD.nonces(user1), nonce + 1);
    }

    function _getPermitDigest(
        address owner_,
        address spender_,
        uint256 value_,
        uint256 nonce_,
        uint256 deadline_
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner_,
                spender_,
                value_,
                nonce_,
                deadline_
            )
        );

        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    anchorUSD.DOMAIN_SEPARATOR(),
                    structHash
                )
            );
    }
}
