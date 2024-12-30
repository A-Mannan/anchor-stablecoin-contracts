// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {AnchorEngine} from "../src/AnchorEngine.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {DeployAnchor} from "../script/DeployAnchor.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {AnchorTestFixture} from "./AnchorTestFixture.t.sol";

contract AnchorEnginePositionsTest is AnchorTestFixture {

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT AND MINT
    //////////////////////////////////////////////////////////////*/

    function test_UserCanMintAnchorUSDByDepositingETH() public {
        // Arrange
        uint256 initialAnchorUSDSupply = anchorUSD.totalSupply();
        uint256 initialETHBalance = user.balance;
        (uint256 initialUserDebt, uint256 initialUserCollateral) = anchorEngine
            .userPositions(user);
        uint256 initialBorrowersCount = anchorEngine.getBorrowersCount();


        // Act
        vm.prank(user);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );


        // Assert
        (uint256 endingUserDebt, uint256 endingUserCollateral) = anchorEngine
            .userPositions(user);
        uint256 endingBorrowersCount = anchorEngine.getBorrowersCount();


        assertGt(anchorUSD.totalSupply(), initialAnchorUSDSupply);
        assertEq(user.balance, initialETHBalance - USER_SUBMIT_AMOUNT);

        assertGt(anchorUSD.balanceOf(user), 0);
        assertEq(USER_MINT_AMOUNT, anchorUSD.balanceOf(user));

        assert(anchorEngine.isBorrower(user));

        assertEq(endingUserDebt, initialUserDebt + USER_MINT_AMOUNT);
        assertEq(
            endingUserCollateral,
            initialUserCollateral + USER_SUBMIT_AMOUNT
        );
        assertEq(endingBorrowersCount, initialBorrowersCount + 1);
    }

    function test_UserCanMintAnchorUSDByDepositingStETH() public {
        // Arrange
        uint256 initialETHBalance = user.balance;
        uint256 initialAnchorUSDSupply = anchorUSD.totalSupply();
        uint256 stETHAmountToDeposit = USER_SUBMIT_AMOUNT;
        (uint256 initialUserDebt, uint256 initialUserCollateral) = anchorEngine
            .userPositions(user);
        uint256 initialBorrowersCount = anchorEngine.getBorrowersCount();

        // Act
        vm.startPrank(user);
        stEth.submit{value: USER_SUBMIT_AMOUNT}(user);

        stEth.approve(address(anchorEngine), stETHAmountToDeposit);

        anchorEngine.depositStETHToMint(
            user,
            stETHAmountToDeposit,
            USER_MINT_AMOUNT
        );

        vm.stopPrank();

        // Assert
        (uint256 endingUserDebt, uint256 endingUserCollateral) = anchorEngine
            .userPositions(user);
        uint256 endingBorrowersCount = anchorEngine.getBorrowersCount();

        assertGt(anchorUSD.totalSupply(), initialAnchorUSDSupply);
        assertEq(user.balance, initialETHBalance - USER_SUBMIT_AMOUNT);

        assertEq(anchorUSD.balanceOf(user), USER_MINT_AMOUNT);

        assert(anchorEngine.isBorrower(user));

        assertEq(endingUserDebt, initialUserDebt + USER_MINT_AMOUNT);
        assertEq(
            endingUserCollateral,
            initialUserCollateral + stETHAmountToDeposit
        );
        assertEq(endingBorrowersCount, initialBorrowersCount + 1);
    }

    function test_RevertWhen_MintInsufficientETH() public {
        vm.startPrank(user);
        vm.expectRevert();
        anchorEngine.depositEtherToMint{value: 0.99 ether}(
            user,
            USER_MINT_AMOUNT
        );
        vm.stopPrank();
    }

    modifier WhenUserDepositedCollateralAndMintedAnchorUSD() {
        vm.prank(user);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );
        _;
    }

    function test_ItRemovesUserFromBorrowersWhenUserWithdrawsWholeCollateral()
        public
        WhenUserDepositedCollateralAndMintedAnchorUSD
    {
        // Arrange - Act
        vm.startPrank(user);
        anchorEngine.repay(user, USER_MINT_AMOUNT);
        anchorEngine.withdraw(user, USER_SUBMIT_AMOUNT);
        vm.stopPrank();

        // Assert
        assert(!anchorEngine.isBorrower(user));
    }

    // modifier WhenUserBecameRedemptionProvider() {
    //     vm.prank(user);
    //     anchorEngine.becomeRedemptionProvider();
    //     _;
    // }

    // modifier WhenRedeemerDepositedCollateralAndMintedAnchorUSD() {
    //     vm.prank(redeemer);
    //     anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
    //         redeemer,
    //         USER_MINT_AMOUNT
    //     );
    //     _;
    // }

    // function test_ItRemovesProviderFromRedemptionProvidersWhenDebtIsRepaid()
    //     public
    //     WhenUserDepositedCollateralAndMintedAnchorUSD
    //     WhenUserBecameRedemptionProvider
    //     WhenRedeemerDepositedCollateralAndMintedAnchorUSD
    // {
    //     // Arrange - Act
    //     vm.prank(redeemer);
    //     anchorEngine.redeemCollateral(user, USER_MINT_AMOUNT);

    //     // Assert
    //     assert(!anchorEngine.isRedemptionProvider(user));
    // }
}
