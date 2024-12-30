// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWithdrawalQueueERC721 {
    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    function claimWithdrawals(
        uint256[] calldata _requestIds,
        uint256[] calldata _hints
    ) external;
}
