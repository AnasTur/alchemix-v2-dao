// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "src/interfaces/IBribe.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IVoter.sol";
import "src/interfaces/IVotingEscrow.sol";
import "src/BaseGauge.sol";

contract PassthroughGauge is BaseGauge {
    event Deposit(address indexed from, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed from, uint256 tokenId, uint256 amount);
    event Passthrough(address indexed from, address token, uint256 amount, address receiver);

    address public _token;

    constructor(
        address _receiver,
        address _bribe,
        address _ve,
        address _voter
    ) {
        bribe = _bribe;
        ve = _ve;
        voter = _voter;
        receiver = _receiver;

        admin = msg.sender;

        IBribe(bribe).setGauge(address(this));
        _token = IVotingEscrow(ve).ALCX();
        IBribe(bribe).addRewardToken(_token);
        isReward[_token] = true;
        rewards.push(_token);
    }

    function setAdmin(address _admin) external {
        require(msg.sender == admin, "not admin");
        admin = _admin;
    }

    function updateReceiver(address _receiver) external {
        require(msg.sender == admin, "not admin");
        receiver = _receiver;
    }

    function passthroughRewards(uint256 _amount) public lock {
        require(_amount > 0, "insufficient amount");

        uint256 rewardBalance = IERC20(_token).balanceOf(address(this));
        require(rewardBalance >= _amount, "insufficient rewards");

        _updateRewardForAllTokens();

        _safeTransfer(_token, receiver, _amount);

        emit Passthrough(msg.sender, _token, _amount, receiver);
    }

    function notifyRewardAmount(address token, uint256 _amount) external override lock {
        require(_amount > 0, "insufficient amount");
        if (!isReward[token]) {
            require(rewards.length < MAX_REWARD_TOKENS, "too many rewards tokens");
        }
        // rewards accrue only during the bribe period
        uint256 bribeStart = block.timestamp - (block.timestamp % (7 days)) + BRIBE_LAG;
        uint256 adjustedTstamp = block.timestamp < bribeStart ? bribeStart : bribeStart + 7 days;
        if (rewardRate[token] == 0) _writeRewardPerTokenCheckpoint(token, 0, adjustedTstamp);
        (rewardPerTokenStored[token], lastUpdateTime[token]) = _updateRewardPerToken(token);

        if (block.timestamp >= periodFinish[token]) {
            _safeTransferFrom(token, msg.sender, address(this), _amount);
            rewardRate[token] = _amount / DURATION;
        } else {
            uint256 _remaining = periodFinish[token] - block.timestamp;
            uint256 _left = _remaining * rewardRate[token];
            require(_amount > _left);
            _safeTransferFrom(token, msg.sender, address(this), _amount);
            rewardRate[token] = (_amount + _left) / DURATION;
        }
        require(rewardRate[token] > 0);
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(rewardRate[token] <= balance / DURATION, "Provided reward too high");
        periodFinish[token] = adjustedTstamp + DURATION;
        if (!isReward[token]) {
            isReward[token] = true;
            rewards.push(token);
            IBribe(bribe).addRewardToken(token);
        }

        emit NotifyReward(msg.sender, token, _amount);
    }
}
