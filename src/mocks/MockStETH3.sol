// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockStETH is IERC20, Ownable {
    // Errors
    error MockStETH__AmountShouldBeMoreThanZero();
    error MockStETH__InsufficientBalance();
    error MockStETH__InsufficientAllowance();

    // State Variables
    uint256 public totalPooledEth;
    uint256 public totalShares;
    mapping(address user => uint256 sharesAmount) private shares;
    mapping(address user => mapping(address spender => uint256 amount))
        private allowances;
    address private immutable initialTokenHolder;
    uint256 private constant INITIAL_TOKEN_SUPPLY=1e8;

    // Events
    event TransferShares(
        address indexed from,
        address indexed to,
        uint256 sharesValue
    );
    event Submitted(address indexed sender, uint256 amount);

    // Functions

    constructor() Ownable(msg.sender) {
        initialTokenHolder = msg.sender;
        _mintInitialShares();
    }

    // External Functions
    function name() external pure returns (string memory) {
        return "Mocked Liquid staked Ether";
    }

    function symbol() external pure returns (string memory) {
        return "MStETH";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return totalPooledEth;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return getPooledEthByShares(sharesOf(_account));
    }


    function allowance(
        address _owner,
        address _spender
    ) external view returns (uint256) {
        return allowances[_owner][_spender];
    }

    function accumulateRewards(uint256 rewards) external onlyOwner {
        totalPooledEth += rewards;
    }

    function transfer(
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        _transfer(msg.sender, _recipient, _amount);
        return true;
    }

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) external returns (bool) {
        _spendAllowance(_sender, msg.sender, _amount);
        _transfer(_sender, _recipient, _amount);
        return true;
    }

    function approve(
        address _spender,
        uint256 _amount
    ) external returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function submit() external payable {
        if (msg.value == 0) {
            revert MockStETH__AmountShouldBeMoreThanZero();
        }
        uint256 sharesAmount = getSharesByPooledEth(msg.value);

        _mintShares(msg.sender, sharesAmount);
        totalPooledEth += msg.value;

        emit Submitted(msg.sender, msg.value);

        _emitTransferAfterMintingShares(msg.sender, sharesAmount);
    }

    // Public Functions

    function sharesOf(address _account) public view returns (uint256) {
        return shares[_account];
    }

    function getPooledEthByShares(
        uint256 _sharesAmount
    ) public view returns (uint256) {
        return (_sharesAmount * totalPooledEth) / totalShares;
    }

    function getSharesByPooledEth(
        uint256 _ethAmount
    ) public view returns (uint256) {
        return (_ethAmount * totalShares) / totalPooledEth;
    }

    // Internal Functions
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal {
        uint256 _sharesToTransfer = getSharesByPooledEth(_amount);
        _transferShares(_sender, _recipient, _sharesToTransfer);
        _emitTransferEvents(_sender, _recipient, _amount, _sharesToTransfer);
    }

    function _emitTransferEvents(
        address _from,
        address _to,
        uint _tokenAmount,
        uint256 _sharesAmount
    ) internal {
        emit Transfer(_from, _to, _tokenAmount);
        emit TransferShares(_from, _to, _sharesAmount);
    }

    function _emitTransferAfterMintingShares(
        address _to,
        uint256 _sharesAmount
    ) internal {
        _emitTransferEvents(
            address(0),
            _to,
            getPooledEthByShares(_sharesAmount),
            _sharesAmount
        );
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _spendAllowance(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal {
        uint256 currentAllowance = allowances[_owner][_spender];
        if (currentAllowance < _amount) {
            revert MockStETH__InsufficientAllowance();
        }
        _approve(_owner, _spender, currentAllowance - _amount);
    }

    function _transferShares(
        address _sender,
        address _recipient,
        uint256 _sharesAmount
    ) internal {
        uint256 currentSenderShares = shares[_sender];
        if (_sharesAmount > currentSenderShares) {
            revert MockStETH__InsufficientBalance();
        }

        shares[_sender] -= _sharesAmount;
        shares[_recipient] += _sharesAmount;
    }

    function _mintShares(address _recipient, uint256 _sharesAmount) internal {
        totalShares += _sharesAmount;
        shares[_recipient] += _sharesAmount;
    }

    // Private Functions
    function _mintInitialShares() private {
        totalPooledEth += INITIAL_TOKEN_SUPPLY;
        _mintShares(initialTokenHolder, INITIAL_TOKEN_SUPPLY);
        _emitTransferAfterMintingShares(initialTokenHolder, INITIAL_TOKEN_SUPPLY);
    }
}
