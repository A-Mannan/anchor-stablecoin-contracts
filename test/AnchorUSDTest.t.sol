// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/AnchorUSD.sol";

contract AnchorUSDTest is Test {
    AnchorUSD public anchorUSD;
    address public anchorEngine = makeAddr("anchorEngine");
    address public feeReceiver = makeAddr("feeReceiver");

    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public attacker = makeAddr("attacker");

    uint256 public constant USER_MINT_AMOUNT = 100 ether;

    function setUp() public {
        anchorUSD = new AnchorUSD(anchorEngine, feeReceiver);
    }

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    function test_ItInitializesNameAndSymbolCorrectly() public view {
        assertEq(anchorUSD.name(), "AnchorUSD");
        assertEq(anchorUSD.symbol(), "AnchorUSD");
    }

    function test_ItInitializesDecimalsCorrectly() public view {
        assertEq(anchorUSD.decimals(), 18);
    }

    function test_ItInitializesTotalSupplyCorrectly() public view {
        assertEq(anchorUSD.totalSupply(), 0);
    }

    function test_ItInitializesTotalSharesCorrectly() public view {
        assertEq(anchorUSD.getTotalShares(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                MINTING
    //////////////////////////////////////////////////////////////*/

    function test_AnchorEngineCanMintAnchorUSDToUser() public {
        uint256 mintAmount = 100 ether;
        uint256 sharesAmount = anchorUSD.getSharesByMintedAnchorUSD(mintAmount);
        vm.prank(anchorEngine);
        anchorUSD.mint(user1, mintAmount);

        assertEq(anchorUSD.totalSupply(), mintAmount);
        assertEq(anchorUSD.getTotalShares(), sharesAmount);

        assertEq(anchorUSD.sharesOf(user1), sharesAmount);
        assertEq(anchorUSD.balanceOf(user1), mintAmount);
    }

    function test_RevertWhen_UnauthorizedCallerMintsAnchorUSD() public {
        uint256 mintAmount = 100 ether;

        vm.startPrank(attacker);

        vm.expectRevert();
        anchorUSD.mint(user1, mintAmount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                BURNING
    //////////////////////////////////////////////////////////////*/

    modifier WhenAnchorEngineMintedAnchorUSDToUser() {
        vm.prank(anchorEngine);
        anchorUSD.mint(user1, USER_MINT_AMOUNT);
        _;
    }

    function test_AnchorEngineCanBurnAnchorUSDOfUser()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        uint256 initialTotalSupply = anchorUSD.totalSupply();
        uint256 initialTotalShares = anchorUSD.getTotalShares();
        uint256 initialUserShares = anchorUSD.sharesOf(user1);
        uint256 initialUserAnchorUsdBalance = anchorUSD.balanceOf(user1);

        uint256 burnAmount = 50 ether;

        uint256 sharesToBurn = anchorUSD.getSharesByMintedAnchorUSD(burnAmount);
        vm.prank(anchorEngine);
        anchorUSD.burn(user1, burnAmount);

        uint256 endingTotalSupply = anchorUSD.totalSupply();
        uint256 endingTotalShares = anchorUSD.getTotalShares();
        uint256 endingUserShares = anchorUSD.sharesOf(user1);
        uint256 endingUserAnchorUsdBalance = anchorUSD.balanceOf(user1);

        assertEq(endingTotalSupply, initialTotalSupply - burnAmount);
        assertEq(endingTotalShares, initialTotalShares - sharesToBurn);
        assertEq(endingUserShares, initialUserShares - sharesToBurn);
        assertEq(
            endingUserAnchorUsdBalance,
            initialUserAnchorUsdBalance - burnAmount
        );
    }

    function test_RevertWhen_UnauthorizedCallerBurnsAnchorUSD()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        uint256 burnAmount = 100 ether;

        vm.startPrank(attacker);

        vm.expectRevert();
        anchorUSD.burn(user1, burnAmount);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                TRANSFER
    //////////////////////////////////////////////////////////////*/

    function test_User1CanTransferAnchorUsdToUser2Correctly()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        uint256 initialUser1AnchorUsdBalance = anchorUSD.balanceOf(user1);
        uint256 initialUser2AnchorUsdBalance = anchorUSD.balanceOf(user2);

        uint256 initialUser1Shares = anchorUSD.sharesOf(user1);
        uint256 initialUser2Shares = anchorUSD.sharesOf(user2);

        uint256 transferAmount = 40 ether;
        uint256 sharesToTransfer = anchorUSD.getSharesByMintedAnchorUSD(
            transferAmount
        );
        vm.prank(user1);
        anchorUSD.transfer(user2, transferAmount);

        uint256 endingUser1AnchorUsdBalance = anchorUSD.balanceOf(user1);
        uint256 endingUser2AnchorUsdBalance = anchorUSD.balanceOf(user2);

        uint256 endingUser1Shares = anchorUSD.sharesOf(user1);
        uint256 endingUser2Shares = anchorUSD.sharesOf(user2);

        assertEq(
            endingUser1AnchorUsdBalance,
            initialUser1AnchorUsdBalance - transferAmount
        );
        assertEq(
            endingUser2AnchorUsdBalance,
            initialUser2AnchorUsdBalance + transferAmount
        );

        assertEq(endingUser1Shares, initialUser1Shares - sharesToTransfer);
        assertEq(endingUser2Shares, initialUser2Shares + sharesToTransfer);
    }

    function test_RevertWhen_UserHasInsufficientBalanceToTransfer()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        vm.startPrank(user1);

        vm.expectRevert();
        anchorUSD.transfer(user2, USER_MINT_AMOUNT + 1 ether);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    function test_UserCanApproveAndGiveAllowanceToOther()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        uint256 approveAmount = 60 ether;

        vm.prank(user1);
        anchorUSD.approve(user2, approveAmount);

        assertEq(anchorUSD.allowance(user1, user2), approveAmount);
    }

    modifier WhenUser1ApprovesAnchorUSDToUser2() {
        uint256 approveAmount = 40 ether;
        vm.prank(user1);
        anchorUSD.approve(user2, approveAmount);
        _;
    }

    function test_UserCanIncreaseAllowanceOfOtherUser()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
        WhenUser1ApprovesAnchorUSDToUser2
    {
        uint256 initialUser2Allowance = anchorUSD.allowance(user1, user2);
        uint256 increaseAmount = 20 ether;

        vm.prank(user1);
        anchorUSD.increaseAllowance(user2, increaseAmount);

        uint256 endingUser2Allowance = anchorUSD.allowance(user1, user2);

        assertEq(endingUser2Allowance, initialUser2Allowance + increaseAmount);
    }

    function test_UserCanDecreaseAllowanceOfOtherUser()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
        WhenUser1ApprovesAnchorUSDToUser2
    {
        uint256 initialUser2Allowance = anchorUSD.allowance(user1, user2);
        uint256 increaseAmount = 20 ether;

        vm.prank(user1);
        anchorUSD.decreaseAllowance(user2, increaseAmount);

        uint256 endingUser2Allowance = anchorUSD.allowance(user1, user2);

        assertEq(endingUser2Allowance, initialUser2Allowance - increaseAmount);
    }

    /*//////////////////////////////////////////////////////////////
                             TRANSFER FROM
    //////////////////////////////////////////////////////////////*/

    function test_User2CanTransferFromUser1FromApprovedAmount()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
        WhenUser1ApprovesAnchorUSDToUser2
    {
        uint256 initialUser1AnchorUsdBalance = anchorUSD.balanceOf(user1);
        uint256 initialUser2AnchorUsdBalance = anchorUSD.balanceOf(user2);

        uint256 initialUser1Shares = anchorUSD.sharesOf(user1);
        uint256 initialUser2Shares = anchorUSD.sharesOf(user2);

        uint256 initialUser2Allowance = anchorUSD.allowance(user1, user2);

        uint256 transferAmount = 40 ether;
        uint256 sharesToTransfer = anchorUSD.getSharesByMintedAnchorUSD(
            transferAmount
        );
        vm.prank(user2);
        anchorUSD.transferFrom(user1, user2, transferAmount);

        uint256 endingUser1AnchorUsdBalance = anchorUSD.balanceOf(user1);
        uint256 endingUser2AnchorUsdBalance = anchorUSD.balanceOf(user2);

        uint256 endingUser1Shares = anchorUSD.sharesOf(user1);
        uint256 endingUser2Shares = anchorUSD.sharesOf(user2);

        uint256 endingUser2Allowance = anchorUSD.allowance(user1, user2);

        assertEq(
            endingUser1AnchorUsdBalance,
            initialUser1AnchorUsdBalance - transferAmount
        );
        assertEq(
            endingUser2AnchorUsdBalance,
            initialUser2AnchorUsdBalance + transferAmount
        );

        assertEq(endingUser1Shares, initialUser1Shares - sharesToTransfer);
        assertEq(endingUser2Shares, initialUser2Shares + sharesToTransfer);

        assertEq(endingUser2Allowance, initialUser2Allowance - transferAmount);
    }


    /*//////////////////////////////////////////////////////////////
                      BURN SHARES AND REDISTRIBUTE
    //////////////////////////////////////////////////////////////*/

    function test_AnchorEngineCanBurnOnlySharesAndRedistribute()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        // Arrange
        for (uint160 userIdx = 1; userIdx < 10; userIdx++) {
            address user = address(userIdx);
            vm.prank(anchorEngine);
            anchorUSD.mint(user, USER_MINT_AMOUNT);
        }

        uint256 initialTotalShares = anchorUSD.getTotalShares();
        uint256 initialTotalSupply = anchorUSD.totalSupply();
        uint256 initialUser1Shares = anchorUSD.sharesOf(user1);

        // Act
        uint256 burnAmount = 50e18; // 50 debtToken
        uint256 sharesToBurn = anchorUSD.getSharesByMintedAnchorUSD(burnAmount);

        vm.prank(anchorEngine);
        anchorUSD.burnShares(user1, sharesToBurn);

        // Assert

        uint256 endingTotalShares = anchorUSD.getTotalShares();
        uint256 endingTotalSupply = anchorUSD.totalSupply();
        uint256 endingUser1Shares = anchorUSD.sharesOf(user1);

        assertLt(anchorUSD.balanceOf(user1), USER_MINT_AMOUNT);
        assertEq(
            initialTotalSupply,
            endingTotalSupply,
            "Total supply should be same"
        );
        assertEq(endingTotalShares, initialTotalShares - sharesToBurn);

        assertEq(endingUser1Shares, initialUser1Shares - sharesToBurn);

        for (uint160 userIdx = 1; userIdx < 10; userIdx++) {
            address user = address(userIdx);
            assertGt(anchorUSD.balanceOf(user), USER_MINT_AMOUNT);
        }
    }

    function test_RevertWhen_UnauthorizedCallerBurnsShares()
        public
        WhenAnchorEngineMintedAnchorUSDToUser
    {
        uint256 burnAmount = 50e18; // 50 debtToken
        uint256 sharesToBurn = anchorUSD.getSharesByMintedAnchorUSD(burnAmount);
        vm.startPrank(attacker);
        vm.expectRevert();
        anchorUSD.burnShares(user1, sharesToBurn);
        vm.stopPrank();
    }
}
