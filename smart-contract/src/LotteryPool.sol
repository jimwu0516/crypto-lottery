// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract LotteryPool {
    struct Pool {
        address creator;
        uint256 creatorAllocation;
        uint256 targetAmount;
        uint256 currentAmount;
        address winner;
        bool active;
        address[] participants;
        mapping(address => uint256) deposits;
        mapping(address => bool) isParticipant;
    }

    address public owner;
    uint256 public founderAllocation;
    uint256 public poolCreationFee = 0.1 ether;
    uint256 public participantFeePercent = 7;
    uint256 public creatorFeePercent = 2;
    uint256 public founderFeePercent = 5;
    mapping(uint256 => Pool) public pools;
    mapping(address => uint256) public creatorTotalAllocations;
    uint256 public poolCounter;
    uint256 public constant MIN_TARGET_AMOUNT = 5 ether;
    uint256 public constant MAX_TARGET_AMOUNT = 1000 ether;
    mapping(address => uint256) public pendingWithdrawals;

    event PoolCreated(
        uint256 indexed poolId,
        address indexed creator,
        uint256 targetAmount
    );
    event Deposited(
        uint256 indexed poolId,
        address indexed participant,
        uint256 amount
    );
    event WinnerSelected(
        uint256 indexed poolId,
        address indexed winner,
        uint256 amount
    );
    event WithdrawalFailed(address indexed to, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    function createPool(uint256 _targetAmount) external payable {
        require(msg.value == poolCreationFee, "Must pay the pool creation fee");
        require(
            _targetAmount >= MIN_TARGET_AMOUNT,
            "Target amount must be at least 5 ether"
        );
        require(
            _targetAmount <= MAX_TARGET_AMOUNT,
            "Target amount must be less than 1000 ether"
        );

        founderAllocation += msg.value;
        poolCounter++;
        Pool storage newPool = pools[poolCounter];
        newPool.creator = msg.sender;
        newPool.targetAmount = _targetAmount;
        newPool.active = true;

        emit PoolCreated(poolCounter, msg.sender, _targetAmount);
    }

    function participateInPool(uint256 _poolId) external payable {
        Pool storage pool = pools[_poolId];
        require(pool.active, "Pool is not active");
        require(msg.value > 0, "Must send some crypto to participate");

        uint256 fee = (msg.value * participantFeePercent) / 1000;
        uint256 creatorFee = (fee * creatorFeePercent) / participantFeePercent;
        uint256 founderFee = fee - creatorFee;
        uint256 amountToPool = msg.value - fee;

        pool.currentAmount += amountToPool;
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

            (bool success, ) = payable(winner).call{value: payoutAmount}("");
            if (!success) {
                pendingWithdrawals[winner] += payoutAmount;
                emit WithdrawalFailed(winner, payoutAmount);
            } else {
                emit WinnerSelected(_poolId, winner, payoutAmount);
            }
        }

        emit Deposited(_poolId, msg.sender, msg.value);
    }

    function selectWinner(uint256 _poolId) internal view returns (address) {
        Pool storage pool = pools[_poolId];
        uint256 totalDeposits = pool.currentAmount;
        uint256 randomHash = uint256(blockhash(block.number - 1));
        uint256 cumulativeSum = 0;

        for (uint256 i = 0; i < pool.participants.length; i++) {
            address participant = pool.participants[i];
            cumulativeSum += pool.deposits[participant];

            if (randomHash % totalDeposits < cumulativeSum) {
                return participant;
            }
        }

        return pool.participants[0];
    }

    function withdrawCreatorAllocation(uint256 _poolId) external {
        Pool storage pool = pools[_poolId];
        require(msg.sender == pool.creator, "Only creator can withdraw");
        require(pool.creatorAllocation > 0, "No funds to withdraw");

        uint256 amount = pool.creatorAllocation;
        pool.creatorAllocation = 0;
        creatorTotalAllocations[msg.sender] -= amount;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            pool.creatorAllocation = amount;
            creatorTotalAllocations[msg.sender] += amount;
        }
    }

    function withdrawAllCreatorAllocations() external {
        uint256 totalAllocation = creatorTotalAllocations[msg.sender];
        require(totalAllocation > 0, "No funds to withdraw");

        creatorTotalAllocations[msg.sender] = 0;
        for (uint256 i = 1; i <= poolCounter; i++) {
            Pool storage pool = pools[i];
            if (pool.creator == msg.sender && pool.creatorAllocation > 0) {
                uint256 amount = pool.creatorAllocation;
                pool.creatorAllocation = 0;

                (bool success, ) = payable(msg.sender).call{value: amount}("");
                if (!success) {
                    pool.creatorAllocation = amount;
                }
            }
        }
    }

    function withdrawFounderAllocation() external onlyOwner {
        require(founderAllocation > 0, "No funds to withdraw");

        uint256 amount = founderAllocation;
        founderAllocation = 0;

        (bool success, ) = payable(owner).call{value: amount}("");
        if (!success) {
            founderAllocation = amount;
        }
    }

    function withdrawPending() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            pendingWithdrawals[msg.sender] = amount;
        }
    }
}
