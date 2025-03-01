//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Openzeppelin helper
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBTXStaking} from "./../interfaces/IBTXStaking.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title BTX Staking
/// @author Beratrax dev
/// @notice Contract for staking BTX to earn rewards and vote for the next reward vault
contract BTXStaking is IBTXStaking {
  using SafeERC20 for IERC20Metadata;

  // Address of the BTX token
  IERC20Metadata public immutable BTXToken;

  // Address of the reward token
  IERC20Metadata public rewardToken;

  // Address of the governance
  address public governance;

  // Precision factor for multiple calculations
  uint256 public constant ONE = 1e18;

  // Accumulated reward per BTX token
  uint256 public accRewardPerBTX;

  // Last update block for rewards
  uint256 public lastUpdateBlock;

  // Total BTX tokens staked
  uint256 public totalBTXStaked;

  // Reward to distribute per block
  uint256 public currentRewardPerBlock;

  // Current end block for the current reward period
  uint256 public periodEndBlock;

  // Last time reward token was updated
  uint256 public lastUpdateRewardToken;

  // auto incremented when new reward period is started / epoch period started
  uint256 public epochId;

  // array of address of vaults/proposal to vote against
  // it's index is the id of proposal/vault
  address[] public proposals;

  // @dev records the status of proposal, whether it's whitelisted or not
  mapping(address => bool) public isProposal;

  // whitelisted vaults/proposals to epochId to votes count
  mapping(address => mapping(uint256 => uint256)) public proposalToVoteCount;

  // Info of each user that stakes BTX tokens
  mapping(address => UserInfo) public userInfo;

  // Info of each user vote for a specific epoch to proposal
  // epochId => userAddress => proposalAddress
  mapping(uint256 => mapping(address => address)) public userVote;

  /**
   * @notice Constructor
   * @param _governance governance address of beratrax staking
   * @param _rewardToken address of the reward token
   * @param _BTXToken address of the BTX token
   */
  constructor(address _governance, address _rewardToken, address _BTXToken) {
    if (_governance == address(0) || _rewardToken == address(0) || _BTXToken == address(0)) revert ZeroAddress();

    governance = _governance;
    rewardToken = IERC20Metadata(_rewardToken);
    BTXToken = IERC20Metadata(_BTXToken);
    emit GovernanceChanged(address(0), _governance);
    emit RewardTokenChanged(address(0), _rewardToken);
  }

  /**
   * @dev Throws if ether is received
   */
  receive() external payable {
    revert EthTransferNotAllowed();
  }

  /**
   * @dev Throws if called by any account other than the governance
   */
  modifier onlyGovernance() {
    if (msg.sender != governance) revert NotGovernance();
    _;
  }

  /**
   * @notice Updates the governance of this contract
   * @param _newGovernance address of the new governance of this contract
   * @dev Only callable by Governance
   */
  function setGovernance(address _newGovernance) external onlyGovernance {
    if (_newGovernance == address(0)) revert ZeroAddress();

    emit GovernanceChanged(governance, _newGovernance);
    governance = _newGovernance;
  }

  /**
   * @notice Updates the reward token.
   * @param _newRewardToken address of the new reward token
   * @dev Only callable by Governance. It also resets reward distribution accounting
   */
  function updateRewardToken(address _newRewardToken) external onlyGovernance {
    if (_newRewardToken == address(rewardToken)) revert SameRewardToken();
    if (_newRewardToken == address(0)) revert ZeroAddress();

    // Resetting reward distribution accounting
    accRewardPerBTX = 0;
    lastUpdateBlock = _lastRewardBlock();

    // Setting reward token update time
    lastUpdateRewardToken = block.timestamp;

    emit RewardTokenChanged(address(rewardToken), _newRewardToken);

    // Updating reward token address
    rewardToken = IERC20Metadata(_newRewardToken);
  }

  /**
   * @notice Updates the reward per block
   * @param _reward total rewards to distribute.
   * @param _rewardDurationInBlocks total number of blocks in which the '_reward' should be distributed
   * @dev Only callable by Governance. Do not use this function to extend or narrow the voting/reward period.
   */
  function updateRewards(uint256 _reward, uint256 _rewardDurationInBlocks, bool _newEpoch) external onlyGovernance {
    if (_rewardDurationInBlocks == 0) revert ZeroInput();

    // Update reward distribution accounting
    _updateRewardPerBTXAndLastBlock();

    // Adjust the current reward per block
    // If reward distribution duration is expired
    if (block.number >= periodEndBlock) {
      if (_reward == 0) revert ZeroInput();

      currentRewardPerBlock = _reward / _rewardDurationInBlocks;
    }
    // Otherwise, reward distribution duration isn't expired
    else {
      currentRewardPerBlock =
        (_reward + ((periodEndBlock - block.number) * currentRewardPerBlock)) /
        _rewardDurationInBlocks;
    }

    lastUpdateBlock = block.number;

    // Setting rewards expiration block
    periodEndBlock = block.number + _rewardDurationInBlocks;
    if (_newEpoch) epochId++;

    emit NewRewardPeriod(_rewardDurationInBlocks, currentRewardPerBlock, _reward, periodEndBlock);
  }

  /**
   * @notice Updates the reward distribution duration end block
   * @param _expireDurationInBlocks number of blocks after which reward distribution should be halted
   * @dev Only callable by Governance, also use to extend or narrow the voting period
   */
  function updateRewardEndBlock(uint256 _expireDurationInBlocks) external onlyGovernance {
    // Update reward distribution accounting
    _updateRewardPerBTXAndLastBlock();
    lastUpdateBlock = block.number;

    // Setting rewards expiration block
    periodEndBlock = block.number + _expireDurationInBlocks;
    emit PeriodEndBlockUpdate(_expireDurationInBlocks, periodEndBlock);
  }

  /**
   * @notice Migrates the funds to another address.
   * @param _newVersion receiver address of the funds
   * @param _tokens list of token addresses
   * @param _amounts list of funds amount
   * @param _isBTXMigrate whether to transfer BTX tokens, if true then transfer BTX tokens,
   * otherwise transfer all tokens except BTX tokens
   * @dev Can not migrate users' stake
   * @dev Only callable by Governance.
   */
  function migrateFunds(
    address _newVersion,
    IERC20Metadata[] calldata _tokens,
    uint256[] calldata _amounts,
    bool _isBTXMigrate
  ) external onlyGovernance {
    if (_newVersion == address(0)) revert ZeroAddress();

    if (_tokens.length != _amounts.length) revert InputLengthMismatch();

    // Declaring outside the loop to save gas
    IERC20Metadata tokenAddress;
    uint256 amount;

    for (uint256 i; i < _tokens.length; ) {
      // Local copy to save gas
      tokenAddress = _tokens[i];
      amount = _amounts[i];

      if (tokenAddress == BTXToken) revert InvalidAsset();

      if (address(tokenAddress) == address(0)) revert ZeroAddress();

      if (amount == 0) revert ZeroInput();

      if (amount > tokenAddress.balanceOf(address(this))) revert InsufficientFunds();

      tokenAddress.safeTransfer(_newVersion, amount);
      unchecked {
        ++i;
      }
    }

    // Migrate BTX tokens
    if (_isBTXMigrate) {
      // BTX token balance of this contract minus staked BTX
      uint256 protocolBTXBalance = BTXToken.balanceOf(address(this)) - totalBTXStaked;

      // If protocol owns any BTX in this contract then transfer
      if (protocolBTXBalance > 0) BTXToken.safeTransfer(_newVersion, protocolBTXBalance);
      else revert InsufficientBTXFunds();
    }
    emit FundsMigrated(_newVersion, _tokens, _amounts);
  }

  /**
   * @notice only the stakers can cast vote and only for the ongoing epoch
   * @param _proposalAddress address of the proposal to cast the vote to
   * @dev only the positive votes are being taken into account, vote only for the desired proposal to win
   */
  function vote(address _proposalAddress) external {
    if (block.number >= periodEndBlock) revert RewardDistributionPeriodHasExpired();

    if (userInfo[msg.sender].amount == 0) revert NoStakeFound();

    if (isProposal[_proposalAddress] == false) revert InvalidProposal();

    if (userVote[epochId][msg.sender] == _proposalAddress) revert AlreadyVoted();

    address oldVoteProposalAddress = userVote[epochId][msg.sender];

    userVote[epochId][msg.sender] = _proposalAddress;
    // if the old vote was not for the current proposal, then decrease the vote count
    if (oldVoteProposalAddress != address(0)) proposalToVoteCount[oldVoteProposalAddress][epochId]--;
    proposalToVoteCount[_proposalAddress][epochId]++;

    emit Vote(_proposalAddress, msg.sender, epochId);
  }

  /**
   * @notice Set the vaults to whitelisted or blacklist to vote
   * @param _proposals array of vaults addresses
   * @param status array of booleans to set the status of vaults, false means omit
   * @dev duplication will occur in proposals array, if whitelisting after had it blacklisted, but it won't hurt the authenticity of the proposals array
   */
  function updateProposals(address[] calldata _proposals, bool[] calldata status) external onlyGovernance {
    if (_proposals.length != status.length) revert InputLengthMismatch();
    // if record found then, update the existing proposal status
    // if not found then add the proposal to the proposals array and update the status in the mapping
    /**
     * edge cases
     * if the proposal is whitelisted then update the status
     * if the proposal is blacklisted then add the proposal with updated status
     * if the there is no record of the proposal then add the proposal with updated status
     * if the address was whitelisted once, then gets blacklisted and now is coming again to be whitelisted, then if will increase the length of proposals array
     */
    for (uint256 i = 0; i < _proposals.length; i++) {
      if (isProposal[_proposals[i]]) {
        isProposal[_proposals[i]] = status[i];
      } else {
        // the workaround to avoid duplication is to find the index of existing proposal, if found then update the status else add the proposal
        // but it's will be a nested loop, so it's not good
        proposals.push(_proposals[i]);
        isProposal[_proposals[i]] = status[i];
      }
    }
  }

  /**
   * @notice Stake BTX tokens. Also triggers a claim.
   * @param _to staking reward receiver address
   * @param _amount amount of BTX tokens to stake
   */
  function stake(address _to, uint256 _amount) external {
    if (_amount == 0) revert ZeroInput();

    if (_to == address(0)) revert ZeroAddress();

    if (currentRewardPerBlock == 0) revert RewardPerBlockIsNotSet();

    if (block.number >= periodEndBlock) revert RewardDistributionPeriodHasExpired();

    if (rewardToken.balanceOf(address(this)) == 0) revert InsufficientFunds();

    _stakeOrUnstakeOrClaim(_to, _amount, TxType.STAKE);
  }

  /**
   * @notice Unstake BTX tokens. Also triggers a reward claim.
   * @param _amount amount of BTX tokens to unstake
   */
  function unstake(uint256 _amount) external {
    if ((_amount > userInfo[msg.sender].amount) || _amount == 0) revert AmountLessThanStakedAmountOrZero();

    _stakeOrUnstakeOrClaim(msg.sender, _amount, TxType.UNSTAKE);
  }

  /**
   * @notice Unstake all staked BTX tokens without caring about rewards, EMERGENCY ONLY
   */
  function emergencyUnstake() external {
    if (userInfo[msg.sender].amount > 0) {
      _stakeOrUnstakeOrClaim(msg.sender, userInfo[msg.sender].amount, TxType.EMERGENCY);
    } else revert NoStakeFound();
  }

  /**
   * @notice Claim pending rewards.
   */
  function claim() external {
    _stakeOrUnstakeOrClaim(msg.sender, userInfo[msg.sender].amount, TxType.CLAIM);
  }

  /**
   * @notice Calculate pending rewards for a user
   * @param _user address of the user
   * @return pending rewards of the user
   */
  function calculatePendingRewards(address _user) external view returns (uint256) {
    uint256 newAccRewardPerBTX;

    if (totalBTXStaked != 0) {
      newAccRewardPerBTX =
        accRewardPerBTX +
        (((_lastRewardBlock() - lastUpdateBlock) * (currentRewardPerBlock * ONE)) / totalBTXStaked);
      // If checking user pending rewards in the block in which reward token is updated
      if (newAccRewardPerBTX == 0) return 0;
    } else return 0;

    uint256 rewardDebt = userInfo[_user].rewardDebt;

    // Reset debt if user is checking rewards after reward token has changed
    if (userInfo[_user].lastUpdateRewardToken < lastUpdateRewardToken) rewardDebt = 0;

    uint256 pendingRewards = ((userInfo[_user].amount * newAccRewardPerBTX) / ONE) - rewardDebt;

    // Downscale if reward token has less than 18 decimals
    if (_computeScalingFactor(rewardToken) != 1) {
      // Downscaling pending rewards before transferring to the user
      pendingRewards = _downscale(pendingRewards);
    }
    return pendingRewards;
  }

  /**
   * @notice Return last block where trading rewards were distributed
   */
  function lastRewardBlock() external view returns (uint256) {
    return _lastRewardBlock();
  }

  /**
   * @notice Return the vaults/propsals whitelisted to vote
   * @param _all return all vaults/proposals or only the whitelisted ones
   */
  function getProposals(bool _all) external view returns (address[] memory) {
    // early return if all are requested, remove duplication on the returned end
    if (_all) return proposals;
    else {
      uint256 count = 0;
      // count the whitelisted only
      for (uint256 i = 0; i < proposals.length; i++) {
        if (isProposal[proposals[i]]) count++;
      }
      // prepare the array of whitelisted ones
      address[] memory _proposals = new address[](count);
      uint256 index;
      for (uint256 j = 0; j < proposals.length; j++) {
        if (isProposal[proposals[j]]) {
          _proposals[index] = proposals[j];
          index++;
        }
      }
      return _proposals;
    }
  }

  /**
   * @notice Stake/ Unstake BTX tokens and also distributes reward
   * @param _to staking reward receiver address
   * @param _amount amount of BTX tokens to stake or unstake. 0 if claim tx.
   * @param _txType type of the transaction
   */
  function _stakeOrUnstakeOrClaim(address _to, uint256 _amount, TxType _txType) private {
    // Update reward distribution accounting
    _updateRewardPerBTXAndLastBlock();

    // Reset debt if reward token has changed
    _resetDebtIfNewRewardToken(_to);

    UserInfo storage user = userInfo[_to];

    uint256 pendingRewards;

    // Distribute rewards if not emergency unstake
    if (TxType.EMERGENCY != _txType) {
      // Distribute rewards if not new stake
      if (user.amount > 0) {
        // Calculate pending rewards
        pendingRewards = _calculatePendingRewards(_to);

        // Downscale if reward token has less than 18 decimals
        if (_computeScalingFactor(rewardToken) != 1) {
          // Downscaling pending rewards before transferring to the user
          pendingRewards = _downscale(pendingRewards);
        }

        // If there are rewards to distribute
        if (pendingRewards > 0) {
          if (pendingRewards > rewardToken.balanceOf(address(this))) revert InsufficientFunds();

          // Transferring rewards to the user
          rewardToken.safeTransfer(_to, pendingRewards);
        }
        // If there are no pending rewards and tx is of claim then revert
        else if (TxType.CLAIM == _txType) revert NoPendingRewardsToClaim();
      }
      // Claiming rewards without any stake
      else if (TxType.CLAIM == _txType) revert NoPendingRewardsToClaim();
    }

    if (TxType.STAKE == _txType) {
      // Transfer BTX tokens from the caller to this contract
      BTXToken.safeTransferFrom(msg.sender, address(this), _amount);

      // Increase user BTX staked amount
      user.amount += _amount;

      // Increase total BTX staked amount
      totalBTXStaked += _amount;
    } else if (TxType.UNSTAKE == _txType || TxType.EMERGENCY == _txType) {
      // Decrease user BTX staked amount
      user.amount -= _amount;

      // Decrease total BTX staked amount
      totalBTXStaked -= _amount;

      // Transfer BTX tokens back to the sender
      BTXToken.safeTransfer(_to, _amount);
    }

    // Adjust user debt
    user.rewardDebt = (user.amount * accRewardPerBTX) / ONE;

    emit StakeOrUnstakeOrClaim(_to, _amount, pendingRewards, _txType);
  }

  /**
   * @notice Resets user reward debt if reward token has changed
   * @param _to reward debt reset address
   */
  function _resetDebtIfNewRewardToken(address _to) private {
    // Reset debt if user last update reward token time is less than the time of last reward token update
    if (userInfo[_to].lastUpdateRewardToken < lastUpdateRewardToken) {
      userInfo[_to].rewardDebt = 0;
      userInfo[_to].lastUpdateRewardToken = lastUpdateRewardToken;
    }
  }

  /**
   * @notice Updates accumulated reward to distribute per BTX token. Also updates the last block in which rewards are distributed
   */
  function _updateRewardPerBTXAndLastBlock() private {
    if (totalBTXStaked == 0) {
      lastUpdateBlock = block.number;
      return;
    }

    accRewardPerBTX += ((_lastRewardBlock() - lastUpdateBlock) * (currentRewardPerBlock * ONE)) / totalBTXStaked;

    if (block.number != lastUpdateBlock) lastUpdateBlock = _lastRewardBlock();
  }

  /**
   * @notice Calculate pending rewards for a user
   * @param _user address of the user
   */
  function _calculatePendingRewards(address _user) private view returns (uint256) {
    return ((userInfo[_user].amount * accRewardPerBTX) / ONE) - userInfo[_user].rewardDebt;
  }

  /**
   * @notice Return last block where rewards must be distributed
   */
  function _lastRewardBlock() private view returns (uint256) {
    return block.number < periodEndBlock ? block.number : periodEndBlock;
  }

  /**
   * @notice Returns a scaling factor that, when multiplied to a token amount for `token`, normalizes its balance as if
   * it had 18 decimals.
   */
  function _computeScalingFactor(IERC20Metadata _token) private view returns (uint256) {
    // Tokens that don't implement the `decimals` method are not supported.
    uint256 tokenDecimals = _token.decimals();

    // Tokens with more than 18 decimals are not supported.
    uint256 decimalsDifference = 18 - tokenDecimals;
    return 10 ** decimalsDifference;
  }

  /**
   * @notice Reverses the upscaling applied to `amount`, resulting in a smaller or equal value depending on
   * whether it needed scaling or not
   */
  function _downscale(uint256 _amount) private view returns (uint256) {
    return _amount / _computeScalingFactor(rewardToken);
  }
}
