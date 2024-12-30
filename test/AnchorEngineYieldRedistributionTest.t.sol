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
    address public buyer = makeAddr("buyer");

    function setUp() public override {
        super.setUp();
        if (block.chainid == 31337) {
            vm.deal(buyer, STARTING_USER_BALANCE);
        }
    }

    modifier WhenUserDepositedCollateralAndMintedAnchorUSD() {
        vm.prank(user);
        anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
            user,
            USER_MINT_AMOUNT
        );
        _;
    }

    modifier WhenMultipleUsersDepositedCollateralAndMintedAnchorUSD() {
        for (
            uint160 depositerIndex = 1;
            depositerIndex < 10;
            depositerIndex++
        ) {
            hoax(address(depositerIndex), STARTING_USER_BALANCE);
            anchorEngine.depositEtherToMint{value: USER_SUBMIT_AMOUNT}(
                address(depositerIndex),
                USER_MINT_AMOUNT
            );
        }
        _;
    }

    modifier WhenStETHRebasesRewards() {
        // vm.deal(address(stEth), 10 ether);
        vm.prank(stEth.owner());
        stEth.accumulateRewards(10 ether);
        _;
    }

    function _fundWithAnchorUsd(address _user, uint256 _amount) private {
        vm.prank(address(anchorEngine));
        anchorUSD.mint(_user, _amount);
    }

    function test_UserCanBuyStEthIncomeAndTriggerRebaseRedemption()
        public
        WhenMultipleUsersDepositedCollateralAndMintedAnchorUSD
        WhenStETHRebasesRewards
    {
        // Arrange
        uint256 initialBuyerStEthEBalance = stEth.balanceOf(buyer);
        uint256 auctionYieldAmount = stEth.balanceOf(address(anchorEngine)) -
            anchorEngine.totalDepositedEther();

        // Act
        vm.warp(2 days + 13 hours);

        uint256 dutchAuctionDiscountPrice = anchorEngine
            .getDutchAuctionDiscountPrice();
        uint256 auctionPaymentAmount = (auctionYieldAmount *
            anchorEngine.fetchEthPriceInUsd() *
            dutchAuctionDiscountPrice) /
            10_000 /
            1e18;

        _fundWithAnchorUsd(buyer, auctionPaymentAmount);

        vm.startPrank(buyer);

        anchorUSD.approve(address(anchorEngine), auctionPaymentAmount);
        anchorEngine.harvestAndAuctionYield(auctionYieldAmount);

        vm.stopPrank();

        // Assert
        assertGt(stEth.balanceOf(buyer), initialBuyerStEthEBalance);
        for (
            uint160 depositerIndex = 1;
            depositerIndex < 10;
            depositerIndex++
        ) {
            assertGt(
                anchorUSD.balanceOf(address(depositerIndex)),
                USER_MINT_AMOUNT
            );
        }
    }
}
