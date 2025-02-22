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
                1300*1e18
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

// Available Accounts
// ==================

// (0) 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 (10000.000000000000000000 ETH)
// (1) 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 (10000.000000000000000000 ETH)
// (2) 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC (10000.000000000000000000 ETH)
// (3) 0x90F79bf6EB2c4f870365E785982E1f101E93b906 (10000.000000000000000000 ETH)
// (4) 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65 (10000.000000000000000000 ETH)
// (5) 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc (10000.000000000000000000 ETH)
// (6) 0x976EA74026E726554dB657fA54763abd0C3a0aa9 (10000.000000000000000000 ETH)
// (7) 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955 (10000.000000000000000000 ETH)
// (8) 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f (10000.000000000000000000 ETH)
// (9) 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720 (10000.000000000000000000 ETH)
// (10) 0xBcd4042DE499D14e55001CcbB24a551F3b954096 (10000.000000000000000000 ETH)
// (11) 0x71bE63f3384f5fb98995898A86B02Fb2426c5788 (10000.000000000000000000 ETH)
// (12) 0xFABB0ac9d68B0B445fB7357272Ff202C5651694a (10000.000000000000000000 ETH)
// (13) 0x1CBd3b2770909D4e10f157cABC84C7264073C9Ec (10000.000000000000000000 ETH)
// (14) 0xdF3e18d64BC6A983f673Ab319CCaE4f1a57C7097 (10000.000000000000000000 ETH)

// Private Keys
// ==================

// (0) 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
// (1) 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
// (2) 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
// (3) 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
// (4) 0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
// (5) 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba
// (6) 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e
// (7) 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356
// (8) 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97
// (9) 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
// (10) 0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897
// (11) 0x701b615bbdfb9de65240bc28bd21bbc0d996645a3dd57e7b12bc2bdf6f192c82
// (12) 0xa267530f49f8280200edf313ee7af6b827f2a8bce2897751d06a843f644967b1
// (13) 0x47c99abed3324a2707c28affff1267e45918ec8c3f20b8aa892e8b065d2942dd
// (14) 0xc526ee95bf44d8fc405a158bb884d9d1238d99f0612e9f33d006bb0789009aaa