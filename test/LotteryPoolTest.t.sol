// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../src/LotteryPool.sol";

contract LotteryPoolTest is Test {
    LotteryPool public lotteryPool;
    address public creator = address(0xBEEF);
    address public participant1 = address(0xCAFE);
    address public participant2 = address(0xDEAD);

    function setUp() public {
        lotteryPool = new LotteryPool();
        vm.deal(creator, 100 ether);
        vm.deal(participant1, 100 ether);
        vm.deal(participant2, 100 ether);
    }

    function testCreatePool() public {
        vm.startPrank(creator);

        uint256 targetAmount = 8 ether;
        uint256 fee = 0.1 ether;

        lotteryPool.createPool{value: fee}(targetAmount);

        (
            uint256 poolId,
            address poolCreator,
            uint256 creatorAllocation,
            uint256 targetAmountRes,
            uint256 currentAmount,
            address winner,
            bool active,
            address[] memory participants,
            uint256 finalCreatorAllocation
        ) = lotteryPool.getPoolDetails(1);

        assertEq(poolId, 1);
        assertEq(creatorAllocation, 0);
        assertEq(currentAmount, 0);
        assertEq(active, true);

        vm.stopPrank();
    }

    function testParticipateInPool() public {
        testCreatePool();

        vm.startPrank(participant1);
        uint256 depositAmount = 2 ether;

        vm.expectRevert("Pool is not active");
        lotteryPool.participateInPool{value: depositAmount}(2);

        lotteryPool.participateInPool{value: depositAmount}(1);

        (
            uint256 poolId,
            address poolCreator,
            uint256 creatorAllocation,
            uint256 targetAmountRes,
            uint256 currentAmount,
            address winner,
            bool active,
            address[] memory participants,
            uint256 finalCreatorAllocation
        ) = lotteryPool.getPoolDetails(1);

        assertEq(currentAmount, 1.86 ether);
        assertEq(creatorAllocation, 0.1 ether);
        assertEq(active, true);

        vm.stopPrank();
    }

    function testWinnerSelection() public {
        testCreatePool();

        vm.startPrank(participant1);
        lotteryPool.participateInPool{value: 5 ether}(1);
        vm.stopPrank();

        vm.startPrank(participant2);
        lotteryPool.participateInPool{value: 5 ether}(1);
        vm.stopPrank();

        (
            uint256 poolId,
            address poolCreator,
            uint256 creatorAllocation,
            uint256 targetAmountRes,
            uint256 currentAmount,
            address winner,
            bool active,
            address[] memory participants,
            uint256 finalCreatorAllocation
        ) = lotteryPool.getPoolDetails(1);

        assertEq(active, false);
        assertEq(currentAmount, 9.3 ether);
        assertEq(creatorAllocation, 0.5 ether);

        bool winnerIsParticipant1 = (winner == participant1);
        bool winnerIsParticipant2 = (winner == participant2);
        assertTrue(winnerIsParticipant1 || winnerIsParticipant2);
    }


    function testWithdrawCreatorAllocation() public {
        testWinnerSelection();

        vm.startPrank(creator);

        uint256 withdrawableAmount = lotteryPool.getWithdrawableAmount(creator);
        assertEq(withdrawableAmount, 0.5 ether);

        lotteryPool.withdrawCreatorAllocation(1);

        (
            uint256 poolId,
            address poolCreator,
            uint256 creatorAllocation,
            uint256 targetAmountRes,
            uint256 currentAmount,
            address winner,
            bool active,
            address[] memory participants,
            uint256 finalCreatorAllocation
        ) = lotteryPool.getPoolDetails(1);

        assertEq(creatorAllocation, 0); 

        vm.stopPrank();
    }

}
