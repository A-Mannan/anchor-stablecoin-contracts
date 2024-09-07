// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurveLPToken {
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function minter() external view returns (address);

    function decimals() external view returns (uint8);

    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool);
    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool);

    function mint(address _to, uint256 _value) external returns (bool);
    function burnFrom(address _to, uint256 _value) external returns (bool);

    function set_minter(address _minter) external;
    function set_name(string calldata _name, string calldata _symbol) external;
}

interface ICurve {
    function owner() external view returns (address);
}
