// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IAnchorUSD} from "./interfaces/IAnchorUSD.sol";
import {Governable} from "./dependencies/Governable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";
import {IStableSwapSTETH} from "../src/interfaces/IStableSwapSTETH.sol";
import {IWithdrawalQueueERC721} from "./interfaces/IWithdrawalQueueERC721.sol";

/**
 ______                  __                      
/\  _  \                /\ \                     
\ \ \L\ \    ___     ___\ \ \___     ___   _ __  
 \ \  __ \ /' _ `\  /'___\ \  _ `\  / __`\/\`'__\
  \ \ \/\ \/\ \/\ \/\ \__/\ \ \ \ \/\ \L\ \ \ \/ 
   \ \_\ \_\ \_\ \_\ \____\\ \_\ \_\ \____/\ \_\ 
    \/_/\/_/\/_/\/_/\/____/ \/_/\/_/\/___/  \/_/ 
                                                 
                                                 
 ____                                          
/\  _`\                   __                   
\ \ \L\_\    ___      __ /\_\    ___      __   
 \ \  _\L  /' _ `\  /'_ `\/\ \ /' _ `\  /'__`\ 
  \ \ \L\ \/\ \/\ \/\ \L\ \ \ \/\ \/\ \/\  __/ 
   \ \____/\ \_\ \_\ \____ \ \_\ \_\ \_\ \____\
    \/___/  \/_/\/_/\/___L\ \/_/\/_/\/_/\/____/
                      /\____/                  
                      \_/__/   

 */

