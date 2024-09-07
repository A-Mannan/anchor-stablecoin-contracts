// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {VyperDeployer} from "../lib/utils/VyperDeployer.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ICurveLPToken} from "../src/interfaces/ICurveLPToken.sol";

contract DeployEthStEthPool is VyperDeployer, Script {
    address[2] public tokenAddresses;

    function run()
        public
        returns (
            address LPTokenAddr,
            address ethStEthPoolAddr,
            HelperConfig helperConfig
        )
    {
        helperConfig = new HelperConfig(); // This comes with our mocks!

        (address stEth, , uint256 deployerKey) = helperConfig
            .activeNetworkConfig();

        address ethPlaceholder = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        tokenAddresses = [ethPlaceholder, stEth];

        vm.startBroadcast(deployerKey);

        LPTokenAddr = deployContract(
            "src/curve/CurveTokenV3.vy",
            abi.encode("Curve.fi ETH/stETH", "steCRV")
        );
        ethStEthPoolAddr = deployContract(
            "src/curve/StableSwapSTETH.vy",
            abi.encode(
                msg.sender,
                tokenAddresses,
                LPTokenAddr,
                200,
                1000000,
                5000000000
            )
        );

        ICurveLPToken(LPTokenAddr).set_minter(ethStEthPoolAddr);

        vm.stopBroadcast();
    }
}
