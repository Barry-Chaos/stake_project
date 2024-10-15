// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RCCStake is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    // 常量
    bytes32 private constant ADMIN_ROLE = keccak256("admin_role");
    bytes32 private constant UPGRADE_ROLE = keccak256("upgrade_role");
    uint256 private constant NATIVE_CURRENCY_PID = 0;

    // 结构体
    struct Pool {
        address stakeTokenAddress;
        uint256 poolWeight;
        uint256 stakeTokenAmount;
        uint256 minDepositAmount;
        uint256 lockBlocks;

        uint256 accRewardPerStakeToken;
        uint256 lastRewardBlock;
    }

    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockBlock;
    }

    struct User {
        uint256 stakeTokenAmount;
        uint256 pendingReward;
        uint256 finishedReward;
        UnstakeRequest[] requests;
    }

    // 事件
    event AddPool(address indexed stakeTokenAddress, uint256 indexed poolWeight, uint256 indexed lastRewardBlock, uint256 minDepositAmount, uint256 lockBlocks);
    event Deposit(uint256 indexed poolId, address indexed user, uint256 amount, uint256 indexed blcokNumber);
    event Unstake(uint256 indexed poolId, address indexed user, uint256 amount, uint256 indexed blcokNumber);
    event Withdraw(uint256 indexed poolId, address indexed user, uint256 amount, uint256 indexed blockNumber);
    event Claim(uint256 indexed poolId, address indexed user, uint256 reward);

    // 状态变量
    uint256 private totalWeight;
    uint256 private startBlock;
    uint256 private endBlock;
    uint256 private rewardPerBlock;
    IERC20 rewardToken;
    
    Pool[] pools;
    mapping(uint256 => mapping(address => User)) users;
    
    bool withdrawPaused;
    bool claimPaused;

    // --------------------------------------------初始化函数--------------------------------------------
    function initialize(address rewardToken_, uint256 startBlock_, uint256 endBlock_, uint256 rewardPerBlock_) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
         __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        require(startBlock_ < endBlock_ && rewardPerBlock_ > 0, "invalid paramters");

        rewardToken = IERC20(rewardToken_);
        startBlock = startBlock_;
        endBlock = endBlock_;
        rewardPerBlock = rewardPerBlock_;
    }
    // uups升级 身份验证
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADE_ROLE) {}

    // --------------------------------------------修饰器--------------------------------------------
    modifier checkPid(uint256 _pid) {
        require(_pid < pools.length, "invalid pid");
        _;
    }
    modifier whenNotClaimPaused() {
        require(!claimPaused, "claim is paused");
        _;
    }
    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "withdraw is paused");
        _;
    }

    // --------------------------------------------管理员函数--------------------------------------------
    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "withdraw is already paused");

        withdrawPaused = true;
    }
    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "withdraw is already unpaused");

        withdrawPaused = false;
    }
    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "claim is already paused");

        claimPaused = true;
    }
    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "claim is already unpaused");

        claimPaused = false;
    }

    // 添加质押池
    function addPool(
        address stakeTokenAddress_, 
        uint256 poolWeight_, 
        uint256 minDepositAmount_, 
        uint256 lockBlocks_
    ) public onlyRole(ADMIN_ROLE) returns(uint256 poolId) {
        // 参数校验
        if (pools.length == 0) { // 第一个池 质押的是以太币
            require(stakeTokenAddress_ == address(0x0), "invalid stakeTokenAddress_");
        } else { // 其他的池 质押的是合约代币
            require(stakeTokenAddress_ != address(0x0), "invalid stakeTokenAddress_");
        }
        require(poolWeight_ > 0, "invalid poolWeight_");
        require(minDepositAmount_ > 0, "invalid minDepositAmount_");
        require(lockBlocks_ > 0, "invalid lockBlocks_");
        require(block.number < endBlock, "already end");

        // 添加新池
        uint256 lastRewardBlock = block.number < startBlock ? startBlock : block.number;
        pools.push(Pool({
            stakeTokenAddress: stakeTokenAddress_,
            poolWeight: poolWeight_,
            stakeTokenAmount: 0,
            minDepositAmount: minDepositAmount_,
            lockBlocks: lockBlocks_,
            accRewardPerStakeToken: 0,
            lastRewardBlock:lastRewardBlock
        }));
        poolId = pools.length - 1;

        // 更新总权重
        totalWeight += poolWeight_;

        // emit 事件
    }

    // --------------------------------------------用户函数--------------------------------------------
    // 用户质押以太币
    function depositNative() public payable {
        // 参数校验
        require(block.number > endBlock, "already end");

        uint256 amount = msg.value;
        Pool storage pool = pools[NATIVE_CURRENCY_PID];
        require(amount >= pool.minDepositAmount, "deposit amount is too small");

        // 更新质押池的奖励信息
        updatePool(NATIVE_CURRENCY_PID);

        // 更新用户奖励
        User storage user = users[NATIVE_CURRENCY_PID][msg.sender];
        uint256 userStakeTokenAmount = user.stakeTokenAmount;
        if (userStakeTokenAmount > 0) {
            uint256 pendingReward = pool.accRewardPerStakeToken * userStakeTokenAmount - user.finishedReward;
            user.pendingReward += pendingReward;
        }

        // 更新质押数
        user.stakeTokenAmount += amount;
        pool.stakeTokenAmount += amount;

        // 更新用户下一次奖励时所要扣除的奖励
        user.finishedReward = pool.accRewardPerStakeToken * user.stakeTokenAmount;

        // emit 事件
    }
    
    // 用户质押合约代币
    function deposit(uint256 poolId, uint256 amount) public checkPid(poolId) {
        // 参数校验
        require(poolId > 0, "poolId not supported");
        require(block.number > endBlock, "already end");

        Pool storage pool = pools[poolId];
        require(amount >= pool.minDepositAmount, "deposit amount is too small");

        // 代币转移
        IERC20(pool.stakeTokenAddress).transferFrom(msg.sender, address(this), amount);

        // 更新质押池的奖励信息
        updatePool(poolId);

        // 更新用户奖励
        User storage user = users[poolId][msg.sender];
        uint256 userStakeTokenAmount = user.stakeTokenAmount;
        if (userStakeTokenAmount > 0) {
            uint256 pendingReward = pool.accRewardPerStakeToken * userStakeTokenAmount - user.finishedReward;
            user.pendingReward += pendingReward;
        }

        // 更新质押数
        user.stakeTokenAmount += amount;
        pool.stakeTokenAmount += amount;

        // 更新用户下一次奖励时所要扣除的奖励
        user.finishedReward = pool.accRewardPerStakeToken * user.stakeTokenAmount;

        // emit 事件
    }

    // 用户解除质押
    function unstake(uint256 poolId, uint256 amount) public checkPid(poolId) {
        // 参数校验
        require(amount > 0, "invalid amount");

        User storage user = users[poolId][msg.sender];
        uint256 userStakeTokenAmount = user.stakeTokenAmount;
        require(amount <= userStakeTokenAmount, "not enough staking token balance");

        // 更新质押池的奖励
        updatePool(poolId);

        // 更新用户的奖励
        Pool storage pool = pools[poolId];
        if (userStakeTokenAmount > 0) {
            uint256 pendingReward = pool.accRewardPerStakeToken * userStakeTokenAmount - user.finishedReward;
            user.pendingReward += pendingReward;
        }

        // 更新质押数
        user.stakeTokenAmount -= amount;
        pool.stakeTokenAmount -= amount;
        user.requests.push(UnstakeRequest({
            amount: amount,
            unlockBlock: block.number + pool.lockBlocks
        }));

        // 计算用户下一次奖励所要扣减的奖励
        user.finishedReward = pool.accRewardPerStakeToken * user.stakeTokenAmount;

        // emit 事件
    }

    // 用户取回质押
    function withdraw(uint256 poolId) public checkPid(poolId) {
        // 统计已解锁的质押
        User storage user = users[poolId][msg.sender];
        UnstakeRequest[] storage requests = user.requests;
        uint256 withdrawReward;
        uint256 num;
        for (uint i = 0; i < requests.length; i++) {
            UnstakeRequest storage request = requests[i];
            if (request.unlockBlock > block.number) {
                break;
            }
            withdrawReward += request.amount;
            num++;
        }
        require(withdrawReward > 0, "no staking token to withdraw");

        // 清理解押请求
        for (uint i = 0; i < requests.length - num; i++) {
            requests[i] = requests[i + num];
        }
        for (uint i = 0; i < num; i++) {
            requests.pop();
        }

        // 转移代币
        Pool storage pool = pools[poolId];
        address stakeTokenAddress = pool.stakeTokenAddress;
        if (stakeTokenAddress == address(0x0)) {
            payable(msg.sender).transfer(withdrawReward);
        } else {
            IERC20(stakeTokenAddress).transferFrom(address(this), msg.sender, withdrawReward);
        }

        // emit 事件
    }

    // 用户领取奖励
    function claim(uint256 poolId) public checkPid(poolId) {
        // 更新质押池的奖励
        updatePool(poolId);

        // 统计用户的奖励
        Pool storage pool = pools[poolId];
        User storage user = users[poolId][msg.sender];
        uint256 pendingReward = pool.accRewardPerStakeToken * user.stakeTokenAmount - user.finishedReward + user.pendingReward;
        require(pendingReward > 0, "no pending reward");

        // 发放奖励
        rewardToken.transfer(msg.sender, pendingReward);

        // 奖励清空，并更新用户下一次奖励所需扣减的奖励
        user.pendingReward = 0;
        user.finishedReward = pool.accRewardPerStakeToken * user.stakeTokenAmount;

        // emit 事件
    }

    // --------------------------------------------内部函数--------------------------------------------
    // 更新质押池的奖励信息
    function updatePool(uint256 poolId) internal checkPid(poolId) {
        // 参数校验
        require(block.number > endBlock, "already end");

        Pool storage pool = pools[poolId];
        uint256 lastRewardBlock = pool.lastRewardBlock;
        if (block.number <= lastRewardBlock) {
            return;
        }

        // 更新奖励信息
        uint256 stakeTokenAmount = pool.stakeTokenAmount;
        if(stakeTokenAmount > 0) {
            // 计算本周期内 每个质押代币的奖励
            uint256 poolWeight = pool.poolWeight;
            uint256 rewardForPool = (block.number - lastRewardBlock) * rewardPerBlock * poolWeight / totalWeight;
            uint256 rewardPerStakeToken = rewardForPool / pool.stakeTokenAmount;
            pool.accRewardPerStakeToken += rewardPerStakeToken;
        }
        pool.lastRewardBlock = block.number;

        // emit 事件
    }
}