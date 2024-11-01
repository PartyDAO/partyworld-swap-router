//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { SafeTransferLib } from "solmate/src/utils/SafeTransferLib.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { BaseAggregator } from "src/BaseAggregator.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

// Modified from RainbowRouter: https://etherscan.io/address/0x00000000009726632680FB29d3F7A9734E3010E2#code
contract UnoRouter is BaseAggregator, Ownable {
    /// @dev Event emitted when a swap target gets added
    event SwapTargetAdded(address indexed target);

    /// @dev Event emitted when a swap target gets removed
    event SwapTargetRemoved(address indexed target);

    /// @dev Event emitted when token fees are withdrawn
    event TokenWithdrawn(address indexed token, address indexed target, uint256 amount);

    /// @dev Event emitted when ETH fees are withdrawn
    event EthWithdrawn(address indexed target, uint256 amount);

    constructor(
        address _owner,
        address[] memory _swapTargets,
        ISignatureTransfer _permit2
    )
        Ownable(_owner)
        BaseAggregator(_permit2)
    {
        for (uint256 i = 0; i < _swapTargets.length; i++) {
            swapTargets[_swapTargets[i]] = true;
        }
    }

    /// @dev We don't want to accept any ETH, except refunds from aggregators
    /// or the owner (for testing purposes), which can also withdraw
    /// This is done by evaluating the value of status, which is set to 2
    /// only during swaps due to the "nonReentrant" modifier
    receive() external payable {
        require(_reentrancyGuardEntered() || msg.sender == owner(), "NO_RECEIVE");
    }

    /// @dev method to add or remove swap targets from swapTargets
    /// This is required so we only approve "trusted" swap targets
    /// to transfer tokens out of this contract
    /// @param target address of the swap target to add
    /// @param add flag to add or remove the swap target
    function updateSwapTargets(address target, bool add) external onlyOwner {
        swapTargets[target] = add;
        if (add) {
            emit SwapTargetAdded(target);
        } else {
            emit SwapTargetRemoved(target);
        }
    }

    /// @dev method to withdraw ERC20 tokens (from the fees)
    /// @param token address of the token to withdraw
    /// @param to address that's receiving the tokens
    /// @param amount amount of tokens to withdraw
    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ZERO_ADDRESS");
        SafeTransferLib.safeTransfer(ERC20(token), to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    /// @dev method to withdraw ETH (from the fees)
    /// @param to address that's receiving the ETH
    /// @param amount amount of ETH to withdraw
    function withdrawEth(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "ZERO_ADDRESS");
        SafeTransferLib.safeTransferETH(to, amount);
        emit EthWithdrawn(to, amount);
    }
}
