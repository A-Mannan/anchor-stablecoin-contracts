// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";

contract AccumulateStETHRewards is Script {

    address public constant MOCK_STETH_ADDR=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;

    function run() public {

        MockStETH mockStEth = MockStETH(MOCK_STETH_ADDR);
        vm.startBroadcast();
        mockStEth.accumulateRewards(2 ether);
        vm.stopBroadcast();
    }
}
