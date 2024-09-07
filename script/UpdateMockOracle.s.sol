// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import "forge-std/console.sol";

contract DeployMocks is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant NEW_ANSWER = 3000e8;

    address public constant MOCK_ETH_USD_PRICE_FEED = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (, , uint256 deployerKey) = helperConfig.activeNetworkConfig();


        MockV3Aggregator mockPriceFeed = MockV3Aggregator(MOCK_ETH_USD_PRICE_FEED);

        vm.startBroadcast(deployerKey);
        mockPriceFeed.updateAnswer(NEW_ANSWER);
        vm.stopBroadcast();
    }
}
