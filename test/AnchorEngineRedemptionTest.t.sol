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

contract AnchorEngineRedemptionTest is AnchorTestFixture {
    struct DepositerInfo {
        uint256 collAmount;
        uint256 debtAmount;
        uint256 redemptionFeeRate;
        uint256 redemptionAmount;
    }

    struct UserBalances {
        uint256 collAmount;
        uint256 debtAmount;
        uint256 collRatio;
        uint256 redemptionAmount;
        uint256 redemptionFeeRate;
    }

    struct SystemBalances {
        uint256 totalDepositedEther;
        uint256 totalAnchorUSDCirculation;
    }

    DepositerInfo[5] public depositers;

    address redeemer = makeAddr("redeemer");

    uint256 public constant USER_REDEPMENT_FEE_BPS = 100; //1%
    uint256 public constant USER_REDEMPTION_AMOUNT = 1000e18; //$1000

    uint256 public constant BATCH_REDEEM_AMOUNT = 2000e18; //$2000

    uint256 public constant REDEEM_AMOUNT = 100e18;

    function setUp() public override {
        super.setUp();

        for (uint160 depositerIdx = 1; depositerIdx < 5; depositerIdx++) {
            address depositer = address(depositerIdx);
            vm.deal(depositer, STARTING_USER_BALANCE);
        }

        //200%
        depositers[1].collAmount = 2 ether;
        depositers[1].debtAmount = 2000e18;
        depositers[1].redemptionFeeRate = 400; //4%
        depositers[1].redemptionAmount = 500e18;

        // 250%
        depositers[2].collAmount = 4 ether;
        depositers[2].debtAmount = 3200e18;
        depositers[2].redemptionFeeRate = 300; //3%
        depositers[2].redemptionAmount = 500e18;

        // 400%
        depositers[3].collAmount = 6 ether;
        depositers[3].debtAmount = 3000e18;
        depositers[3].redemptionFeeRate = 200; //2%
        depositers[3].redemptionAmount = 1000e18;

        // 500%
        depositers[4].collAmount = 8 ether;
        depositers[4].debtAmount = 3200e18;
        depositers[4].redemptionFeeRate = 100; //1%
        depositers[4].redemptionAmount = 1500e18;
    }

    function _getUserBalances(
        address _user
    ) internal view returns (UserBalances memory) {
        (uint256 debt, uint256 coll) = anchorEngine.userPositions(_user);
        uint256 collRatio = (coll * 1e18 * 100) / debt;
        (uint256 feeRate, uint256 redemptionAmount) = anchorEngine
            .redemptionOffers(_user);
        return UserBalances(coll, debt, collRatio, redemptionAmount, feeRate);
    }

    function _getAllUserBalances()
        internal
        view
        returns (UserBalances[5] memory)
    {
        UserBalances[5] memory users;
        for (uint160 depositerIdx = 1; depositerIdx < 5; depositerIdx++) {
            users[depositerIdx] = _getUserBalances(address(depositerIdx));
        }
        return users;
    }

    function _getSystemBalances()
        internal
        view
        returns (SystemBalances memory)
    {
        return
            SystemBalances(
                anchorEngine.totalDepositedEther(),
                anchorEngine.totalAnchorUSDCirculation()
            );
    }

    /*//////////////////////////////////////////////////////////////
                               REDEMPTION
    //////////////////////////////////////////////////////////////*/

    modifier WhenUserDepositedCollateralAndMintedAnchorUSD() {
        vm.prank(user);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );
        _;
    }

    modifier WhenMultipleUsersDepositedCollateralAndMintedDebtToken() {
        for (uint160 depositerIdx = 1; depositerIdx < 5; depositerIdx++) {
            address depositer = address(depositerIdx);
            vm.prank(depositer);
            anchorEngine.depositEtherToMint{
                value: depositers[depositerIdx].collAmount
            }(depositer, depositers[depositerIdx].debtAmount);
        }
        _;
    }

    function test_UserCanBecomeRedemptionProvider()
        public
        WhenUserDepositedCollateralAndMintedAnchorUSD
    {
        // Arrange - Act

        vm.prank(user);
        anchorEngine.becomeRedemptionProvider(
            USER_REDEPMENT_FEE_BPS,
            USER_REDEMPTION_AMOUNT
        );

        (uint256 feeRate, uint256 amount) = anchorEngine.redemptionOffers(user);

        // Assert
        assert(anchorEngine.isRedemptionProvider(user));
        assertEq(feeRate, USER_REDEPMENT_FEE_BPS);
        assertEq(amount, USER_REDEMPTION_AMOUNT);
    }

    function test_MultipleUsersCanBecomeRedemptionProviders()
        public
        WhenMultipleUsersDepositedCollateralAndMintedDebtToken
    {
        for (uint160 depositerIdx = 1; depositerIdx < 5; depositerIdx++) {
            address depositer = address(depositerIdx);
            vm.prank(depositer);
            anchorEngine.becomeRedemptionProvider(
                depositers[depositerIdx].redemptionFeeRate,
                depositers[depositerIdx].redemptionAmount
            );

            (uint256 feeRate, uint256 amount) = anchorEngine.redemptionOffers(
                depositer
            );

            // Assert
            assert(anchorEngine.isRedemptionProvider(depositer));
            assertEq(feeRate, depositers[depositerIdx].redemptionFeeRate);
            assertEq(amount, depositers[depositerIdx].redemptionAmount);
        }
    }

    modifier WhenUserBecameRedemptionProvider() {
        vm.prank(user);
        anchorEngine.becomeRedemptionProvider(
            USER_REDEPMENT_FEE_BPS,
            USER_REDEMPTION_AMOUNT
        );
        _;
    }

    modifier WhenMultipleUsersBecameRedemptionProviders() {
        for (uint160 depositerIdx = 1; depositerIdx < 5; depositerIdx++) {
            address depositer = address(depositerIdx);
            vm.prank(depositer);
            anchorEngine.becomeRedemptionProvider(
                depositers[depositerIdx].redemptionFeeRate,
                depositers[depositerIdx].redemptionAmount
            );
        }
        _;
    }

    function _fundWithAnchorUsd(address _user, uint256 _amount) private {
        vm.prank(address(anchorEngine));
        anchorUSD.mint(_user, _amount);
    }

    function test_RedeemerCanRedeemCollateralForAnchorUSD()
        public
        WhenUserDepositedCollateralAndMintedAnchorUSD
        WhenUserBecameRedemptionProvider
    {
        // Arrange
        (
            uint256 initialUserBorrowedAmount,
            uint256 initialUserCollateral
        ) = anchorEngine.userPositions(user);

        _fundWithAnchorUsd(redeemer, REDEEM_AMOUNT);

        uint256 initialRedeemerStEthBalance = stEth.balanceOf(redeemer);
        uint256 initialRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

        // Act
        vm.startPrank(redeemer);

        anchorEngine.redeemCollateral(user, REDEEM_AMOUNT, 0);

        vm.stopPrank();

        // Assert
        (
            uint256 endingUserBorrowedAmount,
            uint256 endingUserCollateral
        ) = anchorEngine.userPositions(user);

        uint256 priceInUsd = anchorEngine.fetchEthPriceInUsd();
        uint256 redeemedCollateral = (((REDEEM_AMOUNT * 1e18) / priceInUsd) *
            (100_00 - USER_REDEPMENT_FEE_BPS)) / 100_00;

        uint256 endingRedeemerStEthBalance = stEth.balanceOf(redeemer);
        uint256 endingRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

        (, uint256 endingAmount) = anchorEngine.redemptionOffers(user);

        assertEq(
            endingRedeemerStEthBalance,
            initialRedeemerStEthBalance + redeemedCollateral
        );
        assertEq(
            endingUserBorrowedAmount,
            initialUserBorrowedAmount - REDEEM_AMOUNT
        );
        assertEq(
            endingUserCollateral,
            initialUserCollateral - redeemedCollateral
        );

        assertEq(
            endingRedeemerAnchorUSDBalance,
            initialRedeemerAnchorUSDBalance - REDEEM_AMOUNT
        );

        assert(anchorEngine.isRedemptionProvider(user));
        assertEq(endingAmount, USER_REDEMPTION_AMOUNT - REDEEM_AMOUNT);
    }

    function test_UserCanBeRemovedFromRedemptionProviderWhenUserAmountIsFullyRedeemed()
        public
        WhenUserDepositedCollateralAndMintedAnchorUSD
        WhenUserBecameRedemptionProvider
    {
        // Arrange - Act

        _fundWithAnchorUsd(redeemer, USER_REDEMPTION_AMOUNT);

        vm.startPrank(redeemer);

        anchorEngine.redeemCollateral(user, USER_REDEMPTION_AMOUNT, 0);

        vm.stopPrank();

        // Assert

        (uint256 feeRate, uint256 endingAmount) = anchorEngine.redemptionOffers(
            user
        );

        assert(!anchorEngine.isRedemptionProvider(user));
        assertEq(endingAmount, 0);
        assertEq(feeRate, 0);
    }

    function test_RedeemerCanBatchRedeemCollateralForAnchorUSDFromMultipleRPsBasedOnFees()
        public
        WhenMultipleUsersDepositedCollateralAndMintedDebtToken
        WhenMultipleUsersBecameRedemptionProviders
    {
        // Arrange
        address[] memory redemptionProviders = new address[](4);
        redemptionProviders[0] = address(4);
        redemptionProviders[1] = address(3);
        redemptionProviders[2] = address(2);
        redemptionProviders[3] = address(1);

        _fundWithAnchorUsd(redeemer, BATCH_REDEEM_AMOUNT);

        uint256 initialRedeemerStEthBalance = stEth.balanceOf(redeemer);
        uint256 initialRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

        UserBalances[5] memory initialUsersBalances = _getAllUserBalances();
        SystemBalances memory intitialSystemBalances = _getSystemBalances();

        // Act

        vm.startPrank(redeemer);

        anchorEngine.batchRedeemCollateral(
            redemptionProviders,
            BATCH_REDEEM_AMOUNT,
            0
        );

        vm.stopPrank();

        // Assert
        uint256 endingRedeemerStEthBalance = stEth.balanceOf(redeemer);
        uint256 endingRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

        UserBalances[5] memory endingUsersBalances = _getAllUserBalances();
        SystemBalances memory endingSystemBalances = _getSystemBalances();

        uint256 priceInUsd = anchorEngine.fetchEthPriceInUsd();
        uint256 user4RedeemedCollateral = (initialUsersBalances[4]
            .redemptionAmount *
            (100_00 - initialUsersBalances[4].redemptionFeeRate) *
            1e18) / (priceInUsd * 100_00);
        uint256 leftOverRedemptionAmount = BATCH_REDEEM_AMOUNT -
            initialUsersBalances[4].redemptionAmount;
        uint256 user3RedeemedCollateral = (leftOverRedemptionAmount *
            (100_00 - initialUsersBalances[3].redemptionFeeRate) *
            1e18) / (priceInUsd * 100_00);
        uint256 redeemedCollateral = user4RedeemedCollateral +
            user3RedeemedCollateral;

        _assertUserBalances(initialUsersBalances, endingUsersBalances);

        _assertSystemBalances(
            intitialSystemBalances,
            endingSystemBalances,
            redeemedCollateral
        );

        assertEq(
            endingRedeemerStEthBalance,
            initialRedeemerStEthBalance + redeemedCollateral
        );
        assertEq(
            endingRedeemerAnchorUSDBalance,
            initialRedeemerAnchorUSDBalance - BATCH_REDEEM_AMOUNT
        );
    }

    function _assertUserBalances(
        UserBalances[5] memory initialUsersBalances,
        UserBalances[5] memory endingUsersBalances
    ) internal view {
        uint256 priceInUsd = anchorEngine.fetchEthPriceInUsd();

        // Depositer 1
        assertEq(
            endingUsersBalances[1].debtAmount,
            initialUsersBalances[1].debtAmount
        );
        assertEq(
            endingUsersBalances[1].collAmount,
            initialUsersBalances[1].collAmount
        );
        assertEq(
            endingUsersBalances[1].collRatio,
            initialUsersBalances[1].collRatio
        );
        assertEq(
            endingUsersBalances[1].redemptionAmount,
            initialUsersBalances[1].redemptionAmount
        );
        assertEq(
            endingUsersBalances[1].redemptionFeeRate,
            initialUsersBalances[1].redemptionFeeRate
        );

        // Depositer 2
        assertEq(
            endingUsersBalances[2].debtAmount,
            initialUsersBalances[2].debtAmount
        );

        assertEq(
            endingUsersBalances[2].collAmount,
            initialUsersBalances[2].collAmount
        );
        assertEq(
            endingUsersBalances[2].collRatio,
            initialUsersBalances[2].collRatio
        );
        assertEq(
            endingUsersBalances[2].redemptionAmount,
            initialUsersBalances[2].redemptionAmount
        );
        assertEq(
            endingUsersBalances[2].redemptionFeeRate,
            initialUsersBalances[2].redemptionFeeRate
        );

        // Depositer 3 Partially redeemed
        uint256 leftOverRedemptionAmount = BATCH_REDEEM_AMOUNT -
            initialUsersBalances[4].redemptionAmount;
        uint256 user3RedeemedCollateral = (leftOverRedemptionAmount *
            (100_00 - initialUsersBalances[3].redemptionFeeRate) *
            1e18) / (priceInUsd * 100_00);

        assertEq(
            endingUsersBalances[3].debtAmount,
            initialUsersBalances[3].debtAmount - leftOverRedemptionAmount
        );

        assertEq(
            endingUsersBalances[3].collAmount,
            initialUsersBalances[3].collAmount - user3RedeemedCollateral
        );

        assertGt(
            endingUsersBalances[3].collRatio,
            initialUsersBalances[3].collRatio
        );

        assertEq(
            endingUsersBalances[3].redemptionAmount,
            initialUsersBalances[3].redemptionAmount - leftOverRedemptionAmount
        );

        assertEq(
            endingUsersBalances[3].redemptionFeeRate,
            initialUsersBalances[3].redemptionFeeRate
        );

        // Depositer 4 Fully redeemed
        uint256 user4RedeemedCollateral = (initialUsersBalances[4]
            .redemptionAmount *
            (100_00 - initialUsersBalances[4].redemptionFeeRate) *
            1e18) / (priceInUsd * 100_00);

        assertEq(
            endingUsersBalances[4].debtAmount,
            initialUsersBalances[4].debtAmount -
                initialUsersBalances[4].redemptionAmount
        );

        assertEq(
            endingUsersBalances[4].collAmount,
            initialUsersBalances[4].collAmount - user4RedeemedCollateral
        );

        assertGt(
            endingUsersBalances[4].collRatio,
            initialUsersBalances[4].collRatio
        );

        assertEq(endingUsersBalances[4].redemptionAmount, 0);

        assertEq(endingUsersBalances[4].redemptionFeeRate, 0);
    }

    function _assertSystemBalances(
        SystemBalances memory initialSystemBalances,
        SystemBalances memory endingSystemBalances,
        uint256 redeemedCollateral
    ) internal pure {
        assertEq(
            endingSystemBalances.totalAnchorUSDCirculation,
            initialSystemBalances.totalAnchorUSDCirculation -
                BATCH_REDEEM_AMOUNT
        );
        assertEq(
            endingSystemBalances.totalDepositedEther,
            initialSystemBalances.totalDepositedEther - redeemedCollateral
        );
    }
}
