// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockWithdrawalQueueERC721 {
    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    mapping(uint256 => WithdrawalRequestStatus) public withdrawalRequests;
    uint256 public nextRequestId = 1;
    mapping(address => uint256[]) public userRequests;

    event WithdrawalRequested(
        uint256 requestId,
        uint256 amountOfStETH,
        address owner
    );
    event WithdrawalFinalized(uint256 requestId);
    event WithdrawalClaimed(
        uint256 requestId,
        address owner,
        uint256 ethAmount
    );

    function requestWithdrawals(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds) {
        requestIds = new uint256[](_amounts.length);

        for (uint256 i = 0; i < _amounts.length; i++) {
            uint256 requestId = nextRequestId++;
            withdrawalRequests[requestId] = WithdrawalRequestStatus({
                amountOfStETH: _amounts[i],
                owner: _owner,
                timestamp: block.timestamp,
                isFinalized: false,
                isClaimed: false
            });
            userRequests[_owner].push(requestId);

            emit WithdrawalRequested(requestId, _amounts[i], _owner);
            requestIds[i] = requestId;
        }
    }

    function finalizeWithdrawal(uint256 requestId) external {
        WithdrawalRequestStatus storage request = withdrawalRequests[requestId];
        require(!request.isFinalized, "Already finalized");

        request.isFinalized = true;
        emit WithdrawalFinalized(requestId);
    }

    function claimWithdrawals(
        uint256[] calldata _requestIds,
        uint256[] calldata /*_hints*/
    ) external {
        for (uint256 i = 0; i < _requestIds.length; i++) {
            uint256 requestId = _requestIds[i];
            WithdrawalRequestStatus storage request = withdrawalRequests[
                requestId
            ];

            require(request.isFinalized, "Not finalized");
            require(!request.isClaimed, "Already claimed");
            require(request.owner == msg.sender, "Not the owner");

            request.isClaimed = true;

            // Simulate sending ETH equivalent to the amount of stETH
            uint256 ethAmount = request.amountOfStETH; // 1:1 ratio for simplicity
            payable(msg.sender).transfer(ethAmount);

            emit WithdrawalClaimed(requestId, msg.sender, ethAmount);
        }
    }

    function getWithdrawalRequests(
        address _owner
    ) external view returns (uint256[] memory requestsIds) {
        return userRequests[_owner];
    }

    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses) {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);

        for (uint256 i = 0; i < _requestIds.length; i++) {
            statuses[i] = withdrawalRequests[_requestIds[i]];
        }
    }
}
