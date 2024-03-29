// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/interfaces/IERC4626.sol";

interface ISteakedDegen is IERC4626 {
    event FanSet(address indexed user, bool isFan);
    event InitialDeposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
    event SteakFeePaid(address indexed caller, uint256 amount);
    event DaoFeePaid(address indexed caller, uint256 amount);

    function setFan(address user, bool isFan) external;
    function isFan(address user) external view returns (bool);
    function steakFee() external view returns (uint256);
    function initialDeposit(uint256 assets, address receiver) external;
}
