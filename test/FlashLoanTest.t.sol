// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";
import {MockFlashLoanReceiver} from "../src/mocks/MockFlashLoanReceiver.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract FlashLoanTest is Test {
    AnchorUSD public anchorUSD;
    address public anchorEngine = makeAddr("anchorEngine");
    address public feeReceiver = makeAddr("feeReceiver");

    IERC3156FlashBorrower public flashLoanReceiver;
    address public user = makeAddr("user");

    uint256 public constant FLASH_LOAN_AMOUNT = 1_000_000e18;

    uint256 public constant FLASH_LOAN_FEE = 9; // 1 = 0.0001%

    function _flashFee(address, uint256 value) internal pure returns (uint256) {
        return (value * FLASH_LOAN_FEE) / 100_00;
    }

    function setUp() public {
        anchorUSD = new AnchorUSD(anchorEngine, feeReceiver);
        flashLoanReceiver = new MockFlashLoanReceiver(user, address(anchorUSD));
        uint256 flashLoanFee = _flashFee(address(anchorUSD), FLASH_LOAN_AMOUNT);

        vm.startPrank(anchorEngine);
        anchorUSD.mint(user, 1000 * 10 ** 18);
        anchorUSD.mint(address(flashLoanReceiver), flashLoanFee);
        vm.stopPrank();

        
    }

    function test_FlashLoanExecutesCorrectlyAndMaintainsSupply() public {
        uint256 initialFeeReceiverBalance = anchorUSD.balanceOf(feeReceiver);
        uint256 initialFlashLoanReceiverBalance = anchorUSD.balanceOf(
            address(flashLoanReceiver)
        );
        uint256 initialTotalSupply = anchorUSD.totalSupply();

        uint256 flashLoanFee = _flashFee(address(anchorUSD), FLASH_LOAN_AMOUNT);

        // Flash loan receiver is a contract that implements IERC3156FlashBorrower interface
        vm.prank(user);
        anchorUSD.flashLoan(
            flashLoanReceiver,
            address(anchorUSD),
            FLASH_LOAN_AMOUNT,
            ""
        );

        uint256 endingFeeReceiverBalance = anchorUSD.balanceOf(feeReceiver);
        uint256 endingFlashLoanReceiverBalance = anchorUSD.balanceOf(
            address(flashLoanReceiver)
        );
        uint256 endingTotalSupply = anchorUSD.totalSupply();

        assertEq(
            endingFeeReceiverBalance,
            initialFeeReceiverBalance + flashLoanFee
        );
        assertEq(
            endingFlashLoanReceiverBalance,
            initialFlashLoanReceiverBalance - flashLoanFee
        );
        assertEq(endingTotalSupply, initialTotalSupply);
    }
}
