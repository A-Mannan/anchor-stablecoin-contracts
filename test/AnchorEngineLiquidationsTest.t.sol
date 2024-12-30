// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {AnchorEngine} from "../src/AnchorEngine.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {DeployAnchor} from "../script/DeployAnchor.s.sol";
import {AnchorTestFixture} from "./AnchorTestFixture.t.sol";

contract AnchorEngineLiquidationsTest is AnchorTestFixture {
    modifier WhenUserDepositedCollateralAndMintedAnchorUSD() {
        vm.prank(user);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              LIQUIDATIONS
    //////////////////////////////////////////////////////////////*/

    modifier WhenUserCollateralRateFallsBelowBadCollateralRate() {
        ethUsdPriceFeed.updateAnswer(1150e8);
        _;
    }

    modifier WhenLiquidatorHasProvidedLiquidation() {
        vm.startPrank(liquidator);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            liquidator,
            USER_MINT_AMOUNT
        );
        anchorUSD.approve(address(anchorEngine), USER_MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    struct LocalVariables__LiquidateUser {
        uint256 initialUserBorrowedAmount;
        uint256 initialUserCollateral;
        uint256 initialLiquidatorStEthBalance;
        uint256 initialLiquidatorAnchorUSDBalance;
        uint256 initialKeeperStEthBalance;
        uint256 endingUserBorrowedAmount;
        uint256 endingUserCollateral;
        uint256 endingLiquidatorStEthBalance;
        uint256 endingLiquidatorAnchorUSDBalance;
        uint256 endingKeeperStEthBalance;
        uint256 priceInUsd;
        uint256 liquidatedColl;
        uint256 debtPaidOff;
        uint256 keepersReward;
        uint256 liquidatorReward;
        uint256 userCollRatio;
    }

    // function test_UserCanBeLiquidatedWhenCollRatioFallsBelowThreshold()
    //     public
    //     WhenUserDepositedCollateralAndMintedAnchorUSD
    //     WhenLiquidatorHasProvidedLiquidation
    //     WhenUserCollateralRateFallsBelowBadCollateralRate
    // {
    //     //Arrange
    //     LocalVariables__LiquidateUser memory vars;
    //     (
    //         vars.initialUserBorrowedAmount,
    //         vars.initialUserCollateral
    //     ) = anchorEngine.userPositions(user);
    //     vars.initialLiquidatorStEthBalance = stEth.balanceOf(liquidator);
    //     vars.initialLiquidatorAnchorUSDBalance = anchorUSD.balanceOf(
    //         liquidator
    //     );
    //     vars.initialKeeperStEthBalance = stEth.balanceOf(keepers);

    //     // Act
    //     vm.prank(keepers);
    //     anchorEngine.liquidatePosition(liquidator, user, LIQUIDATION_AMOUNT);

    //     // Assert
    //     (
    //         vars.endingUserBorrowedAmount,
    //         vars.endingUserCollateral
    //     ) = anchorEngine.userPositions(user);
    //     vars.endingLiquidatorStEthBalance = stEth.balanceOf(liquidator);
    //     vars.endingLiquidatorAnchorUSDBalance = anchorUSD.balanceOf(liquidator);
    //     vars.endingKeeperStEthBalance = stEth.balanceOf(keepers);

    //     vars.priceInUsd = anchorEngine.fetchEthPriceInUsd();
    //     vars.debtPaidOff =
    //         (LIQUIDATION_AMOUNT * vars.priceInUsd) /
    //         DECIMAL_PRECISION;
    //     vars.liquidatedColl = (LIQUIDATION_AMOUNT * 11) / 10;
    //     vars.keepersReward =
    //         (LIQUIDATION_AMOUNT * anchorEngine.keeperRate()) /
    //         100;

    //     vars.liquidatorReward = vars.liquidatedColl - vars.keepersReward;

    //     assertEq(
    //         vars.endingLiquidatorStEthBalance,
    //         vars.initialLiquidatorStEthBalance + vars.liquidatorReward
    //     );
    //     assertEq(
    //         vars.endingUserBorrowedAmount,
    //         vars.initialUserBorrowedAmount - vars.debtPaidOff
    //     );
    //     assertEq(
    //         vars.endingUserCollateral,
    //         vars.initialUserCollateral - vars.liquidatedColl
    //     );
    //     assertEq(
    //         vars.endingLiquidatorAnchorUSDBalance,
    //         vars.initialLiquidatorAnchorUSDBalance - vars.debtPaidOff
    //     );
    //     assertEq(
    //         vars.endingKeeperStEthBalance,
    //         vars.initialKeeperStEthBalance + vars.keepersReward
    //     );
    // }

    function test_UserCanBeLiquidatedWhenCollRatioFallsBelowThreshold()
        public
        WhenUserDepositedCollateralAndMintedAnchorUSD
        WhenLiquidatorHasProvidedLiquidation
        WhenUserCollateralRateFallsBelowBadCollateralRate
    {
        //Arrange
        LocalVariables__LiquidateUser memory vars;
        (
            vars.initialUserBorrowedAmount,
            vars.initialUserCollateral
        ) = anchorEngine.userPositions(user);
        vars.initialLiquidatorStEthBalance = stEth.balanceOf(liquidator);
        vars.initialLiquidatorAnchorUSDBalance = anchorUSD.balanceOf(
            liquidator
        );
        vars.initialKeeperStEthBalance = stEth.balanceOf(keepers);
        vars.priceInUsd = anchorEngine.fetchEthPriceInUsd();
        vars.userCollRatio =
            (vars.initialUserCollateral * vars.priceInUsd * 100) /
            vars.initialUserBorrowedAmount;

        // Act
        vm.prank(keepers);
        anchorEngine.liquidatePosition(liquidator, user, DEBT_TO_OFFSET);

        // Assert
        (
            vars.endingUserBorrowedAmount,
            vars.endingUserCollateral
        ) = anchorEngine.userPositions(user);
        vars.endingLiquidatorStEthBalance = stEth.balanceOf(liquidator);
        vars.endingLiquidatorAnchorUSDBalance = anchorUSD.balanceOf(liquidator);
        vars.endingKeeperStEthBalance = stEth.balanceOf(keepers);

        vars.debtPaidOff = DEBT_TO_OFFSET;
            // (LIQUIDATION_AMOUNT * vars.priceInUsd * 100) /
            // vars.userCollRatio;

        vars.liquidatedColl =
            (DEBT_TO_OFFSET * vars.userCollRatio) /
            (vars.priceInUsd * 100);
        vars.keepersReward =
            (vars.liquidatedColl * anchorEngine.keeperRate() * 1e18) /
            vars.userCollRatio;

        vars.liquidatorReward = vars.liquidatedColl - vars.keepersReward;

        assertApproxEqAbs(
            vars.endingLiquidatorStEthBalance,
            vars.initialLiquidatorStEthBalance + vars.liquidatorReward,
            1
        );
        assertEq(
            vars.endingUserBorrowedAmount,
            vars.initialUserBorrowedAmount - vars.debtPaidOff
        );
        assertApproxEqAbs(
            vars.endingUserCollateral,
            vars.initialUserCollateral - vars.liquidatedColl,
            1
        );
        assertEq(
            vars.endingLiquidatorAnchorUSDBalance,
            vars.initialLiquidatorAnchorUSDBalance - vars.debtPaidOff
        );
        assertEq(
            vars.endingKeeperStEthBalance,
            vars.initialKeeperStEthBalance + vars.keepersReward
        );
    }
}
