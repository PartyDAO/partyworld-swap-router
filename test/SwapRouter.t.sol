// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/src/Test.sol";

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Permit2 } from "src/Permit2Helper.sol";
import { SwapRouter } from "src/SwapRouter.sol";
import { FeeToken } from "src/BaseAggregator.sol";
import { MockDEX } from "test/mocks/MockDEX.sol";

contract SwapRouterTest is Test {
    address owner;
    address user;
    uint256 userPrivateKey;
    SwapRouter router;
    MockDEX dex;
    ISignatureTransfer permit2;
    ERC20 usdce;
    ERC20 wld;

    bytes32 public constant _PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    bytes32 public constant _TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    function setUp() public {
        owner = makeAddr("owner");
        (user, userPrivateKey) = makeAddrAndKey("user");
        permit2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
        dex = MockDEX(0x7a8D8bddd596E6Ff90ad6E4f003565a1113710C6);
        address[] memory swapTargets = new address[](1);
        swapTargets[0] = address(dex);
        router = new SwapRouter(owner, swapTargets, permit2);
        usdce = ERC20(0x79A02482A880bCE3F13e09Da970dC34db4CD24d1);
        wld = ERC20(0x2cFc85d8E48F8EAB294be644d9E25C3030863003);

        deal(user, 100 ether);
        deal(address(usdce), user, 1000e6);
        deal(address(wld), user, 1000e18);
        deal(address(usdce), address(dex), 1_000_000e6);
        deal(address(wld), address(dex), 1_000_000e18);
        deal(address(dex), 1_000_000 ether);
        vm.startPrank(user);
        usdce.approve(address(permit2), type(uint256).max);
        wld.approve(address(permit2), type(uint256).max);
        vm.stopPrank();
    }

    function testFillQuoteEthToToken() public {
        uint256 feeAmount = 0.01 ether;
        uint256 ethAmount = 1 ether;
        uint256 buyAmount = 1000e6;
        bytes memory swapCallData =
            abi.encodeWithSignature("swapETHForTokens(address,uint256)", address(usdce), buyAmount);
        address payable target = payable(address(dex));

        uint256 ethBalanceBefore = address(user).balance;
        uint256 usdceBalanceBefore = usdce.balanceOf(user);

        vm.prank(user);
        router.fillQuoteEthToToken{ value: ethAmount }(address(usdce), target, swapCallData, feeAmount);

        assertEq(address(user).balance, ethBalanceBefore - ethAmount);
        assertEq(usdce.balanceOf(user), usdceBalanceBefore + buyAmount);
        assertEq(address(router).balance, feeAmount);
    }

    function testFillQuoteTokenToToken() public {
        uint256 sellAmount = 10e6;
        uint256 buyAmount = 10e18;
        uint256 feeAmount = 1e6;
        bytes memory swapCallData = abi.encodeWithSignature(
            "swapTokensForTokens(address,address,uint256,uint256)",
            address(usdce),
            address(wld),
            sellAmount - feeAmount,
            buyAmount
        );
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 30 minutes;
        address payable target = payable(address(dex));
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, address(usdce), sellAmount));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, address(router), nonce, deadline)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, msgHash);
        bytes memory signature = bytes.concat(r, s, bytes1(v));
        Permit2 memory permit = Permit2({ nonce: nonce, deadline: deadline, signature: signature });

        uint256 usdceBalanceBefore = usdce.balanceOf(user);
        uint256 wldBalanceBefore = wld.balanceOf(user);

        vm.prank(user);
        router.fillQuoteTokenToToken(
            address(usdce), address(wld), target, swapCallData, sellAmount, FeeToken.INPUT, feeAmount, permit
        );

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(wld.balanceOf(user), wldBalanceBefore + buyAmount);
        assertEq(usdce.balanceOf(address(router)), feeAmount);
    }

    function testFillQuoteTokenToEth() public {
        uint256 sellAmount = 10e6;
        uint256 buyAmount = 10e18;
        uint256 feePercentage = 0.1e18; // 10%
        uint256 feeAmount = (buyAmount * feePercentage) / 1e18;
        bytes memory swapCallData =
            abi.encodeWithSignature("swapTokensForETH(address,uint256,uint256)", address(usdce), sellAmount, buyAmount);
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 30 minutes;
        address payable target = payable(address(dex));
        bytes32 tokenPermissions = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, address(usdce), sellAmount));
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                permit2.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(_PERMIT_TRANSFER_FROM_TYPEHASH, tokenPermissions, address(router), nonce, deadline)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, msgHash);
        bytes memory signature = bytes.concat(r, s, bytes1(v));
        Permit2 memory permit = Permit2({ nonce: nonce, deadline: deadline, signature: signature });

        uint256 usdceBalanceBefore = usdce.balanceOf(user);
        uint256 ethBalanceBefore = address(user).balance;

        vm.prank(user);
        router.fillQuoteTokenToEth(address(usdce), target, swapCallData, sellAmount, feePercentage, permit);

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(address(user).balance, ethBalanceBefore + buyAmount - feeAmount);
        assertEq(address(router).balance, feeAmount);
    }
}
