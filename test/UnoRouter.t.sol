// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/src/Test.sol";

import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { ERC20 } from "solmate/src/tokens/ERC20.sol";
import { Permit2 } from "src/Permit2Helper.sol";
import { UnoRouter } from "src/UnoRouter.sol";
import { BaseAggregator, FeeToken } from "src/BaseAggregator.sol";
import { MockDEX } from "test/mocks/MockDEX.sol";

contract UnoRouterTest is Test {
    address owner;
    address user;
    uint256 userPrivateKey;
    UnoRouter router;
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
        dex = new MockDEX();
        address[] memory swapTargets = new address[](1);
        swapTargets[0] = address(dex);
        router = new UnoRouter(owner, swapTargets, permit2);
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

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteEthToToken(
            address(usdce),
            target,
            user,
            ethAmount - feeAmount, // Should exclude fee amount
            buyAmount,
            feeAmount
        );

        vm.prank(user);
        router.fillQuoteEthToToken{ value: ethAmount }(address(usdce), target, swapCallData, feeAmount);

        assertEq(address(user).balance, ethBalanceBefore - ethAmount);
        assertEq(usdce.balanceOf(user), usdceBalanceBefore + buyAmount);
        assertEq(address(router).balance, feeAmount);
    }

    function testFillQuoteEthToToken_withEthRemaining() public {
        uint256 feeAmount = 0.01 ether;
        uint256 ethAmount = 1 ether;
        uint256 buyAmount = 1000e6;
        uint256 remainingEth = 0.001 ether;
        bytes memory swapCallData = abi.encodeWithSignature(
            "swapPartialETHForTokens(address,uint256,uint256)", address(usdce), buyAmount, remainingEth
        );
        address payable target = payable(address(dex));

        uint256 ethBalanceBefore = address(user).balance;
        uint256 usdceBalanceBefore = usdce.balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteEthToToken(
            address(usdce),
            target,
            user,
            ethAmount - feeAmount - remainingEth, // Should exclude fee amount and remainingEth
            buyAmount,
            feeAmount
        );

        vm.prank(user);
        router.fillQuoteEthToToken{ value: ethAmount }(address(usdce), target, swapCallData, feeAmount);

        assertEq(address(user).balance, ethBalanceBefore - ethAmount + remainingEth);
        assertEq(usdce.balanceOf(user), usdceBalanceBefore + buyAmount);
        assertEq(address(router).balance, feeAmount);
    }

    function testFillQuoteEthToToken_withNoFee() public {
        uint256 ethAmount = 1 ether;
        uint256 buyAmount = 1000e6;
        bytes memory swapCallData =
            abi.encodeWithSignature("swapETHForTokens(address,uint256)", address(usdce), buyAmount);
        address payable target = payable(address(dex));

        uint256 ethBalanceBefore = address(user).balance;
        uint256 usdceBalanceBefore = usdce.balanceOf(user);

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteEthToToken(address(usdce), target, user, ethAmount, buyAmount, 0);

        vm.prank(user);
        router.fillQuoteEthToToken{ value: ethAmount }(address(usdce), target, swapCallData, 0);

        assertEq(address(user).balance, ethBalanceBefore - ethAmount);
        assertEq(usdce.balanceOf(user), usdceBalanceBefore + buyAmount);
        assertEq(address(router).balance, 0);
    }

    function testFillQuoteTokenToToken_withInputTokenFee() public {
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

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteTokenToToken(
            address(usdce),
            address(wld),
            user,
            target,
            sellAmount - feeAmount, // Should exclude fee amount
            buyAmount,
            FeeToken.INPUT,
            feeAmount
        );

        vm.prank(user);
        router.fillQuoteTokenToToken(
            address(usdce), address(wld), target, swapCallData, sellAmount, FeeToken.INPUT, feeAmount, permit
        );

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(wld.balanceOf(user), wldBalanceBefore + buyAmount);
        assertEq(usdce.balanceOf(address(router)), feeAmount);
    }

    function testFillQuoteTokenToToken_withOutputTokenFee() public {
        uint256 sellAmount = 10e6;
        uint256 buyAmount = 10e18;
        uint256 feeAmount = 1e18;
        bytes memory swapCallData = abi.encodeWithSignature(
            "swapTokensForTokens(address,address,uint256,uint256)", address(usdce), address(wld), sellAmount, buyAmount
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

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteTokenToToken(
            address(usdce),
            address(wld),
            user,
            target,
            sellAmount,
            buyAmount - feeAmount, // Should exclude fee amount
            FeeToken.OUTPUT,
            feeAmount
        );

        vm.prank(user);
        router.fillQuoteTokenToToken(
            address(usdce), address(wld), target, swapCallData, sellAmount, FeeToken.OUTPUT, feeAmount, permit
        );

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(wld.balanceOf(user), wldBalanceBefore + buyAmount - feeAmount);
        assertEq(wld.balanceOf(address(router)), feeAmount);
    }

    function testFillQuoteTokenToToken_withNoFee() public {
        uint256 sellAmount = 10e6;
        uint256 buyAmount = 10e18;
        bytes memory swapCallData = abi.encodeWithSignature(
            "swapTokensForTokens(address,address,uint256,uint256)", address(usdce), address(wld), sellAmount, buyAmount
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

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteTokenToToken(
            address(usdce), address(wld), user, target, sellAmount, buyAmount, FeeToken.INPUT, 0
        );

        vm.prank(user);
        router.fillQuoteTokenToToken(
            address(usdce), address(wld), target, swapCallData, sellAmount, FeeToken.INPUT, 0, permit
        );

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(wld.balanceOf(user), wldBalanceBefore + buyAmount);
        assertEq(usdce.balanceOf(address(router)), 0);
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

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteTokenToEth(
            address(usdce),
            user,
            target,
            sellAmount,
            buyAmount - feeAmount, // Should exclude fee amount
            feeAmount
        );

        vm.prank(user);
        router.fillQuoteTokenToEth(address(usdce), target, swapCallData, sellAmount, feePercentage, permit);

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(address(user).balance, ethBalanceBefore + buyAmount - feeAmount);
        assertEq(address(router).balance, feeAmount);
    }

    function testFillQuoteTokenToEth_withNoFee() public {
        uint256 sellAmount = 10e6;
        uint256 buyAmount = 10e18;
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

        vm.expectEmit(true, true, true, true);
        emit BaseAggregator.FillQuoteTokenToEth(address(usdce), user, target, sellAmount, buyAmount, 0);

        vm.prank(user);
        router.fillQuoteTokenToEth(address(usdce), target, swapCallData, sellAmount, 0, permit);

        assertEq(usdce.balanceOf(user), usdceBalanceBefore - sellAmount);
        assertEq(address(user).balance, ethBalanceBefore + buyAmount);
        assertEq(address(router).balance, 0);
    }
}
