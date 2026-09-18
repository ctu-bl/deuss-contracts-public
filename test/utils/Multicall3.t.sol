// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Multicall3} from "src/utils/Multicall3.sol";

contract Multicall3Target {
    error ForcedRevert();

    event ValueReceived(uint256 indexed value);

    function echo(uint256 value) external pure returns (uint256) {
        return value;
    }

    function shouldRevert() external pure {
        revert ForcedRevert();
    }

    function payableEcho() external payable returns (uint256) {
        emit ValueReceived(msg.value);
        return msg.value;
    }
}

contract Multicall3Test is Test {
    Multicall3 private _multicall;
    Multicall3Target private _target;

    function setUp() public {
        _multicall = new Multicall3();
        _target = new Multicall3Target();
    }

    function test_aggregate_success_and_revert() public {
        Multicall3.Call[] memory calls = new Multicall3.Call[](2);
        calls[0] = Multicall3.Call({target: address(_target), callData: abi.encodeCall(_target.echo, (1))});
        calls[1] = Multicall3.Call({target: address(_target), callData: abi.encodeCall(_target.echo, (2))});

        (uint256 blockNumber, bytes[] memory returnData) = _multicall.aggregate(calls);
        assertEq(blockNumber, block.number);
        assertEq(abi.decode(returnData[0], (uint256)), 1);
        assertEq(abi.decode(returnData[1], (uint256)), 2);

        Multicall3.Call[] memory failingCalls = new Multicall3.Call[](1);
        failingCalls[0] =
            Multicall3.Call({target: address(_target), callData: abi.encodeCall(_target.shouldRevert, ())});

        vm.expectRevert("Multicall3: call failed");
        _multicall.aggregate(failingCalls);
    }

    function test_tryAggregate_paths() public {
        Multicall3.Call[] memory calls = new Multicall3.Call[](2);
        calls[0] = Multicall3.Call({target: address(_target), callData: abi.encodeCall(_target.echo, (7))});
        calls[1] = Multicall3.Call({target: address(_target), callData: abi.encodeCall(_target.shouldRevert, ())});

        Multicall3.Result[] memory results = _multicall.tryAggregate(false, calls);
        assertTrue(results[0].success);
        assertFalse(results[1].success);

        vm.expectRevert("Multicall3: call failed");
        _multicall.tryAggregate(true, calls);
    }

    function test_blockAndAggregate_helpers() public {
        Multicall3.Call[] memory calls = new Multicall3.Call[](1);
        calls[0] = Multicall3.Call({target: address(_target), callData: abi.encodeCall(_target.echo, (9))});

        (uint256 blockNumber, bytes32 blockHash, Multicall3.Result[] memory results) =
            _multicall.tryBlockAndAggregate(false, calls);
        assertEq(blockNumber, block.number);
        assertEq(blockHash, blockhash(block.number));
        assertTrue(results[0].success);

        (uint256 blockNumber2, bytes32 blockHash2, Multicall3.Result[] memory results2) =
            _multicall.blockAndAggregate(calls);
        assertEq(blockNumber2, block.number);
        assertEq(blockHash2, blockhash(block.number));
        assertTrue(results2[0].success);
    }

    function test_aggregate3_paths() public {
        Multicall3.Call3[] memory calls = new Multicall3.Call3[](2);
        calls[0] = Multicall3.Call3({
            target: address(_target), allowFailure: true, callData: abi.encodeCall(_target.shouldRevert, ())
        });
        calls[1] = Multicall3.Call3({
            target: address(_target), allowFailure: false, callData: abi.encodeCall(_target.echo, (5))
        });

        Multicall3.Result[] memory results = _multicall.aggregate3(calls);
        assertFalse(results[0].success);
        assertTrue(results[1].success);

        Multicall3.Call3[] memory failingCalls = new Multicall3.Call3[](1);
        failingCalls[0] = Multicall3.Call3({
            target: address(_target), allowFailure: false, callData: abi.encodeCall(_target.shouldRevert, ())
        });

        vm.expectRevert("Multicall3: call failed");
        _multicall.aggregate3(failingCalls);
    }

    function test_aggregate3Value_paths() public {
        Multicall3.Call3Value[] memory calls = new Multicall3.Call3Value[](2);
        calls[0] = Multicall3.Call3Value({
            target: address(_target),
            allowFailure: false,
            value: 1 ether,
            callData: abi.encodeCall(_target.payableEcho, ())
        });
        calls[1] = Multicall3.Call3Value({
            target: address(_target), allowFailure: true, value: 0, callData: abi.encodeCall(_target.shouldRevert, ())
        });

        Multicall3.Result[] memory results = _multicall.aggregate3Value{value: 1 ether}(calls);
        assertTrue(results[0].success);
        assertFalse(results[1].success);
        assertEq(abi.decode(results[0].returnData, (uint256)), 1 ether);

        Multicall3.Call3Value[] memory failingCalls = new Multicall3.Call3Value[](1);
        failingCalls[0] = Multicall3.Call3Value({
            target: address(_target), allowFailure: false, value: 0, callData: abi.encodeCall(_target.shouldRevert, ())
        });

        vm.expectRevert("Multicall3: call failed");
        _multicall.aggregate3Value(failingCalls);

        Multicall3.Call3Value[] memory mismatchCalls = new Multicall3.Call3Value[](1);
        mismatchCalls[0] = Multicall3.Call3Value({
            target: address(_target),
            allowFailure: true,
            value: 1 ether,
            callData: abi.encodeCall(_target.payableEcho, ())
        });

        vm.expectRevert("Multicall3: value mismatch");
        _multicall.aggregate3Value{value: 0}(mismatchCalls);
    }

    function test_view_helpers() public {
        vm.roll(100);
        vm.coinbase(address(0xBEEF));
        vm.fee(1 gwei);

        address account = makeAddr("balance");
        vm.deal(account, 5 ether);

        assertEq(_multicall.getBlockHash(block.number - 1), blockhash(block.number - 1));
        assertEq(_multicall.getBlockNumber(), block.number);
        assertEq(_multicall.getCurrentBlockCoinbase(), block.coinbase);
        assertEq(_multicall.getCurrentBlockGasLimit(), block.gaslimit);
        assertEq(_multicall.getCurrentBlockTimestamp(), block.timestamp);
        assertEq(_multicall.getEthBalance(account), account.balance);
        assertEq(_multicall.getLastBlockHash(), blockhash(block.number - 1));
        assertEq(_multicall.getBasefee(), block.basefee);
        assertEq(_multicall.getChainId(), block.chainid);
    }
}
