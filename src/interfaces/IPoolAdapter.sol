// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.15;

interface IPoolAdapter {
    function pool() external view returns (address);
    function getDy(address inputToken, address outputToken, uint256 inputAmount) external view returns (uint256);
    function melt(address inputToken, address outputToken, uint256 inputAmount, uint256 minimumAmountOut) external returns (uint256);
}