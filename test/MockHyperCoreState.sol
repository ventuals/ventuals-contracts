// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Converters} from "../src/libraries/Converters.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

contract MockHyperCoreState {
    using Converters for *;
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Constants                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Cheat code address.
    /// Calculated as `address(uint160(uint256(keccak256("hevm cheat code"))))`.
    address public constant VM_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    address public constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;
    uint64 public constant HYPE_TOKEN_ID = 150;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                    CoreWriter Actions                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    struct CoreWriterAction {
        bytes3 action;
        bytes encodedAction;
    }

    struct SpotSend {
        address msgSender;
        address destination;
        uint64 token;
        uint64 weiAmount;
    }

    struct StakingDeposit {
        address msgSender;
        uint64 weiAmount;
    }

    struct StakingWithdraw {
        address msgSender;
        uint64 weiAmount;
    }

    struct TokenDelegate {
        address msgSender;
        address validator;
        uint64 amount;
        bool isUndelegate;
    }

    struct SystemTransfer {
        address msgSender;
        address systemAddress;
        uint256 amount;
    }

    struct PendingStakingWithdraw {
        address msgSender;
        uint64 weiAmount;
        uint256 timestamp; // Timestamp of withdraw (seconds)
    }

    mapping(address => uint64) public systemAddressToTokenId;
    mapping(uint64 => address) public tokenIdToSystemAddress;
    mapping(address => mapping(uint64 => uint64)) public spotBalances;

    SystemTransfer[] public pendingSystemTransfers;
    CoreWriterAction[] public pendingCoreWriterActions;
    PendingStakingWithdraw[] public pendingStakingWithdraws;
    uint256 nextPendingStakingWithdrawIndex;

    /// @dev User -> Delegator Summary
    mapping(address => L1ReadLibrary.DelegatorSummary) public delegatorSummaries;
    /// @dev User -> Validator -> Delegation
    mapping(address => mapping(address => L1ReadLibrary.Delegation)) public validatorDelegations;
    /// @dev User -> Validators
    mapping(address => EnumerableSet.AddressSet) private userToValidators;

    function init() external {
        systemAddressToTokenId[HYPE_SYSTEM_ADDRESS] = HYPE_TOKEN_ID;
        tokenIdToSystemAddress[HYPE_TOKEN_ID] = HYPE_SYSTEM_ADDRESS;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Mock HyperCore state                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function mockSpotBalance(address user, uint64 token, uint64 weiAmount) external {
        spotBalances[user][token] = weiAmount;
    }

    function mockDelegatorSummary(address user, L1ReadLibrary.DelegatorSummary memory _delegatorSummary) external {
        delegatorSummaries[user] = _delegatorSummary;
    }

    function mockDelegation(address user, L1ReadLibrary.Delegation memory delegation) external {
        validatorDelegations[user][delegation.validator] = delegation;
        userToValidators[user].add(delegation.validator);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Read HyperCore state                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function spotBalance(address user, uint64 token) external view returns (L1ReadLibrary.SpotBalance memory) {
        L1ReadLibrary.SpotBalance memory result = L1ReadLibrary.SpotBalance({total: 0, hold: 0, entryNtl: 0});
        if (token == HYPE_TOKEN_ID) {
            result.total = spotBalances[user][token];
        }
        return result;
    }

    function delegatorSummary(address user) external view returns (L1ReadLibrary.DelegatorSummary memory) {
        return delegatorSummaries[user];
    }

    function delegations(address user) external view returns (L1ReadLibrary.Delegation[] memory) {
        EnumerableSet.AddressSet storage validators = userToValidators[user];
        L1ReadLibrary.Delegation[] memory result = new L1ReadLibrary.Delegation[](validators.length());
        for (uint256 i = 0; i < validators.length(); i++) {
            result[i] = validatorDelegations[user][validators.at(i)];
        }
        return result;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               Record HyperCore interactions                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function sendRawAction(address msgSender, bytes calldata data) external {
        // Get the first byte
        bytes1 version = data[0];
        // Get the next 3 bytes
        bytes3 actionId = bytes3(data[1:4]);
        // Get the rest of the data
        bytes memory encodedAction = data[4:];

        if (version != CoreWriterLibrary.CORE_WRITER_VERSION) {
            console.log("[warn] Invalid CoreWriter version");
            return;
        }

        if (actionId == CoreWriterLibrary.TOKEN_DELEGATE) {
            (address validator, uint64 weiAmount, bool isUndelegate) =
                abi.decode(encodedAction, (address, uint64, bool));
            recordTokenDelegate(msgSender, validator, weiAmount, isUndelegate);
        } else if (actionId == CoreWriterLibrary.STAKING_DEPOSIT) {
            (uint64 weiAmount) = abi.decode(encodedAction, (uint64));
            recordStakingDeposit(msgSender, weiAmount);
        } else if (actionId == CoreWriterLibrary.STAKING_WITHDRAW) {
            (uint64 weiAmount) = abi.decode(encodedAction, (uint64));
            recordStakingWithdraw(msgSender, weiAmount);
        } else if (actionId == CoreWriterLibrary.SPOT_SEND) {
            (address destination, uint64 token, uint64 weiAmount) = abi.decode(encodedAction, (address, uint64, uint64));
            recordSpotSend(msgSender, destination, token, weiAmount);
        } else {
            console.log("[warn] Unsupported CoreWriter action");
        }
    }

    /// @dev EVM -> HyperCore transfer
    function recordSystemTransfer(address msgSender, address systemAddress, uint256 amount) external {
        pendingSystemTransfers.push(
            SystemTransfer({msgSender: msgSender, systemAddress: systemAddress, amount: amount})
        );
    }

    /// @dev HyperCore -> EVM transfer
    function recordSpotSend(address msgSender, address destination, uint64 token, uint64 weiAmount) internal {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.SPOT_SEND,
                encodedAction: abi.encode(
                    SpotSend({msgSender: msgSender, destination: destination, token: token, weiAmount: weiAmount})
                )
            })
        );
    }

    function recordStakingDeposit(address msgSender, uint64 weiAmount) internal {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.STAKING_DEPOSIT,
                encodedAction: abi.encode(StakingDeposit({msgSender: msgSender, weiAmount: weiAmount}))
            })
        );
    }

    function recordStakingWithdraw(address msgSender, uint64 weiAmount) internal {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.STAKING_WITHDRAW,
                encodedAction: abi.encode(StakingWithdraw({msgSender: msgSender, weiAmount: weiAmount}))
            })
        );
    }

    function recordTokenDelegate(address msgSender, address validator, uint64 amount, bool isUndelegate) internal {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.TOKEN_DELEGATE,
                encodedAction: abi.encode(
                    TokenDelegate({msgSender: msgSender, validator: validator, amount: amount, isUndelegate: isUndelegate})
                )
            })
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               Process HyperCore interactions               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function beforeBlock() external {
        // Staking withdraws
        processPendingStakingWithdraws();
    }

    function afterBlock() external {
        // EVM -> HyperCore transfers
        processPendingSystemTransfers();

        // CoreWriter actions
        processPendingCoreWriterActions();
    }

    /// @dev EVM -> HyperCore transfer
    function processPendingSystemTransfers() internal {
        for (uint256 i = 0; i < pendingSystemTransfers.length; i++) {
            SystemTransfer storage transfer = pendingSystemTransfers[i];
            spotBalances[transfer.msgSender][systemAddressToTokenId[transfer.systemAddress]] +=
                transfer.amount.to8Decimals();
        }

        // Reset the pending system transfers
        delete pendingSystemTransfers;
    }

    function processPendingCoreWriterActions() internal {
        for (uint256 i = 0; i < pendingCoreWriterActions.length; i++) {
            CoreWriterAction storage action = pendingCoreWriterActions[i];
            if (action.action == CoreWriterLibrary.TOKEN_DELEGATE) {
                TokenDelegate memory delegate = abi.decode(action.encodedAction, (TokenDelegate));
                processTokenDelegate(delegate);
            } else if (action.action == CoreWriterLibrary.STAKING_DEPOSIT) {
                StakingDeposit memory deposit = abi.decode(action.encodedAction, (StakingDeposit));
                processStakingDeposit(deposit);
            } else if (action.action == CoreWriterLibrary.STAKING_WITHDRAW) {
                StakingWithdraw memory withdraw = abi.decode(action.encodedAction, (StakingWithdraw));
                processStakingWithdraw(withdraw);
            } else if (action.action == CoreWriterLibrary.SPOT_SEND) {
                SpotSend memory send = abi.decode(action.encodedAction, (SpotSend));
                processSpotSend(send);
            }
        }

        // Reset the pending core writer actions
        delete pendingCoreWriterActions;
    }

    function processTokenDelegate(TokenDelegate memory delegate) internal {
        L1ReadLibrary.Delegation storage delegation = validatorDelegations[delegate.msgSender][delegate.validator];
        L1ReadLibrary.DelegatorSummary storage _delegatorSummary = delegatorSummaries[delegate.msgSender];
        if (delegate.isUndelegate) {
            if (block.timestamp < delegation.lockedUntilTimestamp / 1000) {
                console.log("[warn] Delegation is locked");
            } else if (delegation.amount < delegate.amount) {
                console.log("[warn] Delegation amount is less than delegate amount");
            } else {
                // Update delegator summary
                _delegatorSummary.delegated -= delegate.amount;
                _delegatorSummary.undelegated += delegate.amount;

                // Update delegation
                delegation.amount -= delegate.amount;

                // Remove delegation if amount is 0
                if (delegation.amount == 0) {
                    delete validatorDelegations[delegate.msgSender][delegate.validator];
                    userToValidators[delegate.msgSender].remove(delegate.validator);
                }
            }
        } else {
            if (_delegatorSummary.undelegated < delegate.amount) {
                console.log("[warn] Undelegated amount is less than delegate amount");
            } else {
                // Update delegator summary
                _delegatorSummary.undelegated -= delegate.amount;
                _delegatorSummary.delegated += delegate.amount;

                // Update delegation
                delegation.amount += delegate.amount;
                delegation.lockedUntilTimestamp = uint64((block.timestamp + 1 days) * 1000);

                // Update userToValidators
                userToValidators[delegate.msgSender].add(delegate.validator);
            }
        }
    }

    function processStakingDeposit(StakingDeposit memory deposit) internal {
        // Deduct from spot balance
        spotBalances[deposit.msgSender][systemAddressToTokenId[HYPE_SYSTEM_ADDRESS]] -= deposit.weiAmount;

        // Update delegator summary
        L1ReadLibrary.DelegatorSummary storage _delegatorSummary = delegatorSummaries[deposit.msgSender];
        _delegatorSummary.undelegated += deposit.weiAmount;
    }

    function processStakingWithdraw(StakingWithdraw memory withdraw) internal {
        // Update delegator summary
        L1ReadLibrary.DelegatorSummary storage _delegatorSummary = delegatorSummaries[withdraw.msgSender];
        _delegatorSummary.undelegated -= withdraw.weiAmount;
        _delegatorSummary.totalPendingWithdrawal += withdraw.weiAmount;
        _delegatorSummary.nPendingWithdrawals += 1;

        // Add to pending withdraws
        pendingStakingWithdraws.push(
            PendingStakingWithdraw({
                msgSender: withdraw.msgSender,
                weiAmount: withdraw.weiAmount,
                timestamp: block.timestamp
            })
        );
    }

    /// @dev HyperCore -> EVM transfer
    function processSpotSend(SpotSend memory send) internal {
        spotBalances[send.msgSender][send.token] -= send.weiAmount;
        Vm(VM_ADDRESS).deal(send.msgSender, send.weiAmount.to18Decimals());
    }

    function processPendingStakingWithdraws() internal {
        while (nextPendingStakingWithdrawIndex < pendingStakingWithdraws.length) {
            PendingStakingWithdraw storage withdraw = pendingStakingWithdraws[nextPendingStakingWithdrawIndex];
            if (block.timestamp >= withdraw.timestamp + 7 days) {
                // Add to spot balance
                spotBalances[withdraw.msgSender][systemAddressToTokenId[HYPE_SYSTEM_ADDRESS]] += withdraw.weiAmount;

                // Update delegator summary
                L1ReadLibrary.DelegatorSummary storage _delegatorSummary = delegatorSummaries[withdraw.msgSender];
                _delegatorSummary.totalPendingWithdrawal -= withdraw.weiAmount;
                _delegatorSummary.nPendingWithdrawals -= 1;

                nextPendingStakingWithdrawIndex++;
            } else {
                break;
            }
        }
    }
}
