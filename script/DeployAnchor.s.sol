// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AnchorUSD} from "../src/AnchorUSD.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";

contract DeployAnchor is Script {
    function getAnchorEngineAddress(
        address deployer,
        uint256 initialNonce
    ) public pure returns (address) {
        return vm.computeCreateAddress(deployer, initialNonce);
    }

    function getAnchorUSDAddress(
        address deployer,
        uint256 initialNonce
    ) public pure returns (address) {
        return vm.computeCreateAddress(deployer, initialNonce + 1);
    }

    function deployAnchorEngine(
        address deployer,
        uint256 initialNonce,
        address ethUsdPriceFeed,
        address stETH
    ) public returns (AnchorEngine) {
        return
            new AnchorEngine(
                stETH,
                ethUsdPriceFeed,
                getAnchorUSDAddress(deployer, initialNonce)
            );
    }

    function deployAnchorUSD(
        address deployer,
        uint256 initialNonce
    ) public returns (AnchorUSD) {
        return new AnchorUSD(getAnchorEngineAddress(deployer, initialNonce), msg.sender);
    }

    function run() external returns (address, address, address, address) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address stETH,
            address ethUsdPriceFeed,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        address deployer = vm.addr(deployerKey);
        uint256 initialNonce = vm.getNonce(deployer);

        vm.startBroadcast(deployerKey);
        AnchorEngine anchorEngine = deployAnchorEngine(
            deployer,
            initialNonce,
            ethUsdPriceFeed,
            stETH
        );
        AnchorUSD anchorUSD = deployAnchorUSD(deployer, initialNonce);
        vm.stopBroadcast();

        return (
            address(anchorEngine),
            address(anchorUSD),
            stETH,
            ethUsdPriceFeed
        );
    }
}

// ANVIL
// == Return ==
// 0: address 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
// 1: address 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
// 2: address 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
// 3: address 0x5FbDB2315678afecb367f032d93F642f64180aa3