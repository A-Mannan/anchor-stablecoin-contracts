// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";
import {AnchorEngine} from "../src/AnchorEngine.sol";

contract DepositAndMintMultipleUsers is Script {
    uint256 public constant ETH_DEPOSIT_AMOUNT = 2 ether;
    uint256 public constant MINT_AMOUNT = 2000e18;

    address public ANCHOR_ENGINE_ADDR =
        0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;

    // Define a struct for user data
    struct User {
        uint256 privateKey;
        uint256 collateral; // ETH amount to deposit
        uint256 debt; // Anchor USD amount to mint
    }

    // Define user data
    User[] users;

    function setUp() public {
        users.push(
            User(
                0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80,
                1 ether,
                1000*1e18
            )
        );
        users.push(
            User(
                0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d,
                2 ether,
                800*1e18
            )
        );
        users.push(
            User(
                0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a,
                3 ether,
                1200*1e18
            )
        );
        users.push(
            User(
                0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6,
                5 ether,
                2500*1e18
            )
        );
        users.push(
            User(
                0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a,
                6 ether,
                8000*1e18
            )
        );
        users.push(
            User(
                0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba,
                5 ether,
                4000*1e18
            )
        );
        users.push(
            User(
                0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e,
                5 ether,
                7000*1e18
            )
        );
        users.push(
            User(
                0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356,
                4 ether,
                3000*1e18
            )
        );
        users.push(
            User(
                0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97,
                2 ether,
                1000*1e18
            )
        );
        users.push(
            User(
                0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6,
                7 ether,
                6000*1e18
            )
        );
        users.push(
            User(
                0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897,
                4 ether,
                2500*1e18
            )
        );
        users.push(
            User(
                0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82,
                3 ether,
                1000*1e18
            )
        );
        users.push(
            User(
                0xa267530f49f8280200edf313ee7af6b827f2a8bce2897751d06a843f644967b1,
                1 ether,
                1500*1e18
            )
        );
        users.push(
            User(
                0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd,
                2.5 ether,
                3000*1e18
            )
        );
        users.push(
            User(
                0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa,
                3.25 ether,
                1500*1e18
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

            // Deposit ETH collateral
            vm.startBroadcast(user.privateKey);
            anchorEngine.depositEtherToMint{value: user.collateral}(
                vm.addr(user.privateKey),
                user.debt
            );
            vm.stopBroadcast();
        }

    }
}