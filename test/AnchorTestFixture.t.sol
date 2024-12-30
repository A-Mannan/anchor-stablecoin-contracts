// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";

import {AnchorEngine} from "../src/AnchorEngine.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {DeployAnchor} from "../script/DeployAnchor.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract AnchorTestFixture is Test {
    AnchorEngine public anchorEngine;
    AnchorUSD public anchorUSD;

    MockStETH public stEth;
    MockV3Aggregator public ethUsdPriceFeed;

    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");
    address public keepers = makeAddr("keepers");

    uint256 public constant STARTING_USER_BALANCE = 100 ether;
    uint256 public constant USER_SUBMIT_AMOUNT = 2 ether;
    uint256 public constant USER_MINT_AMOUNT = 2000e18;

    // uint256 public constant AUCTION_YIELD_AMOUNT = 1 ether;
    uint256 public constant DEBT_TO_OFFSET = 2000e18;
    uint256 public constant DECIMAL_PRECISION = 1e18;

    function setUp() public virtual {
        DeployAnchor deployer = new DeployAnchor();
        (
            address anchorEngineAddr,
            address anchorUSDAddr,
            address stEthAddr,
            address ethUsdPriceFeedAddr
        ) = deployer.run();

        anchorEngine = AnchorEngine(anchorEngineAddr);
        anchorUSD = AnchorUSD(anchorUSDAddr);
        stEth = MockStETH(stEthAddr);
        ethUsdPriceFeed = MockV3Aggregator(ethUsdPriceFeedAddr);

        if (block.chainid == 31337) {
            vm.deal(user, STARTING_USER_BALANCE);
            vm.deal(keepers, STARTING_USER_BALANCE);
            vm.deal(liquidator, STARTING_USER_BALANCE);
        }
    }
}
