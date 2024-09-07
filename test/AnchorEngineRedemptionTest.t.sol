// // SPDX-License-Identifier: MIT

// pragma solidity ^0.8.19;

// import {Test, console} from "forge-std/Test.sol";

// import {AnchorEngine} from "../src/AnchorEngine.sol";
// import {MockStETH} from "../src/mocks/MockStETH.sol";
// import {AnchorUSD} from "../src/AnchorUSD.sol";
// import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
// import {DeployAnchor} from "../script/DeployAnchor.s.sol";
// import {StdCheats} from "forge-std/StdCheats.sol";
// import {AnchorTestFixture} from "./AnchorTestFixture.t.sol";

// contract AnchorEngineRedemptionTest is AnchorTestFixture {

//      /*//////////////////////////////////////////////////////////////
//                                REDEMPTION
//     //////////////////////////////////////////////////////////////*/


//     modifier WhenUserDepositedCollateralAndMintedAnchorUSD() {
//         vm.prank(user);
//         anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
//             user,
//             USER_MINT_AMOUNT
//         );
//         _;
//     }


//     function test_UserCanBecomeRedemptionProvider()
//         public
//         WhenUserDepositedCollateralAndMintedAnchorUSD
//     {
//         // Arrange - Act
//         vm.prank(user);
//         anchorEngine.becomeRedemptionProvider();

//         // Assert
//         assert(anchorEngine.isRedemptionProvider(user));
//     }

//     function test_UserCanRedeemCollateralForAnchorUSD()
//         public
//         WhenUserDepositedCollateralAndMintedAnchorUSD
//     {
//         // Arrange
//         (
//             uint256 initialUserBorrowedAmount,
//             uint256 initialUserCollateral
//         ) = anchorEngine.userPositions(user);
//         vm.prank(user);
//         anchorEngine.becomeRedemptionProvider();

//         vm.startPrank(redeemer);
//         anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
//             redeemer,
//             USER_MINT_AMOUNT
//         );

//         uint256 intialRedeemerStEthBalance = stEth.balanceOf(redeemer);
//         uint256 initialRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

//         // Act
//         anchorEngine.redeemCollateral(user, REDEEM_AMOUNT);

//         vm.stopPrank();

//         // Assert
//         (
//             uint256 endingUserBorrowedAmount,
//             uint256 endingUserCollateral
//         ) = anchorEngine.userPositions(user);

//         uint256 priceInUsd = anchorEngine.fetchEthPriceInUsd();
//         uint256 redeemedCollateral = (((REDEEM_AMOUNT * 1e18) / priceInUsd) *
//             (100_00 - anchorEngine.redemptionFee())) / 100_00;

//         uint256 endingRedeemerStEthBalance = stEth.balanceOf(redeemer);

//         uint256 endingRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

//         assertEq(
//             endingRedeemerStEthBalance,
//             intialRedeemerStEthBalance + redeemedCollateral
//         );
//         assertEq(
//             endingUserBorrowedAmount,
//             initialUserBorrowedAmount - REDEEM_AMOUNT
//         );
//         assertEq(
//             endingUserCollateral,
//             initialUserCollateral - redeemedCollateral
//         );

//         assertEq(
//             endingRedeemerAnchorUSDBalance,
//             initialRedeemerAnchorUSDBalance - REDEEM_AMOUNT
//         );
//     }

//     function test_UserCanRedeemCollateralForAnchorUSDFromRedemptionProviders()
//         public
//         WhenUserDepositedCollateralAndMintedAnchorUSD
//     {
//         // Arrange
//         (
//             uint256 initialUserBorrowedAmount,
//             uint256 initialUserCollateral
//         ) = anchorEngine.userPositions(user);
//         vm.prank(user);
//         anchorEngine.becomeRedemptionProvider();

//         vm.startPrank(redeemer);
//         anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
//             redeemer,
//             USER_MINT_AMOUNT
//         );

//         uint256 intialRedeemerStEthBalance = stEth.balanceOf(redeemer);
//         uint256 initialRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

//         // Act
//         anchorEngine.redeemFromAllProviders(REDEEM_AMOUNT);

//         vm.stopPrank();

//         // Assert
//         (
//             uint256 endingUserBorrowedAmount,
//             uint256 endingUserCollateral
//         ) = anchorEngine.userPositions(user);

//         uint256 priceInUsd = anchorEngine.fetchEthPriceInUsd();
//         uint256 redeemedCollateral = (((REDEEM_AMOUNT * 1e18) / priceInUsd) *
//             (100_00 - anchorEngine.redemptionFee())) / 100_00;

//         uint256 endingRedeemerStEthBalance = stEth.balanceOf(redeemer);
//         uint256 endingRedeemerAnchorUSDBalance = anchorUSD.balanceOf(redeemer);

//         assertEq(
//             endingRedeemerStEthBalance,
//             intialRedeemerStEthBalance + redeemedCollateral
//         );
//         assertEq(
//             endingUserBorrowedAmount,
//             initialUserBorrowedAmount - REDEEM_AMOUNT
//         );
//         assertEq(
//             endingUserCollateral,
//             initialUserCollateral - redeemedCollateral
//         );
//         assertEq(
//             endingRedeemerAnchorUSDBalance,
//             initialRedeemerAnchorUSDBalance - REDEEM_AMOUNT
//         );
//     }

// }
