// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../src/mocks/MockV3Aggregator.sol";
import {DeployMockV3Aggregator} from "./DeployMockV3Aggregator.s.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";
import {DeployMockStEth} from "./DeployMockStEth.s.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address stETH;
        address ethUsdPriceFeed;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 5) {
            activeNetworkConfig = getGoerliEthConfig();
        }else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory sepoliaNetworkConfig) {
        // sepoliaNetworkConfig = NetworkConfig({
        //     ethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
        //     deployerKey: vm.envUint("PRIVATE_KEY")
        // });
    }

    function getGoerliEthConfig() public view returns (NetworkConfig memory goerliNetworkConfig) {
        // goerliNetworkConfig = NetworkConfig({
        //     ethUsdPriceFeed: 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e, // ETH / USD
            
        //     deployerKey: vm.envUint("PRIVATE_KEY")
        // });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.ethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        DeployMockV3Aggregator priceFeedDeployer = new DeployMockV3Aggregator();
        MockV3Aggregator ethUsdPriceFeed = priceFeedDeployer.run();

        DeployMockStEth stETHDeployer = new DeployMockStEth();
        MockStETH stETH = stETHDeployer.run();

        anvilNetworkConfig = NetworkConfig({
            stETH: address(stETH),
            ethUsdPriceFeed: address(ethUsdPriceFeed), // ETH / USD
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }

}
