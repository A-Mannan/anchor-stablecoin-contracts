// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";

contract DepositAndMintMultipleUsers is Script {

    address public ANCHOR_ENGINE_ADDR =
        0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    struct User {
        uint256 privateKey;
        uint256 feeRateBps;
        uint256 redemptionAmount; 
    }

    // Define user data
    User[] users;

    function setUp() public {
        users.push(
            User(
                0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
                150, //1.5%
                1000*1e18
            )
        );
        users.push(
            User(
                0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a,
                200, //2%
                4000*1e18
            )
        );
        users.push(
            User(
                0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba,
                250, //2.5%
                2000*1e18
            )
        );
        users.push(
            User(
                0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e,
                50, //0.5%
                3000*1e18
            )
        );
        users.push(
            User(
                0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356,
                100, //1%
                1500*1e18
            )
        );
        users.push(
            User(
                0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6,
                300, //3%
                4000*1e18
            )
        );
        users.push(
            User(
                0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd,
                25, //0.25%
                2000*1e18
            )
        );
    }

    function run() external {
        // address mostRecentlyDeployedAnchorEngine = DevOpsTools
        //     .get_most_recent_deployment("AnchorEngine", block.chainid);

        address mostRecentlyDeployedAnchorEngine = ANCHOR_ENGINE_ADDR;

        AnchorEngine anchorEngine = AnchorEngine(
            mostRecentlyDeployedAnchorEngine
        );

        for (uint256 i = 0; i < users.length; i++) {
            User memory user = users[i];

            vm.startBroadcast(user.privateKey);
            anchorEngine.becomeRedemptionProvider(
                user.feeRateBps,
                user.redemptionAmount
            );
            vm.stopBroadcast();
        }
    }
}