contract AnchorEngine3 is Governable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct UserPosition {
        uint256 debt;
        uint256 collateral;
    }

    struct RedemptionOffer {
        uint256 feeRate;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 public totalDepositedEther;
    uint256 public totalAnchorUSDCirculation;
    uint256 public lastReportTime;
    uint256 year = 365 days; // secs in a year

    uint256 public mintFeeApy = 150;
    uint256 public safeCollateralRatio = 160 * 1e18;
    uint256 public immutable badCollateralRatio = 150 * 1e18;
    // uint256 public redemptionFee = 50;
    uint8 public keeperRate = 1;

    mapping(address user => UserPosition position) public userPositions;

    uint256 public feeStored;

    IStETH immutable stETH;
    AggregatorV3Interface immutable priceFeed;

    IAnchorUSD public immutable anchorUSD;

    mapping(address redemptionProvider => RedemptionOffer)
        public redemptionOffers;

    EnumerableSet.AddressSet private redemptionProviders;
    EnumerableSet.AddressSet private borrowers;

    IStableSwapSTETH public ethStEthPool;

    IWithdrawalQueueERC721 public stETHWithdrawalQueue;

    uint256 public constant MAX_MINT_FEE_APY = 150; //1.5%

    uint256 public constant SAFE_COLL_RATIO_FLOOR = 160e18; //160%

    uint256 public constant MAX_KEEPERS_RATE = 5; //5%

    uint256 public constant MAX_REDEMPTION_FEE_RATE = 500; //5%

    uint256 public constant INITIAL_MIN_DEPOSIT_AMOUNT = 1 ether;

    int128 constant STETH_IDX_IN_POOL = 1; // Index for stETH in the Curve pool
    int128 constant ETH_IDX_IN_POOL = 0; // Index for ETH in the Curve pool

    uint256 constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 ether;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event BorrowApyChanged(uint256 newApy);
    event SafeCollateralRatioChanged(uint256 newRatio);
    event KeeperRateChanged(uint256 newSlippage);
    event RedemptionFeeChanged(uint256 newSlippage);
    event DepositEther(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawEther(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event Mint(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event Burn(
        address sponsor,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 timestamp
    );
    event LiquidationRecord(
        address provider,
        address keeper,
        address indexed onBehalfOf,
        uint256 anchorUSDAmount,
        uint256 LiquidateEtherAmount,
        uint256 keeperReward,
        bool superLiquidation,
        uint256 timestamp
    );
    event LSDistribution(
        uint256 stETHAdded,
        uint256 payoutAnchorUSD,
        uint256 timestamp
    );
    // event RedemptionProvider(address user, bool status);
    event RedemptionProviderRegistered(address user);
    event RedemptionProviderRemoved(address user);
    event RedeemedCollateral(
        address indexed caller,
        address indexed provider,
        uint256 anchorUSDAmount,
        uint256 etherAmount,
        uint256 timestamp
    );
    event EthStEthPoolChanged(address ethStEthPoolAddr);

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    // setters
    error AnchorEngine__BorrowApyExceedsLimit();
    error AnchorEngine__SafeCollateralRatioTooLow();
    error AnchorEngine__MaxKeeperRateExceeded();
    error AnchorEngine__MaxRedemptionFeeExceeded();

    error AnchorEngine__IndexOutOfBoundError();

    error AnchorEngine__AddressCannotBeZero();
    error AnchorEngine__AmountCannotBeZero();

    error AnchorEngine__ProviderInsufficientDebt();

    error AnchorEngine__DepositBelowInitialMinDeposit();
    error AnchorEngine__InsufficientBalance();

    error AnchorEngine__NotRedemptionProvider();

    error AnchorEngine__AmountExceedsOffer();
    error AnchorEngine__ProviderCollateralRatioTooLow();

    // Custom error for when repayment would reduce debt below redemption commitment
    error AnchorEngine__RepaymentExceedsRedemptionCommitment();

    error AnchorEngine__LiquidationCollateralRateTooHigh();
    error AnchorEngine__LiquidationAmountTooHigh();
    error AnchorEngine__ProviderNotAuthorized();
    error AnchorEngine__SuperLiquidationOverallCollateralRatioTooHigh();
    error AnchorEngine__SuperLiquidationBorrowerCollateralRatioTooHigh();
    error AnchorEngine__SuperLiquidationAmountTooHigh();
    error AnchorEngine__RedemptionProviderNotAuthorized();
    error AnchorEngine__ProviderDebtTooLow();
    error AnchorEngine__ExcessIncomeTooHigh();
    error AnchorEngine__TransferFailed();
    error AnchorEngine__NoRedemptionProviders();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier nonZeroAddress(address account) {
        if (account == address(0)) {
            revert AnchorEngine__AddressCannotBeZero();
        }
        _;
    }

    modifier nonZeroAmount(uint256 amount) {
        if (amount == 0) {
            revert AnchorEngine__AmountCannotBeZero();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _stETHAddress,
        address _priceFeedAddress,
        address _anchorUSDAddress
    ) {
        governance = msg.sender;
        stETH = IStETH(_stETHAddress);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        anchorUSD = IAnchorUSD(_anchorUSDAddress);
    }

    function setBorrowApy(uint256 newApy) external onlyGovernance {
        if (newApy > MAX_MINT_FEE_APY) {
            revert AnchorEngine__BorrowApyExceedsLimit();
        }
        _saveReport();
        mintFeeApy = newApy;
        emit BorrowApyChanged(newApy);
    }

    /**
     * @notice  safeCollateralRatio can be decided by DAO,starts at 160%
     */
    function setSafeCollateralRatio(uint256 newRatio) external onlyGovernance {
        if (newRatio < SAFE_COLL_RATIO_FLOOR) {
            revert AnchorEngine__SafeCollateralRatioTooLow();
        }
        safeCollateralRatio = newRatio;
        emit SafeCollateralRatioChanged(newRatio);
    }

    function setEthStEthPool(address ethStEthPoolAddr) external onlyGovernance {
        ethStEthPool = IStableSwapSTETH(ethStEthPoolAddr);
        emit EthStEthPoolChanged(ethStEthPoolAddr);
    }

    /**
     * @notice KeeperRate can be decided by DAO,1 means 1% of revenue
     */
    function setKeeperRate(uint8 newRate) external onlyGovernance {
        if (newRate > MAX_KEEPERS_RATE) {
            revert AnchorEngine__MaxKeeperRateExceeded();
        }
        keeperRate = newRate;
        emit KeeperRateChanged(newRate);
    }

    /**
     * @notice User chooses to become a Redemption Provider
     */
    function becomeRedemptionProvider(
        uint256 _feeRate,
        uint256 _amount
    ) external nonZeroAmount(_amount) {
        if (_feeRate > MAX_REDEMPTION_FEE_RATE) {
            revert AnchorEngine__MaxRedemptionFeeExceeded();
        }
        if (userPositions[msg.sender].debt < _amount) {
            revert AnchorEngine__ProviderInsufficientDebt();
        }
        redemptionProviders.add(msg.sender);
        redemptionOffers[msg.sender] = RedemptionOffer({
            feeRate: _feeRate,
            amount: _amount
        });
        emit RedemptionProviderRegistered(msg.sender);
    }

    /**
     * @notice User chooses to stop being a Redemption Provider
     */
    function removeRedemptionProvider() external {
        _removeRedemptionProvider(msg.sender);
    }

    function _removeRedemptionProvider(address _provider) internal {
        redemptionProviders.remove(_provider);
        delete redemptionOffers[_provider];
        emit RedemptionProviderRemoved(_provider);
    }

    // --- Redemption Provider EnumerableSet getters ---

    // Function to get the number of redemption providers
    function getRedemptionProvidersCount() public view returns (uint256) {
        return redemptionProviders.length();
    }

    // Function to get a redemption provider by index
    function getRedemptionProviderAtIndex(
        uint256 index
    ) public view returns (address) {
        if (index >= redemptionProviders.length()) {
            revert AnchorEngine__IndexOutOfBoundError();
        }
        return redemptionProviders.at(index);
    }

    // Function to get all redemption providers
    function getAllRedemptionProviders()
        public
        view
        returns (address[] memory)
    {
        address[] memory users = new address[](redemptionProviders.length());
        for (uint256 i = 0; i < redemptionProviders.length(); i++) {
            users[i] = redemptionProviders.at(i);
        }
        return users;
    }

    // Function to check if a user is redemption provider
    function isRedemptionProvider(address _user) public view returns (bool) {
        return redemptionProviders.contains(_user);
    }

    // --- Borrowers EnumerableSet getters ---

    // Function to get the number of borrowers
    function getBorrowersCount() public view returns (uint256) {
        return borrowers.length();
    }

    // Function to get a borrower by index
    function getBorrowerAtIndex(uint256 index) public view returns (address) {
        require(index < borrowers.length(), "Index out of bounds");
        return borrowers.at(index);
    }

    // Function to get all borrowers
    function getAllBorrowers() public view returns (address[] memory) {
        address[] memory users = new address[](borrowers.length());
        for (uint256 i = 0; i < borrowers.length(); i++) {
            users[i] = borrowers.at(i);
        }
        return users;
    }

    // Function to check if a user is a borrower
    function isBorrower(address _user) public view returns (bool) {
        return borrowers.contains(_user);
    }

    // --- Operations related to User Position ---

    /**
     * @notice Deposit ETH on behalf of an address, and update deposit record the this address, can mint anchorUSD directly
     *
     * Emits a `DepositEther` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `mintAmount` Send 0 if doesn't mint anchorUSD
     * - msg.value Must be higher than 0.
     *
     * @dev Record the deposited ETH in the ratio of 1:1 and convert it into stETH.
     */
    function depositEtherToMint(
        address onBehalfOf,
        uint256 mintAmount
    ) external payable nonZeroAddress(onBehalfOf) nonZeroAmount(msg.value) {
        if (!isBorrower(onBehalfOf) && msg.value < INITIAL_MIN_DEPOSIT_AMOUNT)
            revert AnchorEngine__DepositBelowInitialMinDeposit();

        // convert to stETH
        uint256 sharesAmount = stETH.submit{value: msg.value}(governance);
        if (sharesAmount == 0) revert AnchorEngine__AmountCannotBeZero();

        totalDepositedEther += msg.value;
        userPositions[onBehalfOf].collateral += msg.value;

        if (mintAmount > 0) _mintAnchorUSD(onBehalfOf, onBehalfOf, mintAmount);

        if (!isBorrower(onBehalfOf)) borrowers.add(onBehalfOf);

        emit DepositEther(msg.sender, onBehalfOf, msg.value, block.timestamp);
    }

    /**
     * @notice Deposit stETH on behalf of an address, update the interest distribution and deposit record the this address, can mint anchorUSD directly
     * Emits a `DepositEther` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `stETHamount` Must be higher than 0.
     * - `mintAmount` Send 0 if doesn't mint anchorUSD
     * @dev Record the deposited stETH in the ratio of 1:1.
     */
    function depositStETHToMint(
        address onBehalfOf,
        uint256 stETHamount,
        uint256 mintAmount
    ) external nonZeroAddress(onBehalfOf) nonZeroAmount(stETHamount) {
        if (!isBorrower(onBehalfOf) && stETHamount < INITIAL_MIN_DEPOSIT_AMOUNT)
            revert AnchorEngine__DepositBelowInitialMinDeposit();
        stETH.transferFrom(msg.sender, address(this), stETHamount);

        totalDepositedEther += stETHamount;
        userPositions[onBehalfOf].collateral += stETHamount;

        if (mintAmount > 0) _mintAnchorUSD(onBehalfOf, onBehalfOf, mintAmount);

        if (!isBorrower(onBehalfOf)) borrowers.add(onBehalfOf);

        emit DepositEther(msg.sender, onBehalfOf, stETHamount, block.timestamp);
    }

    /**
     * @notice Withdraw collateral assets to an address
     * Emits a `WithdrawEther` event.
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     *
     * @dev Withdraw stETH. Check user’s collateral rate after withdrawal, should be higher than `safeCollateralRatio`
     */
    function withdraw(
        address onBehalfOf,
        uint256 amount
    ) external nonZeroAddress(onBehalfOf) nonZeroAmount(amount) {
        if (userPositions[msg.sender].collateral < amount)
            revert AnchorEngine__InsufficientBalance();

        totalDepositedEther -= amount;
        userPositions[msg.sender].collateral -= amount;

        stETH.transfer(onBehalfOf, amount);

        if (userPositions[msg.sender].debt > 0) _checkHealth(msg.sender);

        if (userPositions[msg.sender].collateral == 0)
            borrowers.remove(msg.sender);

        emit WithdrawEther(msg.sender, onBehalfOf, amount, block.timestamp);
    }

    enum WithdrawalMethod {
        STETH, // Withdraw in stETH
        ETH_CURVE, // Withdraw in ETH via Curve with fee
        ETH_LIDO // Withdraw in ETH via Lido queue without fee
    }

    function withdraw(
        address recipient,
        uint256 amount,
        WithdrawalMethod method,
        uint256 minEthAmountOutForSwap
    ) external nonZeroAddress(recipient) nonZeroAmount(amount) {
        if (userPositions[msg.sender].collateral < amount)
            revert AnchorEngine__InsufficientBalance();

        totalDepositedEther -= amount;
        userPositions[msg.sender].collateral -= amount;

        // Handle based on withdrawal method
        if (method == WithdrawalMethod.STETH) {
            // Withdraw stETH directly
            stETH.transfer(recipient, amount);
        } else if (method == WithdrawalMethod.ETH_CURVE) {
            // Withdraw ETH via Curve StableSwap
            _swapStETHForETH(recipient, amount, minEthAmountOutForSwap);
        } else if (method == WithdrawalMethod.ETH_LIDO) {
            // Withdraw ETH via Lido's queue system (no fee, but time delay)
            _requestLidoWithdrawal(recipient, amount);
        }

        // Check health ratio if user has debt
        if (userPositions[msg.sender].debt > 0) _checkHealth(msg.sender);

        // Remove borrower if collateral is fully withdrawn
        if (userPositions[msg.sender].collateral == 0)
            borrowers.remove(msg.sender);

        emit WithdrawEther(msg.sender, recipient, amount, block.timestamp);
    }

    error AnchorEngine__ETHTransferFailed(address recipient, uint256 amount);

    function _swapStETHForETH(
        address recipient,
        uint256 amount,
        uint256 minEthAmountOut
    ) internal {
        stETH.approve(address(ethStEthPool), amount);

        // Perform the exchange from stETH to ETH
        uint256 ethReceived = ethStEthPool.exchange(
            STETH_IDX_IN_POOL,
            ETH_IDX_IN_POOL,
            amount,
            minEthAmountOut
        );

        // Attempt to send ETH to the recipient
        (bool success, ) = payable(recipient).call{value: ethReceived}("");

        // Revert if the ETH transfer fails
        if (!success) {
            revert AnchorEngine__ETHTransferFailed(recipient, ethReceived);
        }
    }

    function _requestLidoWithdrawal(
        address recipient,
        uint256 amount
    ) internal {
        // Calculate how many requests are needed using ceiling division
        uint256 numberOfRequests = (amount + MAX_STETH_WITHDRAWAL_AMOUNT - 1) /
            MAX_STETH_WITHDRAWAL_AMOUNT;

        uint256[] memory amounts = new uint256[](numberOfRequests);

        // Approve the stETH transfer to the withdrawal queue for the total amount
        stETH.approve(address(stETHWithdrawalQueue), amount);

        // Split the total amount into chunks of MAX_STETH_WITHDRAWAL_AMOUNT
        for (uint256 i = 0; i < numberOfRequests; i++) {
            uint256 requestAmount = amount > MAX_STETH_WITHDRAWAL_AMOUNT
                ? MAX_STETH_WITHDRAWAL_AMOUNT
                : amount;

            amounts[i] = requestAmount;
            amount -= requestAmount;
        }

        // Request the withdrawals
        stETHWithdrawalQueue.requestWithdrawals(amounts, recipient);
    }

    /**
     * @notice The mint amount number of anchorUSD is minted to the address
     * Emits a `Mint` event.
     *
     *
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     */
    function mint(
        address onBehalfOf,
        uint256 amount
    ) external nonZeroAddress(onBehalfOf) nonZeroAmount(amount) {
        _mintAnchorUSD(msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice Burn the amount of anchorUSD and payback the amount of minted anchorUSD
     * Emits a `Burn` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * @dev Calling the internal`_repay`function.
     */
    function burn(
        address onBehalfOf,
        uint256 amount
    ) external nonZeroAddress(onBehalfOf) nonZeroAmount(amount) {
        _repay(msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice When overallCollateralRatio is above 150%, Keeper liquidates borrowers whose collateral rate is below badCollateralRatio, using anchorUSD provided by Liquidation Provider.
     *
     * Requirements:
     * - onBehalfOf Collateral Rate should be below badCollateralRatio
     * - etherAmount should be less than 50% of collateral
     * - provider should authorize Anchor to utilize anchorUSD
     * @dev After liquidation, borrower's debt is reduced by etherAmount * etherPrice, collateral is reduced by the etherAmount corresponding to 110% of the value. Keeper gets keeperRate / 110 of Liquidation Reward and Liquidator gets the remaining stETH.
     */
    function liquidate(
        address provider,
        address onBehalfOf,
        uint256 etherAmount
    ) external {
        uint256 etherPrice = fetchEthPriceInUsd();
        uint256 onBehalfOfCollateralRatio = (userPositions[onBehalfOf]
            .collateral *
            etherPrice *
            100) / userPositions[onBehalfOf].debt;
        require(
            onBehalfOfCollateralRatio < badCollateralRatio,
            "Borrowers collateral rate should below badCollateralRatio"
        );

        require(
            etherAmount * 2 <= userPositions[onBehalfOf].collateral,
            "a max of 50% collateral can be liquidated"
        );
        uint256 anchorUSDAmount = (etherAmount * etherPrice) / 1e18;
        require(
            anchorUSD.allowance(provider, address(this)) >= anchorUSDAmount,
            "provider should authorize to provide liquidation anchorUSD"
        );

        _repay(provider, onBehalfOf, anchorUSDAmount);

        uint256 reducedEther = (etherAmount * 11) / 10;
        totalDepositedEther -= reducedEther;
        userPositions[onBehalfOf].collateral -= reducedEther;
        uint256 reward2keeper;
        if (provider == msg.sender) {
            stETH.transfer(msg.sender, reducedEther);
        } else {
            reward2keeper = (reducedEther * keeperRate) / 110;
            stETH.transfer(provider, reducedEther - reward2keeper);
            stETH.transfer(msg.sender, reward2keeper);
        }
        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            anchorUSDAmount,
            reducedEther,
            reward2keeper,
            false,
            block.timestamp
        );
    }

    /**
     * @notice When overallCollateralRatio is below badCollateralRatio, borrowers with collateralRatio below 125% could be fully liquidated.
     * Emits a `LiquidationRecord` event.
     *
     * Requirements:
     * - Current overallCollateralRatio should be below badCollateralRatio
     * - `onBehalfOf`collateralRatio should be below 125%
     * @dev After Liquidation, borrower's debt is reduced by etherAmount * etherPrice, deposit is reduced by etherAmount * borrower's collateralRatio. Keeper gets a liquidation reward of `keeperRate / borrower's collateralRatio
     */
    function superLiquidation(
        address provider,
        address onBehalfOf,
        uint256 etherAmount
    ) external {
        uint256 etherPrice = fetchEthPriceInUsd();
        require(
            (totalDepositedEther * etherPrice * 100) /
                totalAnchorUSDCirculation <
                badCollateralRatio,
            "overallCollateralRatio should below 150%"
        );
        uint256 onBehalfOfCollateralRatio = (userPositions[onBehalfOf]
            .collateral *
            etherPrice *
            100) / userPositions[onBehalfOf].debt;
        require(
            onBehalfOfCollateralRatio < 125 * 1e18,
            "borrowers collateralRatio should below 125%"
        );
        require(
            etherAmount <= userPositions[onBehalfOf].collateral,
            "total of collateral can be liquidated at most"
        );
        uint256 anchorUSDAmount = (etherAmount * etherPrice) / 1e18;
        if (onBehalfOfCollateralRatio >= 1e20) {
            anchorUSDAmount =
                (anchorUSDAmount * 1e20) /
                onBehalfOfCollateralRatio;
        }
        require(
            anchorUSD.allowance(provider, address(this)) >= anchorUSDAmount,
            "provider should authorize to provide liquidation anchorUSD"
        );

        _repay(provider, onBehalfOf, anchorUSDAmount);

        totalDepositedEther -= etherAmount;
        userPositions[onBehalfOf].collateral -= etherAmount;
        uint256 reward2keeper;
        if (
            msg.sender != provider &&
            onBehalfOfCollateralRatio >= 1e20 + keeperRate * 1e18
        ) {
            reward2keeper =
                ((etherAmount * keeperRate) * 1e18) /
                onBehalfOfCollateralRatio;
            stETH.transfer(msg.sender, reward2keeper);
        }
        stETH.transfer(provider, etherAmount - reward2keeper);

        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            anchorUSDAmount,
            etherAmount,
            reward2keeper,
            true,
            block.timestamp
        );
    }

    /**
     * @notice When stETH balance increases through LSD or other reasons, the excess income is sold for anchorUSD, allocated to anchorUSD holders through rebase mechanism.
     * Emits a `LSDistribution` event.
     *
     * *Requirements:
     * - stETH balance in the contract cannot be less than totalDepositedEther after exchange.
     * @dev Income is used to cover accumulated Service Fee first.
     */
    function excessIncomeDistribution(uint256 payAmountInAnchorUSD) external {
        uint256 payoutEther = (payAmountInAnchorUSD * 1e18) /
            fetchEthPriceInUsd();
        require(
            payoutEther <=
                stETH.balanceOf(address(this)) - totalDepositedEther &&
                payoutEther > 0,
            "Only LSD excess income can be exchanged"
        );

        uint256 income = feeStored + _newFee();

        if (payAmountInAnchorUSD > income) {
            bool success = anchorUSD.transferFrom(
                msg.sender,
                governance,
                income
            );
            require(success, "TF");

            uint256 sharesAmount = anchorUSD.getSharesByMintedAnchorUSD(
                payAmountInAnchorUSD - income
            );

            anchorUSD.burnShares(msg.sender, sharesAmount);
            feeStored = 0;
        } else {
            bool success = anchorUSD.transferFrom(
                msg.sender,
                governance,
                payAmountInAnchorUSD
            );
            require(success, "TF");

            feeStored = income - payAmountInAnchorUSD;
        }

        lastReportTime = block.timestamp;
        stETH.transfer(msg.sender, payoutEther);

        emit LSDistribution(payoutEther, payAmountInAnchorUSD, block.timestamp);
    }

    /**
     * @notice Choose a Redemption Provider, Rigid Redeem `anchorUSDAmount` of anchorUSD and get 1:1 value of stETH
     * Emits a `RedeemedCollateral` event.
     *
     * *Requirements:
     * - `provider` must be a Redemption Provider
     * - `provider`debt must equal to or above`anchorUSDAmount`
     * @dev Service Fee for redemption `redemptionFee` is set to 0.5% by default, can be revised by DAO.
     */

    function redeemCollateral(
        address provider,
        uint256 anchorUSDAmount
    ) public {
        if (!isRedemptionProvider(provider))
            revert AnchorEngine__NotRedemptionProvider();

        if (redemptionOffers[provider].amount < anchorUSDAmount)
            revert AnchorEngine__AmountExceedsOffer();
        uint256 etherPrice = fetchEthPriceInUsd();
        uint256 providerCollateralRatio = _calculateCollateralRatio(
            userPositions[provider].collateral,
            etherPrice,
            userPositions[provider].debt
        );

        if (providerCollateralRatio <= 100 * 1e18)
            revert AnchorEngine__ProviderCollateralRatioTooLow();

        redemptionOffers[provider].amount -= anchorUSDAmount;

        _repay(msg.sender, provider, anchorUSDAmount);

        uint256 etherAmount = (anchorUSDAmount *
            (100_00 - redemptionOffers[provider].feeRate) *
            1e18) / (etherPrice * 100_00);

        if (redemptionOffers[provider].amount == 0)
            _removeRedemptionProvider(provider);

        userPositions[provider].collateral -= etherAmount;
        totalDepositedEther -= etherAmount;

        stETH.transfer(msg.sender, etherAmount);

        emit RedeemedCollateral(
            msg.sender,
            provider,
            anchorUSDAmount,
            etherAmount,
            block.timestamp
        );
    }

    /**
     * @notice Redeems a specified amount of AnchorUSD from multiple redemption providers.
     * @dev Iterates through the list of providers and redeems the specified amount of AnchorUSD.
     *      Only eligible providers (those registered and with a healthy collateral ratio) are considered.
     *      The function does not revert if the full amount cannot be redeemed; it processes as much as possible.
     * @param providers An array of addresses of redemption providers to redeem from, sorted by lowest fee first.
     * @param amount The total amount of AnchorUSD to be redeemed.
     */
    function batchRedeemCollateral(
        address[] calldata providers,
        uint256 amount
    ) external {
        uint256 remainingAmount = amount;
        for (
            uint256 providerIdx = 0;
            providerIdx < providers.length && remainingAmount > 0;
            providerIdx++
        ) {
            uint256 providerCollRatio = _calculateCollateralRatio(
                userPositions[providers[providerIdx]].collateral,
                fetchEthPriceInUsd(),
                userPositions[providers[providerIdx]].debt
            );
            if (
                !isRedemptionProvider(providers[providerIdx]) ||
                providerCollRatio <= (100 * 1e18)
            ) continue;

            uint256 providerAmount = redemptionOffers[providers[providerIdx]]
                .amount;
            uint256 redeemableAmount = remainingAmount < providerAmount
                ? remainingAmount
                : providerAmount;
            redeemCollateral(providers[providerIdx], redeemableAmount);
            remainingAmount -= redeemableAmount;
        }
    }

    /**
     * @dev  Refresh Anchor generated service fee before adding totalAnchorUSDCirculation. Check providers collateralRatio cannot below `safeCollateralRatio`after minting.
     */
    function _mintAnchorUSD(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal {
        userPositions[_provider].debt += _amount;

        anchorUSD.mint(_onBehalfOf, _amount);

        _saveReport();
        totalAnchorUSDCirculation += _amount;
        _checkHealth(_provider);

        emit Mint(msg.sender, _onBehalfOf, _amount, block.timestamp);
    }

    /**
     * @notice Burn _provideramount anchorUSD to payback minted anchorUSD for _onBehalfOf.
     *
     * @dev  Refresh Anchor generated service fee before reducing totalAnchorUSDCirculation.
     */
    function _repay(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal {
        uint256 amount = userPositions[_onBehalfOf].debt >= _amount
            ? _amount
            : userPositions[_onBehalfOf].debt;

        anchorUSD.burn(_provider, amount);

        userPositions[_onBehalfOf].debt -= _amount;

        if (
            isRedemptionProvider(_onBehalfOf) &&
            userPositions[_onBehalfOf].debt <
            redemptionOffers[_onBehalfOf].amount
        ) revert AnchorEngine__RepaymentExceedsRedemptionCommitment();

        _saveReport();
        totalAnchorUSDCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
    }

    function _saveReport() internal {
        feeStored += _newFee();
        lastReportTime = block.timestamp;
    }

    function _calculateCollateralRatio(
        uint256 collateral,
        uint256 price,
        uint256 debt
    ) internal pure returns (uint256) {
        return (collateral * price * 100) / debt;
    }

    /**
     * @dev Get USD value of current collateral asset and minted anchorUSD through price oracle / Collateral asset USD value must higher than safe Collateral Rate.
     */
    function _checkHealth(address user) internal view {
        if (
            _calculateCollateralRatio(
                userPositions[user].collateral,
                fetchEthPriceInUsd(),
                userPositions[user].debt
            ) < safeCollateralRatio
        ) revert("collateralRatio is Below safeCollateralRatio");
    }

    function fetchEthPriceInUsd() public view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint(answer) * 10 ** (18 - priceFeed.decimals());
    }

    function _newFee() internal view returns (uint256) {
        return
            (totalAnchorUSDCirculation *
                mintFeeApy *
                (block.timestamp - lastReportTime)) /
            year /
            10000;
    }
}
