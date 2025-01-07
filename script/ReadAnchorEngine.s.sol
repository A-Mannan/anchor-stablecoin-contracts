// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";
import {console} from "forge-std/console.sol";

contract ReadAnchorEngine is Script {

    address public ANCHOR_ENGINE_ADDR = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    function run() external view {

        // address mostRecentlyDeployedAnchorEngine = DevOpsTools
        //     .get_most_recent_deployment("AnchorEngine", block.chainid);

        address mostRecentlyDeployedAnchorEngine = ANCHOR_ENGINE_ADDR;

        AnchorEngine anchorEngine = AnchorEngine(
            mostRecentlyDeployedAnchorEngine
        );

        console.log("anchorEngine discount rate", anchorEngine.getDutchAuctionDiscountPrice());
    }
}
