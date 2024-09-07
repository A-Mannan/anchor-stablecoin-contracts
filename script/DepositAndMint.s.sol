// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";

contract DepositAndMint is Script {
    uint256 public constant ETH_DEPOSIT_AMOUNT = 2 ether;
    uint256 public constant MINT_AMOUNT = 2000e18;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();

        (, , uint256 deployerKey) = helperConfig.activeNetworkConfig();

        address mostRecentlyDeployedAnchorEngine = DevOpsTools
            .get_most_recent_deployment("AnchorEngine", block.chainid);

        AnchorEngine anchorEngine = AnchorEngine(
            mostRecentlyDeployedAnchorEngine
        );

        vm.startBroadcast(deployerKey);

        anchorEngine.depositEtherToMint{value: ETH_DEPOSIT_AMOUNT}(
            msg.sender,
            MINT_AMOUNT
        );

        vm.stopBroadcast();
    }
}
