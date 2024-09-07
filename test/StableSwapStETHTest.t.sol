// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ICurveLPToken} from "../src/interfaces/ICurveLPToken.sol";
import {IStableSwapSTETH} from "../src/interfaces/IStableSwapSTETH.sol";
import {DeployEthStEthPool} from "../script/DeployEthStEthPool.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockStETH} from "../src/mocks/MockStETH.sol";

contract StableSwapStETHTest is Test {
    ICurveLPToken public lpToken;
    IStableSwapSTETH public ethStethPool;

    MockStETH public mockStEth;

    address public user = makeAddr("user");
    address public liquidityProvider = makeAddr("liquidityProvider");

    uint256 public constant STARTING_USER_BALANCE = 100 ether;

    uint256 public constant LP_DEPOSIT_AMOUNT = 1 ether;

    function setUp() public {
        DeployEthStEthPool deployer = new DeployEthStEthPool();
        (
            address lpTokenAddr,
            address ethStethPoolAddr,
            HelperConfig helperConfig
        ) = deployer.run();
        lpToken = ICurveLPToken(lpTokenAddr);
        ethStethPool = IStableSwapSTETH(ethStethPoolAddr);

        (address stEthAddr, ,) = helperConfig.activeNetworkConfig();
        mockStEth = MockStETH(stEthAddr);

        if (block.chainid == 31337) {
            hoax(liquidityProvider, 2 * STARTING_USER_BALANCE);
            mockStEth.submit{value: STARTING_USER_BALANCE}(address(0));

            hoax(user, 2 * STARTING_USER_BALANCE);
            mockStEth.submit{value: STARTING_USER_BALANCE}(address(0));
        }
    }

    /*//////////////////////////////////////////////////////////////
                          ADD & REMOVE LIQUIDITY
    //////////////////////////////////////////////////////////////*/

    function test_LiquidityProviderCanAddLiquidityIntoPool() public {
        // Arrange
        uint256 initialEthBalance = liquidityProvider.balance;
        uint256 initialStEthBalance = mockStEth.balanceOf(liquidityProvider);
        uint256 initialLpTokenBalance = lpToken.balanceOf(liquidityProvider);

        uint256 ethDepositAmount = 1 ether;
        uint256 stEthDepositAmount = 1 ether;
        uint256 minLPMintAmount = 1 ether;

        // Act
        vm.startPrank(liquidityProvider);
        uint256[2] memory amounts = [ethDepositAmount, stEthDepositAmount];
        mockStEth.approve(address(ethStethPool), stEthDepositAmount);

        uint256 minted = ethStethPool.add_liquidity{value: ethDepositAmount}(
            amounts,
            minLPMintAmount
        );
        vm.stopPrank();

        // Assert
        uint256 endingEthBalance = liquidityProvider.balance;
        uint256 endingStEthBalance = mockStEth.balanceOf(liquidityProvider);
        uint256 endingLpTokenBalance = lpToken.balanceOf(liquidityProvider);

        assertEq(initialEthBalance, endingEthBalance + ethDepositAmount);
        assertEq(initialStEthBalance, endingStEthBalance + stEthDepositAmount);
        assertEq(initialLpTokenBalance, endingLpTokenBalance - minted);
    }

    modifier WhenLPProvidedLiquidityInPool() {
        vm.startPrank(liquidityProvider);

        uint256[2] memory amounts = [uint256(1 ether), uint256(1 ether)];

        mockStEth.approve(address(ethStethPool), 1 ether);
        uint256 minMintAmount = 1 ether;

        uint256 minted = ethStethPool.add_liquidity{value: 1 ether}(
            amounts,
            minMintAmount
        );
        vm.stopPrank();
        _;
    }

    function test_LiquidityProviderCanRemoveLiquidityFromPool()
        public
        WhenLPProvidedLiquidityInPool
    {
        // Arrange
        uint256 initialEthBalance = liquidityProvider.balance;
        uint256 initialStEthBalance = mockStEth.balanceOf(liquidityProvider);
        uint256 initialLpTokenBalance = lpToken.balanceOf(liquidityProvider);

        uint256 ethMinWithdrawAmount = 0.5 ether;
        uint256 stEthMinWithdrawAmount = 0.5 ether;

        uint256 lpAmountToDeposit = 1 ether;
        uint256[2] memory minAmounts = [
            ethMinWithdrawAmount,
            stEthMinWithdrawAmount
        ];

        // Act
        vm.prank(liquidityProvider);
        uint256[2] memory tokenAmounts = ethStethPool.remove_liquidity(
            lpAmountToDeposit,
            minAmounts
        );

        // Assert
        uint256 endingEthBalance = liquidityProvider.balance;
        uint256 endingStEthBalance = mockStEth.balanceOf(liquidityProvider);
        uint256 endingLpTokenBalance = lpToken.balanceOf(liquidityProvider);

        assertEq(initialEthBalance, endingEthBalance - tokenAmounts[0]);
        assertEq(initialStEthBalance, endingStEthBalance - tokenAmounts[1]);
        assertEq(
            initialLpTokenBalance,
            endingLpTokenBalance + lpAmountToDeposit
        );

        emit log_named_uint("ETH withdrawn", tokenAmounts[0]);
        emit log_named_uint("STETH withdrawn", tokenAmounts[1]);
    }

    /*//////////////////////////////////////////////////////////////
                                EXCHANGE
    //////////////////////////////////////////////////////////////*/

    function test_UserCanExhangeEthForStEthFromPool()
        public
        WhenLPProvidedLiquidityInPool
    {
        // Arrange
        uint256 initialUserEthBalance = user.balance;
        uint256 initialUserStEthBalance = mockStEth.balanceOf(user);

        uint256 dx = 0.5 ether;
        uint256 min_dy = 0.49 ether;

        // Act
        vm.prank(user);
        uint256 dy = ethStethPool.exchange{value: dx}(0, 1, dx, min_dy);

        emit log_named_uint("0.5 ETH exchanged for STETH =", dy);

        // Assert
        uint256 endingUserEthBalance = user.balance;
        uint256 endingUserStEthBalance = mockStEth.balanceOf(user);
        assertEq(initialUserEthBalance, endingUserEthBalance + dx);
        assertEq(initialUserStEthBalance, endingUserStEthBalance - dy);
    }

    function test_UserCanExhangeStEthForEthFromPool()
        public
        WhenLPProvidedLiquidityInPool
    {
        // Arrange
        uint256 initialUserEthBalance = user.balance;
        uint256 initialUserStEthBalance = mockStEth.balanceOf(user);

        uint256 dx = 0.5 ether;
        uint256 min_dy = 0.49 ether;

        // Act
        vm.startPrank(user);
        mockStEth.approve(address(ethStethPool), dx);
        uint256 dy = ethStethPool.exchange(1, 0, dx, min_dy);
        vm.stopPrank();

        emit log_named_uint("0.5 STETH exchanged for ETH =", dy);

        // Assert
        uint256 endingUserEthBalance = user.balance;
        uint256 endingUserStEthBalance = mockStEth.balanceOf(user);

        assertEq(initialUserEthBalance, endingUserEthBalance - dy);
        assertEq(initialUserStEthBalance, endingUserStEthBalance + dx);
    }

}
