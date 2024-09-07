// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.19;

contract Governable {
    address public governance;

    event GovernanceAuthorityTransfer(address newGovernance);

    modifier onlyGovernance() {
        require(msg.sender == governance, "Governable: forbidden");
        _;
    }

    function setGovernance(address _governance) external onlyGovernance {
        governance = _governance;
        emit GovernanceAuthorityTransfer(_governance);
    }
}
