// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/LotteryPool.sol";

contract LotteryPoolTest is Test {
    LotteryPool public lotteryPool;
    address public owner;
    address public creator1;
    address public creator2;
    address public participant1;
    address public participant2;
    
    uint256 public initialPoolId;

    function setUp() public {
        lotteryPool = new LotteryPool();
        owner = address(this);
        creator1 = address(0x1);
        creator2 = address(0x2);
        participant1 = address(0x3);
        participant2 = address(0x4);

        // Fund the contract with some ether for testing
        vm.deal(address(this), 10 ether);
    }

    function testCreatePool() public {
        vm.startPrank(creator1);

        // Creator pays the pool creation fee and creates a pool
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);

        uint256 poolId = lotteryPool.poolCounter();
        (uint256 id, address creator, uint256 creatorAllocation, uint256 targetAmount, uint256 currentAmount, address winner, bool active, address[] memory participants, uint256 finalCreatorAllocation) = lotteryPool.getPoolDetails(poolId);

        assertEq(id, poolId);
        assertEq(creator, creator1);
        assertEq(creatorAllocation, 0);
        assertEq(targetAmount, 0.5 ether);
        assertEq(currentAmount, 0);
        assertEq(winner, address(0));
        assertTrue(active);
        assertEq(participants.length, 0);
        assertEq(finalCreatorAllocation, 0);

        vm.stopPrank();
    }

    function testParticipateInPool() public {
        vm.startPrank(creator1);

        // Create a pool
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        initialPoolId = lotteryPool.poolCounter();
        vm.stopPrank();

        vm.startPrank(participant1);
        // Participant deposits into the pool
        lotteryPool.participateInPool{value: 1 ether}(initialPoolId);

        (uint256 poolId, , uint256 creatorAllocation, , uint256 currentAmount, , bool active, address[] memory participants, ) = lotteryPool.getPoolDetails(initialPoolId);

        assertEq(poolId, initialPoolId);
        assertEq(currentAmount, 0.93 ether); // 1 ether - creator fee (0.05 ether) - founder fee (0.02 ether)
        assertTrue(active);
        assertEq(participants.length, 1);
        assertEq(participants[0], participant1);

        vm.stopPrank();
    }

    function testWinnerSelection() public {
        vm.startPrank(creator1);

        // Create a pool
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        uint256 poolId = lotteryPool.poolCounter();
        vm.stopPrank();

        vm.startPrank(participant1);
        lotteryPool.participateInPool{value: 0.3 ether}(poolId);
        vm.stopPrank();

        vm.startPrank(participant2);
        lotteryPool.participateInPool{value: 0.2 ether}(poolId);
        vm.stopPrank();

        // At this point, the pool should be active and the target amount should be met

        vm.warp(block.timestamp + 1 hours); // Advance time to trigger the pool closing
        vm.startPrank(participant1);
        lotteryPool.participateInPool{value: 0.1 ether}(poolId); // Ensure pool gets fully funded
        vm.stopPrank();

        // Test that a winner is selected and funds are distributed
        (uint256 id, , , , uint256 currentAmount, address winner, bool active, , ) = lotteryPool.getPoolDetails(poolId);

        assertFalse(active);
        assertEq(id, poolId);
        assertEq(currentAmount, 0);
        assertTrue(winner == participant1 || winner == participant2);

        vm.stopPrank();
    }

    function testWithdrawCreatorAllocation() public {
        vm.startPrank(creator1);

        // Create and fund a pool
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        uint256 poolId = lotteryPool.poolCounter();
        lotteryPool.participateInPool{value: 1 ether}(poolId);

        // End the pool
        vm.warp(block.timestamp + 1 hours);
        lotteryPool.participateInPool{value: 0.4 ether}(poolId); // Fund to meet target
        lotteryPool.withdrawCreatorAllocation(poolId);

        (uint256 allocation, ) = lotteryPool.getPoolDetails(poolId);
        assertEq(allocation, 0);

        vm.stopPrank();
    }

    function testWithdrawAllCreatorAllocations() public {
        vm.startPrank(creator1);

        // Create and fund multiple pools
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        uint256 poolId1 = lotteryPool.poolCounter();
        lotteryPool.participateInPool{value: 0.5 ether}(poolId1);
        
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        uint256 poolId2 = lotteryPool.poolCounter();
        lotteryPool.participateInPool{value: 0.5 ether}(poolId2);

        // End the pools
        vm.warp(block.timestamp + 1 hours);
        lotteryPool.participateInPool{value: 0.5 ether}(poolId1);
        lotteryPool.participateInPool{value: 0.5 ether}(poolId2);
        lotteryPool.withdrawAllCreatorAllocations();

        (uint256 allocation1, ) = lotteryPool.getPoolDetails(poolId1);
        (uint256 allocation2, ) = lotteryPool.getPoolDetails(poolId2);

        assertEq(allocation1, 0);
        assertEq(allocation2, 0);

        vm.stopPrank();
    }

    function testWithdrawFounderAllocation() public {
        vm.startPrank(owner);

        // Create a pool
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        vm.stopPrank();

        // Fund the pool
        vm.startPrank(participant1);
        lotteryPool.participateInPool{value: 1 ether}(1);
        vm.stopPrank();

        // Withdraw founder allocation
        vm.startPrank(owner);
        lotteryPool.withdrawFounderAllocation();
        uint256 founderAllocation = lotteryPool.founderAllocation();
        assertEq(founderAllocation, 0);
        vm.stopPrank();
    }

    function testWithdrawPending() public {
        vm.startPrank(creator1);

        // Create and fund a pool
        lotteryPool.createPool{value: 0.1 ether}(0.5 ether);
        uint256 poolId = lotteryPool.poolCounter();
        lotteryPool.participateInPool{value: 1 ether}(poolId);
        vm.stopPrank();

        // End the pool
        vm.warp(block.timestamp + 1 hours);
        lotteryPool.participateInPool{value: 0.5 ether}(poolId);

        // Withdraw pending funds
        vm.startPrank(participant1);
        lotteryPool.withdrawPending();
        uint256 pendingAmount = lotteryPool.pendingWithdrawals(participant1);
        assertEq(pendingAmount, 0);
        vm.stopPrank();
    }
}
