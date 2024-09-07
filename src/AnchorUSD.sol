// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20FlashMint} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 ______                  __                     __  __  ____    ____      
/\  _  \                /\ \                   /\ \/\ \/\  _`\ /\  _`\    
\ \ \L\ \    ___     ___\ \ \___     ___   _ __\ \ \ \ \ \,\L\_\ \ \/\ \  
 \ \  __ \ /' _ `\  /'___\ \  _ `\  / __`\/\`'__\ \ \ \ \/_\__ \\ \ \ \ \ 
  \ \ \/\ \/\ \/\ \/\ \__/\ \ \ \ \/\ \L\ \ \ \/ \ \ \_\ \/\ \L\ \ \ \_\ \
   \ \_\ \_\ \_\ \_\ \____\\ \_\ \_\ \____/\ \_\  \ \_____\ `\____\ \____/
    \/_/\/_/\/_/\/_/\/____/ \/_/\/_/\/___/  \/_/   \/_____/\/_____/\/___/ 

 * @title Interest-bearing ERC20-like token for Anchor protocol.
 *
 * AnchorUSD balances are dynamic and represent the holder's share in the total amount
 * of Ether controlled by the protocol. Account shares aren't normalized, so the
 * contract also stores the sum of all shares to calculate each account's token balance
 * which equals to:
 *
 *   shares[account] * totalSupply / _totalShares
 *
 * For example, assume that we have:
 *
 *   _getTotalMintedAnchorUSD() -> 1000 AnchorUSD
 *   sharesOf(user1) -> 100
 *   sharesOf(user2) -> 400
 *
 * Therefore:
 *
 *   balanceOf(user1) -> 200 tokens which corresponds 200 AnchorUSD
 *   balanceOf(user2) -> 800 tokens which corresponds 800 AnchorUSD
 *
 * Since balances of all token holders change when the amount of total shares
 * changes, this token cannot fully implement ERC20 standard: it only emits `Transfer`
 * events upon explicit transfer between holders. In contrast, when total amount of
 * pooled Ether increases, no `Transfer` events are generated: doing so would require
 * emitting an event for each token holder and thus running an unbounded loop.
 */

