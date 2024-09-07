// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

interface IAnchorUSD {
    function totalSupply() external view returns (uint256);

    function getTotalShares() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function sharesOf(address _account) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address _spender, uint256 _amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);


    function getSharesByMintedAnchorUSD(
        uint256 _AnchorUSDAmount
    ) external view returns (uint256);

    function getMintedAnchorUSDByShares(
        uint256 _sharesAmount
    ) external view returns (uint256);

    function mint(
        address _recipient,
        uint256 _mintAmount
    ) external;

    function burnShares(
        address _account,
        uint256 burnAmount
    ) external returns (uint256 newTotalShares);

    function burn(
        address _account,
        uint256 burnAmount
    ) external;

    function transfer(address to, uint256 amount) external returns (bool);
}
