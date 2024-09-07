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
    uint256 public redemptionFee = 50;
    uint8 public keeperRate = 1;

    mapping(address user => UserPosition position) public userPositions;

    uint256 public feeStored;

    IStETH immutable stETH;
    AggregatorV3Interface immutable priceFeed;

    IAnchorUSD public immutable anchorUSD;

    EnumerableSet.AddressSet private redemptionProviders;
    EnumerableSet.AddressSet private borrowers;

    uint256 public constant MAX_MINT_FEE_APY = 150; //1.5%

    uint256 public constant SAFE_COLL_RATIO_FLOOR = 160e18; //160%

    uint256 public constant MAX_KEEPERS_RATE = 5; //5%

    uint256 public constant MAX_REDEMPTION_FEE = 500; //5%

    uint256 public constant INITIAL_MIN_DEPOSIT_AMOUNT = 1 ether;

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
    event RedemptionProvider(address user, bool status);
    event RedeemedCollateral(
        address indexed caller,
        address indexed provider,
        uint256 anchorUSDAmount,
        uint256 etherAmount,
        uint256 timestamp
    );

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

    error AnchorEngine__DepositBelowInitialMinDeposit();
    error AnchorEngine__InsufficientBalance();
    error AnchorEngine__LiquidationCollateralRateTooHigh();
    error AnchorEngine__LiquidationAmountTooHigh();
    error AnchorEngine__ProviderNotAuthorized();
    error AnchorEngine__SuperLiquidationOverallCollateralRatioTooHigh();
    error AnchorEngine__SuperLiquidationBorrowerCollateralRatioTooHigh();
    error AnchorEngine__SuperLiquidationAmountTooHigh();
    error AnchorEngine__RedemptionProviderNotAuthorized();
    error AnchorEngine__ProviderDebtTooLow();
    error AnchorEngine__ProviderCollateralRatioTooLow();
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
     * @notice DAO sets RedemptionFee, 100 means 1%
     */
    function setRedemptionFee(uint8 newFee) external onlyGovernance {
        if (newFee > MAX_REDEMPTION_FEE) {
            revert AnchorEngine__MaxRedemptionFeeExceeded();
        }
        redemptionFee = newFee;
        emit RedemptionFeeChanged(newFee);
    }

    /**
     * @notice User chooses to become a Redemption Provider
     */
    function becomeRedemptionProvider() external {
        redemptionProviders.add(msg.sender);
        emit RedemptionProvider(msg.sender, true);
    }

    /**
     * @notice User chooses to stop being a Redemption Provider
     */
    function removeRedemptionProvider() external {
        redemptionProviders.remove(msg.sender);
        emit RedemptionProvider(msg.sender, false);
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
     * - provider should authorize Lybra to utilize anchorUSD
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
            //Income is distributed to LBR staker.
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
        require(
            isRedemptionProvider(provider),
            "provider is not a RedemptionProvider"
        );
        require(
            userPositions[provider].debt >= anchorUSDAmount,
            "anchorUSDAmount cannot surpass providers debt"
        );
        uint256 etherPrice = fetchEthPriceInUsd();
        uint256 providerCollateralRatio = (userPositions[provider].collateral *
            etherPrice *
            100) / userPositions[provider].debt;
        require(
            providerCollateralRatio >= 100 * 1e18,
            "provider's collateral ratio should more than 100%"
        );
        _repay(msg.sender, provider, anchorUSDAmount);

        if (userPositions[provider].debt == 0)
            redemptionProviders.remove(provider);

        uint256 etherAmount = (((anchorUSDAmount * 1e18) / etherPrice) *
            (100_00 - redemptionFee)) / 100_00;
        userPositions[provider].collateral -= etherAmount;
        totalDepositedEther -= etherAmount;

        if (userPositions[provider].collateral == 0) borrowers.remove(provider);

        stETH.transfer(msg.sender, etherAmount);

        emit RedeemedCollateral(
            msg.sender,
            provider,
            anchorUSDAmount,
            etherAmount,
            block.timestamp
        );
    }

    function redeemFromAllProviders(uint256 anchorUSDAmount) external {
        uint256 providerCount = redemptionProviders.length();
        require(providerCount > 0, "No redemption providers available");

        for (uint256 i = 0; i < providerCount; i++) {
            address provider = redemptionProviders.at(i);
            uint256 providerDebt = userPositions[provider].debt;
            uint256 amountToRedeem = anchorUSDAmount <= providerDebt
                ? anchorUSDAmount
                : providerDebt;
            if (amountToRedeem > 0) {
                redeemCollateral(provider, amountToRedeem);
            }
            anchorUSDAmount -= amountToRedeem;
            if (anchorUSDAmount == 0) {
                break;
            }
        }
    }

    /**
     * @dev Refresh LBR reward before adding providers debt. Refresh Lybra generated service fee before adding totalAnchorUSDCirculation. Check providers collateralRatio cannot below `safeCollateralRatio`after minting.
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
     * @dev Refresh LBR reward before reducing providers debt. Refresh Lybra generated service fee before reducing totalAnchorUSDCirculation.
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

        _saveReport();
        totalAnchorUSDCirculation -= _amount;

        emit Burn(_provider, _onBehalfOf, _amount, block.timestamp);
    }

    function _saveReport() internal {
        feeStored += _newFee();
        lastReportTime = block.timestamp;
    }

    /**
     * @dev Get USD value of current collateral asset and minted anchorUSD through price oracle / Collateral asset USD value must higher than safe Collateral Rate.
     */
    function _checkHealth(address user) internal view {
        if (
            ((userPositions[user].collateral * fetchEthPriceInUsd() * 100) /
                userPositions[user].debt) < safeCollateralRatio
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
