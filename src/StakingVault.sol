// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStakingVault} from "./interfaces/IStakingVault.sol";
import {CoreWriterLibrary} from "./libraries/CoreWriterLibrary.sol";
import {L1ReadLibrary} from "./libraries/L1ReadLibrary.sol";
import {Base} from "./Base.sol";
import {Converters} from "./libraries/Converters.sol";

contract StakingVault is IStakingVault, Base {
    using Converters for *;

    address public immutable HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    /// @dev The HYPE token ID; differs between mainnet (150) and testnet (1105) (see https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/asset-ids)
    uint64 public immutable HYPE_TOKEN_ID;

    /// @dev The last block number when HyperCore spot balance was updated
    /// @dev Used to enforce a one-block delay between spot balance changes, and actions that require
    ///      the spot balance to be up-to-date
    uint256 public lastSpotBalanceChangeBlockNumber;

    /// @dev The last block number when HYPE was delegated or undelegated to a validator
    /// @dev This is used to enforce a minimum one-block delay between delegating/undelegating to a
    ///      validator, and reading the delegation state for the validator from the L1Read precompiles
    mapping(address => uint256) public lastDelegationChangeBlockNumber;

    /// @dev The validators that are whitelisted to be delegated to
    mapping(address => bool) public whitelistedValidators;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(uint64 hypeTokenId) {
        _disableInitializers();

        HYPE_TOKEN_ID = hypeTokenId;
    }

    function initialize(address _roleRegistry, address[] memory _whitelistedValidators) public initializer {
        __Base_init(_roleRegistry);
        for (uint256 i = 0; i < _whitelistedValidators.length; i++) {
            whitelistedValidators[_whitelistedValidators[i]] = true;
        }
    }

    /// @inheritdoc IStakingVault
    function deposit() external payable onlyManager whenNotPaused {
        require(msg.value > 0, ZeroAmount());
        emit Deposit(msg.sender, msg.value);
    }

    /// @inheritdoc IStakingVault
    function stake(address validator, uint64 weiAmount) external onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());
        require(whitelistedValidators[validator], ValidatorNotWhitelisted(validator));
        CoreWriterLibrary.stakingDeposit(weiAmount);
        _delegate(validator, weiAmount);

        lastSpotBalanceChangeBlockNumber = block.number;
    }

    /// @inheritdoc IStakingVault
    function unstake(address validator, uint64 weiAmount) external onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());
        require(whitelistedValidators[validator], ValidatorNotWhitelisted(validator));
        _undelegate(validator, weiAmount);
        CoreWriterLibrary.stakingWithdraw(weiAmount);
    }

    /// @inheritdoc IStakingVault
    function tokenRedelegate(address fromValidator, address toValidator, uint64 weiAmount)
        external
        onlyManager
        whenNotPaused
    {
        require(weiAmount > 0, ZeroAmount());
        require(fromValidator != toValidator, RedelegateToSameValidator());
        require(whitelistedValidators[fromValidator], ValidatorNotWhitelisted(fromValidator));
        require(whitelistedValidators[toValidator], ValidatorNotWhitelisted(toValidator));
        _undelegate(fromValidator, weiAmount); // Will revert if the stake is locked, or if the validator does not have enough HYPE to undelegate
        _delegate(toValidator, weiAmount);
    }

    /// @inheritdoc IStakingVault
    function spotSend(address destination, uint64 token, uint64 weiAmount) external onlyManager whenNotPaused {
        require(weiAmount > 0, ZeroAmount());

        // Note: If the destination account doesn't exist on HyperCore, the spotSend will silently fail
        // and the HYPE will not actually be sent. We check the account exists before making the call,
        // so users don't lose their HYPE if their HyperCore account doesn't exist.
        L1ReadLibrary.CoreUserExists memory coreUserExists = L1ReadLibrary.coreUserExists(destination);
        require(coreUserExists.exists, CoreUserDoesNotExist(destination));

        // Note: We don't expect to run into this case, but we're adding this check for safety. The spotSend call will
        // silently fail if the vault doesn't have enough HYPE, so we check the balance before making the call.
        uint256 _spotBalance = spotBalance(HYPE_TOKEN_ID).total;
        require(_spotBalance >= weiAmount, InsufficientHYPEBalance());

        CoreWriterLibrary.spotSend(destination, token, weiAmount);

        lastSpotBalanceChangeBlockNumber = block.number;
    }

    /// @inheritdoc IStakingVault
    function transferHypeToCore(uint256 amount) external onlyManager whenNotPaused {
        require(amount > 0, ZeroAmount());

        // This is an important safety check - ensures that the StakingVault account is activated on HyperCore.
        // If the StakingVault is not activated on HyperCore, and a HyperEVM -> HyperCore HYPE transfer is made,
        // the transferred HYPE will be lost.
        L1ReadLibrary.CoreUserExists memory coreUserExists = L1ReadLibrary.coreUserExists(address(this));
        require(coreUserExists.exists, CoreUserDoesNotExist(address(this)));

        _transfer(payable(HYPE_SYSTEM_ADDRESS), amount);

        lastSpotBalanceChangeBlockNumber = block.number;
    }

    /// @inheritdoc IStakingVault
    function addApiWallet(address apiWalletAddress, string calldata name) external onlyOperator whenNotPaused {
        CoreWriterLibrary.addApiWallet(apiWalletAddress, name);
    }

    /// @inheritdoc IStakingVault
    function delegation(address validator) external view returns (bool, L1ReadLibrary.Delegation memory) {
        return _getDelegation(validator);
    }

    /// @inheritdoc IStakingVault
    function delegatorSummary() external view returns (L1ReadLibrary.DelegatorSummary memory) {
        return L1ReadLibrary.delegatorSummary(address(this));
    }

    /// @inheritdoc IStakingVault
    function spotBalance(uint64 tokenId) public view returns (L1ReadLibrary.SpotBalance memory) {
        // IMPORTANT: We enforce a one-block delay for reading the spot balance after any spot
        // balance changes. After an action occurs that changes the spot balance, the L1Read
        // precompile will no longer return an up-to-date balance.
        require(block.number > lastSpotBalanceChangeBlockNumber, CannotReadSpotBalanceUntilNextBlock());
        return L1ReadLibrary.spotBalance(address(this), tokenId);
    }

    /// @inheritdoc IStakingVault
    function evmBalance() external view returns (uint256) {
        return address(this).balance.stripUnsafePrecision();
    }

    /// @inheritdoc IStakingVault
    function addValidator(address validator) external onlyOperator whenNotPaused {
        whitelistedValidators[validator] = true;
    }

    /// @inheritdoc IStakingVault
    function removeValidator(address validator) external onlyOperator whenNotPaused {
        delete whitelistedValidators[validator];
    }

    /// @notice Delegates to the validator, and checkpoints this block number as the last delegation change
    function _delegate(address validator, uint64 weiAmount) internal {
        CoreWriterLibrary.tokenDelegate(validator, weiAmount, false /* isUndelegate */ );
        // Update the last delegation change block number
        lastDelegationChangeBlockNumber[validator] = block.number;
    }

    /// @notice Undelegates to the validator, and checkpoints this block number as the last delegation change
    function _undelegate(address validator, uint64 weiAmount) internal {
        // Check if we have enough HYPE to undelegate
        (bool exists, L1ReadLibrary.Delegation memory _delegation) = _getDelegation(validator);
        require(exists && _delegation.amount >= weiAmount, InsufficientHYPEBalance());

        // Check if the stake is unlocked. This value will only be correct in the block after
        // a delegate action is processed.
        require(
            _delegation.lockedUntilTimestamp <= block.timestamp * 1000,
            StakeLockedUntilTimestamp(validator, _delegation.lockedUntilTimestamp)
        );

        CoreWriterLibrary.tokenDelegate(validator, weiAmount, true /* isUndelegate */ );

        // Update the last delegation change block number
        lastDelegationChangeBlockNumber[validator] = block.number;
    }

    /// @notice Internal function to handle HYPE transfers from the vault.
    /// @dev Reverts if there is not enought HYPE to transfer the requested amount, or if the underlying call fails.
    function _transfer(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) revert InsufficientHYPEBalance();

        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed(recipient, amount);
    }

    /// @notice Returns the delegation for a given validator
    /// @param _validator The validator to get the delegation for
    /// @return The delegation for the given validator
    function _getDelegation(address _validator) internal view returns (bool, L1ReadLibrary.Delegation memory) {
        // IMPORTANT: We enforce a one-block delay between delegating/undelegating to a validator and reading the
        // delegation state for the validator from the L1Read precompiles. This is to ensure that the delegation
        // state is updated in the L1Read precompiles before reading it.
        require(
            lastDelegationChangeBlockNumber[_validator] == 0
                || block.number > lastDelegationChangeBlockNumber[_validator],
            CannotReadDelegationUntilNextBlock()
        );

        L1ReadLibrary.Delegation[] memory delegations = L1ReadLibrary.delegations(address(this));
        for (uint256 i = 0; i < delegations.length; i++) {
            if (delegations[i].validator == _validator) {
                return (true, delegations[i]);
            }
        }
        return (false, L1ReadLibrary.Delegation({validator: address(0), amount: 0, lockedUntilTimestamp: 0}));
    }
}
