// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";

contract LiquidatePosition is Script {
    uint256 public constant DEBT_PAYMENT = 100e18;

    address public ANCHOR_ENGINE_ADDR =
        0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    address public BORROWER_TO_LIQUIDATE =
        0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
        // 0x15d34aaf54267db7d7c367839aaf71a00a2c6a65
    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (, , uint256 deployerKey) = helperConfig.activeNetworkConfig();

        // address mostRecentlyDeployedAnchorEngine = DevOpsTools
        //     .get_most_recent_deployment("AnchorEngine", block.chainid);

        address mostRecentlyDeployedAnchorEngine = ANCHOR_ENGINE_ADDR;

        AnchorEngine anchorEngine = AnchorEngine(
            mostRecentlyDeployedAnchorEngine
        );

        vm.startBroadcast(deployerKey);

        anchorEngine.liquidatePosition(
            vm.addr(deployerKey),
            BORROWER_TO_LIQUIDATE,
            DEBT_PAYMENT,
            0
        );

        vm.stopBroadcast();
    }
}
