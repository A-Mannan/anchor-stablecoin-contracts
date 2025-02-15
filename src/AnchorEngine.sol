// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IAnchorUSD} from "./interfaces/IAnchorUSD.sol";
import {Governable} from "./dependencies/Governable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IPriceFeed} from "./interfaces/IPriceFeed.sol";

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

contract AnchorEngine is Governable {
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

    // Currently, the official rebase time for Lido is between 12PM UTC.
    uint256 public lidoRebaseTime = 12 hours;

    uint256 public totalDepositedEther;
    uint256 public totalAnchorUSDCirculation;
    // uint256 public lastReportTime;
    uint256 year = 365 days; // secs in a year

    // uint256 public mintFeeApy = 150;
    // uint256 public safeCollateralRatio = 160 * 1e18;
    // uint256 public immutable badCollateralRatio = 150 * 1e18;
    uint256 public minCollateralRatio;

    // uint256 public redemptionFee = 50;
    uint8 public keeperRate = 1;
    // Fee Share percentage in basis points
    uint256 public feeShareBps = 500; // 5%

    mapping(address user => UserPosition position) public userPositions;

    // uint256 public feeStored;

    IStETH immutable stETH;
    AggregatorV3Interface immutable priceFeed;

    IAnchorUSD public immutable anchorUSD;

    mapping(address redemptionProvider => RedemptionOffer)
        public redemptionOffers;

    EnumerableSet.AddressSet private redemptionProviders;
    EnumerableSet.AddressSet private borrowers;

    // uint256 public constant MAX_MINT_FEE_APY = 150; //1.5%
    uint256 public constant MAX_FEE_SHARE_BPS = 3000; //30%

    uint256 public constant MIN_COLL_RATIO_FLOOR = 120e18; //160%

    uint256 public constant MAX_KEEPERS_RATE = 5; //5%

    uint256 public constant MAX_REDEMPTION_FEE_RATE = 500; //5%

    uint256 public constant INITIAL_MIN_DEPOSIT_AMOUNT = 1 ether;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event FeeShareChanged(uint256 newFeeShareBps);
    event MinCollateralRatioChanged(uint256 newRatio);
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
        uint256 timestamp
    );
    event RedemptionProviderRegistered(
        address indexed user,
        uint256 feeRate,
        uint256 amount
    );
    event RedemptionProviderRemoved(address indexed user);
    event RedeemedCollateral(
        address indexed caller,
        address indexed provider,
        uint256 anchorUSDAmount,
        uint256 etherAmount,
        uint256 timestamp
    );
    event LSDValueCaptured(
        uint256 stETHAdded,
        uint256 payoutEUSD,
        uint256 discountRate,
        uint256 timestamp
    );
    event FeeDistribution(
        address indexed feeAddress,
        uint256 feeAmount,
        uint256 timestamp
    );

    event BatchRedeemedCollateral(
        address indexed caller,
        uint256 anchorUSDAmount,
        uint256 etherAmount,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    // setters
    error AnchorEngine__BorrowApyExceedsLimit();
    error AnchorEngine__MinCollateralRatioTooLow();
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

    error AnchorEngine__CollateralRatioAboveMinCollateralRatio();
    error AnchorEngine__ExceedsCollateralLimit();
    error AnchorEngine__InsufficientAllowance();
    error AnchorEngine__NoExcessIncome();

    error AnchorEngine__SlippageExceeded();

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
        address _anchorUSDAddress,
        uint256 _minCollateralRatio
    ) {
        governance = msg.sender;
        stETH = IStETH(_stETHAddress);
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        anchorUSD = IAnchorUSD(_anchorUSDAddress);
        minCollateralRatio = _minCollateralRatio;
    }

    // Governance Ops

    function setFeeShare(uint256 newFeeShareBps) external onlyGovernance {
        if (newFeeShareBps > MAX_FEE_SHARE_BPS) {
            revert AnchorEngine__BorrowApyExceedsLimit();
        }
        // _saveReport();
        feeShareBps = newFeeShareBps;
        emit FeeShareChanged(newFeeShareBps);
    }

    /**
     * @notice  minCollateralRatio can be decided by DAO,starts at 160%
     */
    function setMinCollateralRatio(uint256 newRatio) external onlyGovernance {
        if (newRatio < MIN_COLL_RATIO_FLOOR) {
            revert AnchorEngine__MinCollateralRatioTooLow();
        }
        minCollateralRatio = newRatio;
        emit MinCollateralRatioChanged(newRatio);
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
     * @notice Sets the rebase time for Lido based on the actual situation.
     * This function can only be called by an address with the ADMIN role.
     */
    function setLidoRebaseTime(uint256 _time) external onlyGovernance {
        lidoRebaseTime = _time;
    }

    // User Ops

    /**
     * @notice User chooses to become a Redemption Provider
     */
    function becomeRedemptionProvider(
        uint256 _feeRate,
        uint256 _amount
    ) external nonZeroAmount(_amount) nonZeroAmount(_feeRate) {
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
        emit RedemptionProviderRegistered(msg.sender, _feeRate, _amount);
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
     * @notice Repay the amount of anchorUSD and payback the amount of minted anchorUSD
     * Emits a `Repay` event.
     * Requirements:
     * - `onBehalfOf` cannot be the zero address.
     * - `amount` Must be higher than 0.
     * @dev Calling the internal`_repay`function.
     */
    function repay(
        address onBehalfOf,
        uint256 amount
    ) external nonZeroAddress(onBehalfOf) nonZeroAmount(amount) {
        _repay(msg.sender, onBehalfOf, amount);
    }

    function liquidatePosition(
        address provider,
        address onBehalfOf,
        uint256 debtToOffset,
        uint256 minEthOut
    ) external {
        uint256 etherPrice = fetchEthPriceInUsd();

        uint256 onBehalfOfCollateralRatio = _calculateCollateralRatio(
            userPositions[onBehalfOf].collateral,
            etherPrice,
            userPositions[onBehalfOf].debt
        );

        if (onBehalfOfCollateralRatio >= minCollateralRatio) {
            revert AnchorEngine__CollateralRatioAboveMinCollateralRatio();
        }

        uint256 anchorUSDAmount = userPositions[onBehalfOf].debt < debtToOffset
            ? userPositions[onBehalfOf].debt
            : debtToOffset;

        // Calculate required collateral (etherAmount) to offset the given debt amount
        uint256 etherAmount = (anchorUSDAmount * 1e18) / etherPrice;

        // Apply discount if the borrower's collateral ratio is >= 100%
        if (onBehalfOfCollateralRatio >= 1e20) {
            etherAmount = (etherAmount * onBehalfOfCollateralRatio) / 1e20;
        }

        if (etherAmount > userPositions[onBehalfOf].collateral) {
            revert AnchorEngine__ExceedsCollateralLimit();
        }

        if (anchorUSD.allowance(provider, address(this)) < anchorUSDAmount) {
            revert AnchorEngine__InsufficientAllowance();
        }

        if (etherAmount < minEthOut) {
            revert AnchorEngine__SlippageExceeded();
        }

        // Repay the specified debt amount using AnchorUSD
        _repay(provider, onBehalfOf, anchorUSDAmount);

        // Update the borrower's collateral and total deposited ether
        totalDepositedEther -= etherAmount;
        userPositions[onBehalfOf].collateral -= etherAmount;

        uint256 reward2keeper;

        // Calculate keeper reward (if applicable)
        if (
            msg.sender != provider &&
            onBehalfOfCollateralRatio >= 1e20 + keeperRate * 1e18
        ) {
            reward2keeper =
                ((etherAmount * keeperRate) * 1e18) /
                onBehalfOfCollateralRatio;
            stETH.transfer(msg.sender, reward2keeper);
        }

        // Transfer the remaining collateral to the provider
        stETH.transfer(provider, etherAmount - reward2keeper);

        // Emit the liquidation event
        emit LiquidationRecord(
            provider,
            msg.sender,
            onBehalfOf,
            anchorUSDAmount,
            etherAmount,
            reward2keeper,
            block.timestamp
        );
    }

    function getHarvestableYield() public view returns (uint256) {
        return stETH.balanceOf(address(this)) - totalDepositedEther;
    }

    // Function for auctioning excess yield with fee deduction
    function harvestYieldAndAuction(uint256 stETHAmount) external {
        // Calculate the excess stETH in the contract
        uint256 excessStETH = getHarvestableYield();

        // Validate input and state
        if (excessStETH == 0 || stETHAmount == 0) {
            revert AnchorEngine__NoExcessIncome();
        }

        // Determine the actual amount of stETH to process
        uint256 yieldToAuction = stETHAmount > excessStETH
            ? excessStETH
            : stETHAmount;

        // Calculate the payment in anchorUSD using Dutch Auction discount
        uint256 dutchAuctionDiscountPrice = getDutchAuctionDiscountPrice();
        uint256 auctionPaymentAmount = (yieldToAuction *
            fetchEthPriceInUsd() *
            dutchAuctionDiscountPrice) /
            10_000 /
            1e18;

        // Calculate the fee to be deducted based on the fee percentage
        uint256 feeAmount = (auctionPaymentAmount * feeShareBps) / 10_000;

        // The amount to be distributed (after deducting fee)
        uint256 redistributionAmount = auctionPaymentAmount - feeAmount;

        // Handle the fee transfer
        bool success = anchorUSD.transferFrom(
            msg.sender,
            governance,
            feeAmount
        );
        if (!success) revert AnchorEngine__TransferFailed();

        // Handle the redistribution of the remaining amount (after fee deduction)
        uint256 sharesAmount = anchorUSD.getSharesByMintedAnchorUSD(
            redistributionAmount
        );
        anchorUSD.burnShares(msg.sender, sharesAmount);

        // Update state and transfer stETH to the user
        // lastReportTime = block.timestamp;
        stETH.transfer(msg.sender, yieldToAuction);

        emit FeeDistribution(governance, feeAmount, block.timestamp);

        // Emit event for yield distribution
        emit LSDValueCaptured(
            yieldToAuction,
            auctionPaymentAmount,
            dutchAuctionDiscountPrice,
            block.timestamp
        );
    }

    /**
     * @notice Reduces the discount for the issuance of additional tokens based on the rebase time using the Dutch auction method.
     * The specific rule is that the discount rate increases by 1% every 30 minutes after the rebase occurs.
     */
    function getDutchAuctionDiscountPrice() public view returns (uint256) {
        uint256 time = getTimePassedSinceRebase();
        // if (time < 30 minutes) return 10_000;
        return 10_000 - (time / 30 minutes) * 100;
    }

    function getTimePassedSinceRebase() public view returns (uint256) {
        return (block.timestamp - lidoRebaseTime) % 1 days;
    }

    /**
     * @notice Internal function to handle the redemption logic.
     * @dev Centralizes the redemption process for single and batch operations.
     * @param provider The address of the redemption provider.
     * @param anchorUSDAmount The amount of AnchorUSD to redeem.
     * @param etherPrice The current ETH price in USD (pre-fetched for efficiency in batch operations).
     * @param minEtherAmount The minimum acceptable amount of stETH to redeem (slippage protection).
     * @return etherAmount The amount of stETH transferred to the redeemer.
     */
    function _processRedemption(
        address provider,
        uint256 anchorUSDAmount,
        uint256 etherPrice,
        uint256 minEtherAmount
    ) internal returns (uint256 etherAmount) {
        if (!isRedemptionProvider(provider))
            revert AnchorEngine__NotRedemptionProvider();

        uint256 providerOfferAmount = redemptionOffers[provider].amount;
        if (providerOfferAmount < anchorUSDAmount)
            revert AnchorEngine__AmountExceedsOffer();

        uint256 providerCollateralRatio = _calculateCollateralRatio(
            userPositions[provider].collateral,
            etherPrice,
            userPositions[provider].debt
        );

        if (providerCollateralRatio <= 100 * 1e18)
            revert AnchorEngine__ProviderCollateralRatioTooLow();

        // Update provider offer amount and user positions in memory first
        redemptionOffers[provider].amount =
            providerOfferAmount -
            anchorUSDAmount;

        uint256 feeRate = redemptionOffers[provider].feeRate;
        etherAmount =
            (anchorUSDAmount * (100_00 - feeRate) * 1e18) /
            (etherPrice * 100_00);

        // Slippage check
        if (etherAmount < minEtherAmount)
            revert AnchorEngine__SlippageExceeded();

        uint256 newCollateral = userPositions[provider].collateral -
            etherAmount;
        userPositions[provider].collateral = newCollateral;

        if (redemptionOffers[provider].amount == 0) {
            _removeRedemptionProvider(provider);
        }

        totalDepositedEther -= etherAmount;

        // Perform repayment
        _repay(msg.sender, provider, anchorUSDAmount);

        emit RedeemedCollateral(
            msg.sender,
            provider,
            anchorUSDAmount,
            etherAmount,
            block.timestamp
        );

        return etherAmount;
    }

    /**
     * @notice Redeems a specified amount of AnchorUSD from a single redemption provider.
     * Emits a `RedeemedCollateral` event.
     * @param provider The address of the redemption provider.
     * @param anchorUSDAmount The amount of AnchorUSD to redeem.
     * @param minEtherAmount The minimum acceptable amount of stETH to redeem (slippage protection).
     */
    function redeemCollateral(
        address provider,
        uint256 anchorUSDAmount,
        uint256 minEtherAmount
    ) public {
        uint256 etherPrice = fetchEthPriceInUsd();
        uint256 etherAmount = _processRedemption(
            provider,
            anchorUSDAmount,
            etherPrice,
            minEtherAmount
        );

        stETH.transfer(msg.sender, etherAmount);
    }

    /**
     * @notice Redeems a specified amount of AnchorUSD from multiple redemption providers.
     * Emits a `BatchRedeemedCollateral` event.
     * @param providers An array of redemption providers.
     * @param amount The total amount of AnchorUSD to redeem.
     * @param minEtherAmount The minimum acceptable total amount of stETH to redeem (slippage protection).
     */
    function batchRedeemCollateral(
        address[] calldata providers,
        uint256 amount,
        uint256 minEtherAmount
    ) external {
        uint256 remainingAmount = amount;
        uint256 totalEtherRedeemed = 0;
        uint256 etherPrice = fetchEthPriceInUsd();

        for (uint256 i = 0; i < providers.length && remainingAmount > 0; i++) {
            address provider = providers[i];

            // Fetch provider offer and calculate redeemable amount
            uint256 providerOfferAmount = redemptionOffers[provider].amount;
            uint256 redeemableAmount = remainingAmount < providerOfferAmount
                ? remainingAmount
                : providerOfferAmount;

            if (
                isRedemptionProvider(provider) &&
                _calculateCollateralRatio(
                    userPositions[provider].collateral,
                    etherPrice,
                    userPositions[provider].debt
                ) >
                (100 * 1e18)
            ) {
                uint256 etherRedeemed = _processRedemption(
                    provider,
                    redeemableAmount,
                    etherPrice,
                    0 // No per-provider slippage check in batch mode
                );

                remainingAmount -= redeemableAmount;
                totalEtherRedeemed += etherRedeemed;
            }
        }

        // Batch slippage check
        if (totalEtherRedeemed < minEtherAmount)
            revert AnchorEngine__SlippageExceeded();

        if (totalEtherRedeemed > 0) {
            stETH.transfer(msg.sender, totalEtherRedeemed);
        }

        emit BatchRedeemedCollateral(
            msg.sender,
            amount - remainingAmount,
            totalEtherRedeemed,
            block.timestamp
        );
    }

    function _mintAnchorUSD(
        address _provider,
        address _onBehalfOf,
        uint256 _amount
    ) internal {
        userPositions[_provider].debt += _amount;

        anchorUSD.mint(_onBehalfOf, _amount);

        totalAnchorUSDCirculation += _amount;
        _checkHealth(_provider);

        emit Mint(msg.sender, _onBehalfOf, _amount, block.timestamp);
    }

    /**
     * @notice Burn _provideramount anchorUSD to payback minted anchorUSD for _onBehalfOf.
     *
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

        totalAnchorUSDCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
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
            ) < minCollateralRatio
        ) revert("collateralRatio is Below minCollateralRatio");
    }

    function fetchEthPriceInUsd() public view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint(answer) * 10 ** (18 - priceFeed.decimals());
    }
}
