// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/LotteryPool.sol";

contract DeployLotteryPool is Script {
    function run() external {
        vm.startBroadcast();

        LotteryPool lotteryPool = new LotteryPool();

        vm.stopBroadcast();
    }
}
