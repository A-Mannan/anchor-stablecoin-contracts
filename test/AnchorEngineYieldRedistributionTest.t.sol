// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {AnchorEngine} from "../src/AnchorEngine.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {DeployAnchor} from "../script/DeployAnchor.s.sol";
import {AnchorTestFixture} from "./AnchorTestFixture.t.sol";

contract AnchorEngineYieldRedistributionTest is AnchorTestFixture {
    modifier WhenUserDepositedCollateralAndMintedAnchorUSD() {
        vm.prank(user);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );
        _;
    }

    function test_UserCanBuyStEthIncomeAndTriggerRebaseRedemption()
        public
        WhenUserDepositedCollateralAndMintedAnchorUSD
    {
        // Arrange
        uint256 otherDepositersMintAmount = 1e18;
        for (
            uint160 depositerIndex = 1;
            depositerIndex < 10;
            depositerIndex++
        ) {
            hoax(address(depositerIndex), STARTING_USER_BALANCE);
            anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
                address(depositerIndex),
                otherDepositersMintAmount
            );
        }

        uint256 initialUserStEthEBalance = stEth.balanceOf(user);

        // Act

        vm.warp(10 days);

        vm.startPrank(user);

        anchorUSD.approve(address(anchorEngine), PAYOUT_AMOUNT);
        anchorEngine.excessIncomeDistribution(PAYOUT_AMOUNT); // Trigger rebase

        vm.stopPrank();
        // Assert

        assertGt(stEth.balanceOf(user), initialUserStEthEBalance);
        for (
            uint160 depositerIndex = 1;
            depositerIndex < 10;
            depositerIndex++
        ) {
            assertGt(
                anchorUSD.balanceOf(address(depositerIndex)),
                otherDepositersMintAmount
            );
        }
    }
}
