// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";

struct Permit2 {
    uint256 nonce;
    uint256 deadline;
    bytes signature;
}

contract Permit2Helper {
    ISignatureTransfer public immutable permit2;

    constructor(ISignatureTransfer _permit2) {
        permit2 = _permit2;
    }
}
