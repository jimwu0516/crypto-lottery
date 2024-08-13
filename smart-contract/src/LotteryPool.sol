// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LotteryPool is ReentrancyGuard {
    struct Pool {
        uint256 poolId;
        address creator;
        uint256 creatorAllocation;
        uint256 targetAmount;
        uint256 currentAmount;
        address winner;
        bool active;
        address[] participants;
        mapping(address => uint256) deposits;
        mapping(address => bool) isParticipant;
        uint256 finalCreatorAllocation;
    }

    address public owner;
    uint256 public founderAllocation;
    uint256 public poolCreationFee = 0.0001 ether;
    uint256 public participantFeePercent = 7;
    uint256 public creatorFeePercent = 5;
    uint256 public founderFeePercent = 2;
    uint256 public constant MIN_TARGET_AMOUNT = 5 ether;
    uint256 public constant MAX_TARGET_AMOUNT = 1000 ether;
    mapping(uint256 => Pool) public pools;
    mapping(address => uint256) public creatorTotalAllocations;
    uint256 public poolCounter;
    mapping(address => uint256) public pendingWithdrawals;

    event PoolCreated(uint256 indexed poolId, address indexed creator, uint256 targetAmount);
    event Deposited(uint256 indexed poolId, address indexed participant, uint256 amount);
    event WinnerSelected(uint256 indexed poolId, address indexed winner, uint256 amount);
    event WithdrawalFailed(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function createPool(uint256 _targetAmount) external payable {
        require(msg.value == poolCreationFee, "Must pay the pool creation fee");
        require(_targetAmount >= MIN_TARGET_AMOUNT && _targetAmount <= MAX_TARGET_AMOUNT, "Invalid target amount");

        founderAllocation += msg.value;
        poolCounter++;
        Pool storage newPool = pools[poolCounter];
        newPool.poolId = poolCounter;
        newPool.creator = msg.sender;
        newPool.targetAmount = _targetAmount;
        newPool.active = true;
        newPool.creatorAllocation = 0;

        emit PoolCreated(poolCounter, msg.sender, _targetAmount);
    }

    function participateInPool(uint256 _poolId) external payable {
        Pool storage pool = pools[_poolId];
        require(pool.active, "Pool is not active");
        require(msg.value > 0, "Must send some crypto to participate");

        (uint256 creatorFee, uint256 founderFee, uint256 amountToPool) = calculateFees(msg.value);

        pool.currentAmount += amountToPool;
        pool.finalCreatorAllocation += creatorFee;
        pool.creatorAllocation += creatorFee;
        creatorTotalAllocations[pool.creator] += creatorFee;
        founderAllocation += founderFee;

        if (!pool.isParticipant[msg.sender]) {
            pool.participants.push(msg.sender);
            pool.isParticipant[msg.sender] = true;
        }
        pool.deposits[msg.sender] += amountToPool;

        if (pool.currentAmount >= pool.targetAmount) {
            pool.active = false;
            address winner = selectWinner(_poolId);
            pool.winner = winner;
            uint256 payoutAmount = pool.currentAmount;

            (bool success,) = payable(winner).call{value: payoutAmount}("");
            if (!success) {
                pendingWithdrawals[winner] += payoutAmount;
                emit WithdrawalFailed(winner, payoutAmount);
            } else {
                emit WinnerSelected(_poolId, winner, payoutAmount);
            }
        }

        emit Deposited(_poolId, msg.sender, msg.value);
    }

    function withdrawCreatorAllocation(uint256 _poolId) external nonReentrant {
        Pool storage pool = pools[_poolId];
        require(msg.sender == pool.creator, "Only creator can withdraw");
        require(!pool.active, "Pool is still active");
        require(pool.creatorAllocation > 0, "No funds to withdraw");

        uint256 amount = pool.creatorAllocation;
        pool.creatorAllocation = 0;
        pool.finalCreatorAllocation = amount;
        creatorTotalAllocations[msg.sender] -= amount;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            pool.creatorAllocation = amount;
            creatorTotalAllocations[msg.sender] += amount;
        }
    }

    function withdrawAllCreatorAllocations() external nonReentrant {
        uint256 totalAllocation = creatorTotalAllocations[msg.sender];
        require(totalAllocation > 0, "No funds to withdraw");

        bool hasInactivePool = false;

        for (uint256 i = 1; i <= poolCounter; i++) {
            Pool storage pool = pools[i];
            if (pool.creator == msg.sender && !pool.active && pool.creatorAllocation > 0) {
                hasInactivePool = true;
                break;
            }
        }

        require(hasInactivePool, "No funds to withdraw");

        creatorTotalAllocations[msg.sender] = 0;

        for (uint256 i = 1; i <= poolCounter; i++) {
            Pool storage pool = pools[i];
            if (pool.creator == msg.sender && !pool.active && pool.creatorAllocation > 0) {
                uint256 amount = pool.creatorAllocation;
                pool.creatorAllocation = 0;

                (bool success,) = payable(msg.sender).call{value: amount}("");
                if (!success) {
                    pool.creatorAllocation = amount;
                }
            }
        }
    }

    function withdrawFounderAllocation() external onlyOwner nonReentrant {
        require(founderAllocation > 0, "No funds to withdraw");

        uint256 amount = founderAllocation;
        founderAllocation = 0;

        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) {
            founderAllocation = amount;
        }
    }

    function withdrawPending() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            pendingWithdrawals[msg.sender] = amount;
        }
    }

    function getActivePools() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            if (pools[i].active) {
                activeCount++;
            }
        }

        uint256[] memory activePools = new uint256[](activeCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            if (pools[i].active) {
                activePools[index] = i;
                index++;
            }
        }

        return activePools;
    }

    function getInactivePools() external view returns (uint256[] memory) {
        uint256 inactiveCount = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            if (!pools[i].active) {
                inactiveCount++;
            }
        }

        uint256[] memory inactivePools = new uint256[](inactiveCount);
        uint256 index = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            if (!pools[i].active) {
                inactivePools[index] = i;
                index++;
            }
        }

        return inactivePools;
    }

    function getPoolDetails(uint256 _poolId)
        external
        view
        returns (
            uint256 poolId,
            address creator,
            uint256 creatorAllocation,
            uint256 targetAmount,
            uint256 currentAmount,
            address winner,
            bool active,
            address[] memory participants,
            uint256 finalCreatorAllocation
        )
    {
        Pool storage pool = pools[_poolId];
        return (
            pool.poolId,
            pool.creator,
            pool.creatorAllocation,
            pool.targetAmount,
            pool.currentAmount,
            pool.winner,
            pool.active,
            pool.participants,
            pool.finalCreatorAllocation
        );
    }

    function getPoolsByCreator(address _creator) external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            if (pools[i].creator == _creator) {
                count++;
            }
        }

        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            if (pools[i].creator == _creator) {
                result[index] = i;
                index++;
            }
        }

        return result;
    }

    function getPoolParticipantsAmount(uint256 _poolId) external view returns (address[] memory, uint256[] memory) {
        Pool storage pool = pools[_poolId];
        uint256 participantCount = pool.participants.length;
        address[] memory participants = new address[](participantCount);
        uint256[] memory amounts = new uint256[](participantCount);

        for (uint256 i = 0; i < participantCount; i++) {
            address participant = pool.participants[i];
            participants[i] = participant;
            amounts[i] = pool.deposits[participant];
        }

        return (participants, amounts);
    }

    function getPoolsParticipatedIn(address participant) external view returns (uint256[] memory) {
        uint256 participatedCount = 0;

        for (uint256 i = 1; i <= poolCounter; i++) {
            if (pools[i].isParticipant[participant]) {
                participatedCount++;
            }
        }

        uint256[] memory participatedPools = new uint256[](participatedCount);
        uint256 index = 0;

        for (uint256 i = 1; i <= poolCounter; i++) {
            if (pools[i].isParticipant[participant]) {
                participatedPools[index] = i;
                index++;
            }
        }

        return participatedPools;
    }

    function getWithdrawableAmount(address creator) external view returns (uint256) {
        uint256 totalWithdrawable = 0;

        for (uint256 i = 1; i <= poolCounter; i++) {
            Pool storage pool = pools[i];
            if (pool.creator == creator && !pool.active && pool.creatorAllocation > 0) {
                totalWithdrawable += pool.creatorAllocation;
            }
        }

        return totalWithdrawable;
    }

    function calculateFees(uint256 _amount) internal pure returns (uint256, uint256, uint256) {
        uint256 creatorFee = (_amount * 5) / 100;
        uint256 founderFee = (_amount * 2) / 100;
        uint256 amountToPool = _amount - creatorFee - founderFee;
        return (creatorFee, founderFee, amountToPool);
    }

    function selectWinner(uint256 _poolId) internal view returns (address) {
        Pool storage pool = pools[_poolId];
        uint256 totalDeposits = pool.currentAmount;

        bytes32 randomHash = keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp, totalDeposits));

        uint256 randomIndex = uint256(randomHash) % totalDeposits;
        uint256 cumulativeSum = 0;

        for (uint256 i = 0; i < pool.participants.length; i++) {
            address participant = pool.participants[i];
            cumulativeSum += pool.deposits[participant];

            if (randomIndex < cumulativeSum) {
                return participant;
            }
        }

        return pool.participants[0];
    }
}
