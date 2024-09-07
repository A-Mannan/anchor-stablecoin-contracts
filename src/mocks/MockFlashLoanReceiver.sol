// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockFlashLoanReceiver is IERC3156FlashBorrower {
    address public immutable initiator;
    address public immutable flashLoanLender;

    constructor(address _initiator, address _flashLoanLender) {
        initiator = _initiator;
        flashLoanLender = _flashLoanLender;
    }

    function onFlashLoan(
        address _initiator,
        address _token,
        uint256 _amount,
        uint256 _fee,
        bytes calldata
    ) external override returns (bytes32) {
        require(msg.sender == flashLoanLender, "not the flash loaner");
        require(_initiator == initiator, "not the initiator");

        
        // Handle the flash loan (e.g., use the borrowed tokens)

        // Repay the flash loan + fee
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(
            balance >= _amount + _fee,
            "ERC3156FlashBorrower: insufficient balance"
        );
        IERC20(_token).approve(msg.sender, _amount + _fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}
