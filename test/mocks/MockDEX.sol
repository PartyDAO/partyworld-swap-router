//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";

contract MockDEX {
    function swapTokensForTokens(
        ERC20 sellToken,
        ERC20 buyToken,
        uint256 sellAmount,
        uint256 buyAmount
    )
        external
        payable
    {
        SafeTransferLib.safeTransferFrom(sellToken, msg.sender, address(this), sellAmount);
        SafeTransferLib.safeTransfer(buyToken, msg.sender, buyAmount);
    }

    function swapTokensForETH(ERC20 sellToken, uint256 sellAmount, uint256 buyAmount) external {
        SafeTransferLib.safeTransferFrom(sellToken, msg.sender, address(this), sellAmount);
        payable(msg.sender).call{ value: buyAmount }("");
    }

    function swapETHForTokens(ERC20 buyToken, uint256 buyAmount) external payable {
        SafeTransferLib.safeTransfer(buyToken, msg.sender, buyAmount);
    }

    function swapPartialETHForTokens(ERC20 buyToken, uint256 buyAmount, uint256 remainingEth) external payable {
        SafeTransferLib.safeTransfer(buyToken, msg.sender, buyAmount);
        if (remainingEth > 0) {
            payable(msg.sender).call{ value: remainingEth }("");
        }
    }
}
