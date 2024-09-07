// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";

contract DeployMockStEth is Script {
    function run() public returns (MockStETH) {

        vm.startBroadcast();
        MockStETH mockStEth = new MockStETH();
        vm.stopBroadcast();
        return mockStEth;
    }
}
