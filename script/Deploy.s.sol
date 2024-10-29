// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console } from "forge-std/src/console.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { SwapRouter } from "src/SwapRouter.sol";
import { MockDEX } from "test/mocks/MockDEX.sol";

contract Deploy is Script {
    function run() public {
        ISignatureTransfer permit2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

        vm.startBroadcast();
        MockDEX mockDex = new MockDEX();
        address[] memory swapTargets = new address[](1);
        swapTargets[0] = address(mockDex);
        SwapRouter router = new SwapRouter(msg.sender, swapTargets, permit2);
        vm.stopBroadcast();

        console.log("Router deployed at", address(router));
        console.log("MockDEX deployed at", address(mockDex));
    }
}
