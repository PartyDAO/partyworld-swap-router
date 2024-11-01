// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console } from "forge-std/src/console.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { UnoRouter } from "src/UnoRouter.sol";

contract Deploy is Script {
    function run() public {
        ISignatureTransfer permit2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        address uniswapSwapRouter = 0x091AD9e2e6e5eD44c1c66dB50e49A601F9f36cF6;

        vm.startBroadcast();
        address[] memory swapTargets = new address[](1);
        swapTargets[0] = uniswapSwapRouter;
        UnoRouter router = new UnoRouter(msg.sender, swapTargets, permit2);
        vm.stopBroadcast();

        console.log("Router deployed at", address(router));
    }
}
