// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";

contract RegisterProvider is Script {
    uint256 public constant REDEMPTION_AMOUNT = 100e18;
    uint256 public constant FEE_RATE = 400;

    address public ANCHOR_ENGINE_ADDR = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

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

        anchorEngine.becomeRedemptionProvider(
            FEE_RATE,
            REDEMPTION_AMOUNT
        );

        vm.stopBroadcast();
    }
}