contract AnchorUSD is ERC20, ERC20Permit, ERC20FlashMint {
    uint256 private _totalShares;
    uint256 private _totalSupply;

    /**
     * @dev AnchorUSD balances are dynamic and are calculated based on the accounts' shares
     * and the total supply by the protocol. Account shares aren't
     * normalized, so the contract also stores the sum of all shares to calculate
     * each account's token balance which equals to:
     *
     *   shares[account] * _getTotalMintedAnchorUSD() / _getTotalShares()
     */
    mapping(address => uint256) private shares;

    /**
     * @dev Allowances are nominated in tokens, not token shares.
     */
    mapping(address => mapping(address => uint256)) private allowances;

    address public immutable anchorEngine;

    address public immutable feeReceiver;

    // --- ERC 3156 Data ---
    uint256 public constant FLASH_LOAN_FEE = 9; // 1 = 0.0001%

    /**
     * @notice An executed shares transfer from `sender` to `recipient`.
     *
     * @dev emitted in pair with an ERC20-defined `Transfer` event.
     */
    event TransferShares(
        address indexed from,
        address indexed to,
        uint256 sharesValue
    );

    /**
     * @notice An executed `burnShares` request
     *
     * @dev Reports simultaneously burnt shares amount
     * and corresponding AnchorUSD amount.
     * The AnchorUSD amount is calculated twice: before and after the burning incurred rebase.
     *
     * @param account holder of the burnt shares
     * @param preRebaseTokenAmount amount of AnchorUSD the burnt shares corresponded to before the burn
     * @param postRebaseTokenAmount amount of AnchorUSD the burnt shares corresponded to after the burn
     * @param sharesAmount amount of burnt shares
     */
    event SharesBurnt(
        address indexed account,
        uint256 preRebaseTokenAmount,
        uint256 postRebaseTokenAmount,
        uint256 sharesAmount
    );

    modifier onlyAnchorEngine() {
        require(msg.sender == anchorEngine, "Not Anchor Engine");
        _;
    }

    constructor(
        address _anchorEngine,
        address _feeReceiver
    ) ERC20("AnchorUSD", "AnchorUSD") ERC20Permit("AnchorUSD") {
        anchorEngine = _anchorEngine;
        feeReceiver = _feeReceiver;
    }

    /**s
     * @return the amount of AnchorUSD in existence.
     *
     * @dev Always equals to `_getTotalMintedAnchorUSD()` since token amount
     * is pegged to the total amount of AnchorUSD controlled by the protocol.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @return the amount of tokens owned by the `_account`.
     *
     * @dev Balances are dynamic and equal the `_account`'s share in the amount of the
     * total Ether controlled by the protocol. See `sharesOf`.
     */
    function balanceOf(
        address _account
    ) public view override returns (uint256) {
        return getMintedAnchorUSDByShares(_sharesOf(_account));
    }

    /**
     * @return the remaining number of tokens that `_spender` is allowed to spend
     * on behalf of `_owner` through `transferFrom`. This is zero by default.
     *
     * @dev This value changes when `approve` or `transferFrom` is called.
     */
    function allowance(
        address _owner,
        address _spender
    ) public view override returns (uint256) {
        return allowances[_owner][_spender];
    }

    /**
     * @notice Atomically increases the allowance granted to `_spender` by the caller by `_addedValue`.
     *
     * This is an alternative to `approve` that can be used as a mitigation for
     * Emits an `Approval` event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `_spender` cannot be the the zero address.
     */
    function increaseAllowance(
        address _spender,
        uint256 _addedValue
    ) public returns (bool) {
        _approve(
            msg.sender,
            _spender,
            allowances[msg.sender][_spender] + _addedValue
        );
        return true;
    }

    /**
     * @notice Atomically decreases the allowance granted to `_spender` by the caller by `_subtractedValue`.
     *
     * This is an alternative to `approve` that can be used as a mitigation for
     * Emits an `Approval` event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `_spender` cannot be the zero address.
     * - `_spender` must have allowance for the caller of at least `_subtractedValue`.
     */
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @return the total amount of shares in existence.
     *
     * @dev The sum of all accounts' shares can be an arbitrary number, therefore
     * it is necessary to store it in order to calculate each account's relative share.
     */
    function getTotalShares() public view returns (uint256) {
        return _totalShares;
    }

    /**
     * @return the amount of shares owned by `_account`.
     */
    function sharesOf(address _account) public view returns (uint256) {
        return _sharesOf(_account);
    }

    /**
     * @return the amount of shares that corresponds to `_anchorUSDAmount` protocol-supplied AnchorUSD.
     */
    function getSharesByMintedAnchorUSD(
        uint256 _anchorUSDAmount
    ) public view returns (uint256) {
        uint256 totalMintedAnchorUSD = _totalSupply;
        if (totalMintedAnchorUSD == 0) {
            return _anchorUSDAmount;
        }
        return (_anchorUSDAmount * _totalShares) / totalMintedAnchorUSD;
    }

    /**
     * @return the amount of AnchorUSD that corresponds to `_sharesAmount` token shares.
     */
    function getMintedAnchorUSDByShares(
        uint256 _sharesAmount
    ) public view returns (uint256) {
        if (_totalShares == 0) {
            return 0;
        }
        return (_sharesAmount * _totalSupply) / _totalShares;
    }

    /**
     * @notice Sets `_amount` as the allowance of `_spender` over the `_owner` s tokens.
     *
     * Emits an `Approval` event.
     *
     * Requirements:
     *
     * - `_owner` cannot be the zero address.
     * - `_spender` cannot be the zero address.
     */
    function _approve(
        address _owner,
        address _spender,
        uint256 _amount,
        bool
    ) internal override {
        require(_owner != address(0), "APPROVE_FROM_ZERO_ADDRESS");
        require(_spender != address(0), "APPROVE_TO_ZERO_ADDRESS");

        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    /**
     * @return the amount of shares owned by `_account`.
     */
    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    /**
     * @notice Creates `sharesAmount` shares and assigns them to `_recipient`, increasing the total amount of shares.
     * @dev This operation also increases the total supply of tokens.
     *
     * Requirements:
     *
     * - `_recipient` cannot be the zero address.
     * - the contract must not be paused.
     */
    function mint(
        address _recipient,
        uint256 _mintAmount
    ) external onlyAnchorEngine {
        require(_mintAmount != 0, "ZA");
        _mint(_recipient, _mintAmount);
    }

    /**
     * @notice Destroys `sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
     * @dev This operation also decrease the total supply of tokens.
     *
     * Requirements:
     *
     * - `_account` cannot be the zero address.
     * - `_account` must hold at least `sharesAmount` shares.
     * - the contract must not be paused.
     */
    function burn(
        address _account,
        uint256 _burnAmount
    ) external onlyAnchorEngine {
        require(_burnAmount != 0, "ZA");
        _burn(_account, _burnAmount);
    }

    /**
     * @notice Destroys `sharesAmount` shares from `_account`'s holdings, decreasing the total amount of shares.
     * @dev This doesn't decrease the token total supply.
     *
     * Requirements:
     *
     * - `_account` cannot be the zero address.
     * - `_account` must hold at least `sharesAmount` shares.
     * - the contract must not be paused.
     */
    function burnShares(
        address _account,
        uint256 _sharesAmount
    ) external onlyAnchorEngine returns (uint256 newTotalShares) {
        require(_account != address(0), "BURN_FROM_THE_ZERO_ADDRESS");
        require(_sharesAmount != 0, "ZA");
        newTotalShares = _onlyBurnShares(_account, _sharesAmount);
    }

    function _onlyBurnShares(
        address _account,
        uint256 _sharesAmount
    ) private returns (uint256 newTotalShares) {
        uint256 accountShares = shares[_account];
        require(_sharesAmount <= accountShares, "BURN_AMOUNT_EXCEEDS_BALANCE");

        uint256 preRebaseTokenAmount = getMintedAnchorUSDByShares(
            _sharesAmount
        );

        newTotalShares = _totalShares - _sharesAmount;
        _totalShares = newTotalShares;

        shares[_account] = accountShares - _sharesAmount;

        uint256 postRebaseTokenAmount = getMintedAnchorUSDByShares(
            _sharesAmount
        );

        emit SharesBurnt(
            _account,
            preRebaseTokenAmount,
            postRebaseTokenAmount,
            _sharesAmount
        );

        // Notice: we're not emitting a Transfer event to the zero address here since shares burn
        // works by redistributing the amount of tokens corresponding to the burned shares between
        // all other token holders. The total supply of the token doesn't change as the result.
        // This is equivalent to performing a send from `address` to each other token holder address,
        // but we cannot reflect this as it would require sending an unbounded number of events.

        // We're emitting `SharesBurnt` event to provide an explicit rebase log record nonetheless.
    }

    // --- ERC 3156 ---

    function _flashFee(
        address,
        uint256 value
    ) internal pure override returns (uint256) {
        return (value * FLASH_LOAN_FEE) / 100_00;
    }

    function _flashFeeReceiver() internal view override returns (address) {
        return feeReceiver;
    }

    /**
     * @dev Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
     * (or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
     * this function.
     *
     * Emits a {Transfer} event.
     */

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        uint256 sharesAmount = getSharesByMintedAnchorUSD(value);
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            _totalSupply += value;
            _totalShares += sharesAmount;
        } else {
            uint256 fromShares = shares[from];
            if (fromShares < sharesAmount) {
                revert ERC20InsufficientBalance(
                    from,
                    getMintedAnchorUSDByShares(fromShares),
                    value
                );
            }
            unchecked {
                // Overflow not possible: sharesAmount <= fromShares <= totalShares.
                shares[from] = fromShares - sharesAmount;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                _totalSupply -= value;
                _totalShares -= sharesAmount;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                shares[to] += sharesAmount;
            }
        }

        emit Transfer(from, to, value);
        emit TransferShares(from, to, sharesAmount);
    }
}
