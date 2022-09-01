// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.15;

import "./libraries/Math.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IVotingEscrow.sol";
import "./interfaces/IAlchemixToken.sol";

struct InitializationParams {
    address voter; // the voting & distribution system
    address ve; // the ve(3,3) system that will be locked into
    address rewardsDistributor; // the distribution system that ensures users aren't diluted
    uint256 supply; // current emissions supply
    uint256 rewards; // current amount of emissions
    uint256 stepdown; // rate rewards decreases by
}

contract Minter is IMinter {
    // Allows minting once per epoch (epoch = 1 week, reset every Thursday 00:00 UTC)
    uint256 internal constant WEEK = 86400 * 7;

    // Tail emissions rate
    uint256 public constant TAIL_EMISSIONS_RATE = 2194e18;

    IAlchemixToken public alcx = IAlchemixToken(0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF);
    IVoter public immutable voter;
    IVotingEscrow public immutable ve;
    IRewardsDistributor public immutable rewardsDistributor;

    uint256 public epochEmissions;

    uint256 public activePeriod;

    address internal initializer;
    address public admin;
    address public pendingAdmin;

    uint256 public stepdown;
    uint256 public rewards;
    uint256 public supply;

    event Mint(address indexed sender, uint256 epoch, uint256 circulatingSupply, uint256 circulatingEmissions);

    constructor(InitializationParams memory params) {
        stepdown = params.stepdown;
        rewards = params.rewards;
        supply = params.supply;
        initializer = msg.sender;
        admin = msg.sender;
        voter = IVoter(params.voter);
        ve = IVotingEscrow(params.ve);
        rewardsDistributor = IRewardsDistributor(params.rewardsDistributor);
        activePeriod = ((block.timestamp + WEEK) / WEEK) * WEEK;
    }

    // Remove if contract is not upgradeable
    // Claimants and amounts can be added as params if
    // the minter is initialized with address that should have veALCX
    function initialize() external {
        require(initializer == msg.sender);
        initializer = address(0);
    }

    function setAdmin(address _admin) external {
        require(msg.sender == admin, "not admin");
        pendingAdmin = _admin;
    }

    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "not pending admin");
        admin = pendingAdmin;
    }

    // Circulating supply is total token supply - locked supply
    function circulatingAlcxSupply() public view returns (uint256) {
        return alcx.totalSupply() - ve.totalSupply();
    }

    // Amount of emission for the current epoch
    function epochEmission() public view returns (uint256) {
        return rewards - stepdown;
    }

    function circulatingEmissionsSupply() public view returns (uint256) {
        return supply;
    }

    // TODO determine how to handle distribution of newly minted alcx
    // Calculate inflation and adjust ve balances accordingly
    function calculateGrowth(uint256 _minted) public view returns (uint256) {
        uint256 veTotal = ve.totalSupply();
        uint256 alcxTotal = alcx.totalSupply();
        return (((((_minted * veTotal) / alcxTotal) * veTotal) / alcxTotal) * veTotal) / alcxTotal / 2;
    }

    // Update period can only be called once per epoch (1 week)
    function updatePeriod() external returns (uint256) {
        uint256 period = activePeriod;

        if (block.timestamp >= period + WEEK && initializer == address(0)) {
            // Only trigger if new epoch
            period = (block.timestamp / WEEK) * WEEK;
            activePeriod = period;
            epochEmissions = epochEmission();

            uint256 growth = calculateGrowth(epochEmissions);
            uint256 required = growth + epochEmissions;
            uint256 balanceOf = alcx.balanceOf(address(this));

            if (balanceOf < required) {
                alcx.mint(address(this), required - balanceOf);
            }

            // Set rewards for next epoch
            rewards -= stepdown;

            // Adjust updated emissions total
            supply += rewards;

            // Once we reach the emissions tail stepdown is 0
            if (rewards <= TAIL_EMISSIONS_RATE) {
                stepdown = 0;
            }

            // Logic to distrubte minted tokens
            alcx.approve(address(rewardsDistributor), growth);
            require(alcx.transfer(address(rewardsDistributor), growth));
            rewardsDistributor.checkpointToken(); // Checkpoint token balance that was just minted in rewards distributor
            rewardsDistributor.checkpointTotalSupply(); // Checkpoint supply

            alcx.approve(address(voter), epochEmissions);
            voter.notifyRewardAmount(epochEmissions);

            emit Mint(msg.sender, epochEmissions, circulatingAlcxSupply(), circulatingEmissionsSupply());
        }
        return period;
    }
}
