// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Converters} from "../src/libraries/Converters.sol";
import {L1ReadLibrary} from "../src/libraries/L1ReadLibrary.sol";
import {CoreWriterLibrary} from "../src/libraries/CoreWriterLibrary.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

contract MockHyperCoreState {
    using Converters for *;

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

    mapping(address => uint64) public systemAddressToTokenId;
    mapping(uint64 => address) public tokenIdToSystemAddress;
    mapping(address => mapping(uint64 => uint64)) public spotBalances;

    SystemTransfer[] public pendingSystemTransfers;
    CoreWriterAction[] public pendingCoreWriterActions;

    /// @dev User -> Delegator Summary
    mapping(address => L1ReadLibrary.DelegatorSummary) public delegatorSummaries;
    /// @dev User -> Validator -> Delegation
    mapping(address => mapping(address => L1ReadLibrary.Delegation)) public validatorDelegations;

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Read HyperCore state                   */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function spotBalance(address user, uint64 token) external view returns (L1ReadLibrary.SpotBalance memory) {
        L1ReadLibrary.SpotBalance memory spotBalance = L1ReadLibrary.SpotBalance({total: 0, hold: 0, entryNtl: 0});
        if (token == HYPE_TOKEN_ID) {
            spotBalance.total = spotBalances[user][token];
        }
        return spotBalance;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*               Record HyperCore interactions                */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev EVM -> HyperCore transfer
    function recordSystemTransfer(address msgSender, address systemAddress, uint256 amount) external {
        pendingSystemTransfers.push(
            SystemTransfer({msgSender: msgSender, systemAddress: systemAddress, amount: amount})
        );
    }

    /// @dev HyperCore -> EVM transfer
    function recordSpotSend(address msgSender, address destination, uint64 token, uint64 weiAmount) external {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.SPOT_SEND,
                encodedAction: abi.encode(
                    SpotSend({msgSender: msgSender, destination: destination, token: token, weiAmount: weiAmount})
                )
            })
        );
    }

    function recordStakingDeposit(address msgSender, uint64 weiAmount) external {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.STAKING_DEPOSIT,
                encodedAction: abi.encode(StakingDeposit({msgSender: msgSender, weiAmount: weiAmount}))
            })
        );
    }

    function recordStakingWithdraw(address msgSender, uint64 weiAmount) external {
        pendingCoreWriterActions.push(
            CoreWriterAction({
                action: CoreWriterLibrary.STAKING_WITHDRAW,
                encodedAction: abi.encode(StakingWithdraw({msgSender: msgSender, weiAmount: weiAmount}))
            })
        );
    }

    function recordTokenDelegate(address msgSender, address validator, uint64 amount, bool isUndelegate) external {
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

    function processBlock() external {
        processPendingSystemTransfers();
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
                processPendingSpotSend(send);
            }
        }

        // Reset the pending core writer actions
        delete pendingCoreWriterActions;
    }

    function processTokenDelegate(TokenDelegate memory delegate) internal {
        L1ReadLibrary.Delegation storage delegation = validatorDelegations[delegate.msgSender][delegate.validator];
        L1ReadLibrary.DelegatorSummary storage delegatorSummary = delegatorSummaries[delegate.msgSender];
        if (delegate.isUndelegate) {
            if (block.timestamp < delegation.lockedUntilTimestamp / 1000) {
                console.log("[warn] Delegation is locked");
            } else if (delegation.amount < delegate.amount) {
                console.log("[warn] Delegation amount is less than delegate amount");
            } else {
                delegation.amount -= delegate.amount;
                delegatorSummary.delegated -= delegate.amount;
                delegatorSummary.totalPendingWithdrawal += delegate.amount;
                delegatorSummary.nPendingWithdrawals += 1;
            }
        } else {
            if (delegatorSummary.undelegated < delegate.amount) {
                console.log("[warn] Undelegated amount is less than delegate amount");
            } else {
                delegatorSummary.undelegated -= delegate.amount;
                delegatorSummary.delegated += delegate.amount;

                // Update delegation
                delegation.amount += delegate.amount;
                delegation.lockedUntilTimestamp = uint64((block.timestamp + 1 days) * 1000);
            }
        }
    }

    function processStakingDeposit(StakingDeposit memory deposit) internal {
        // Deduct from spot balance
        spotBalances[deposit.msgSender][systemAddressToTokenId[HYPE_SYSTEM_ADDRESS]] -= deposit.weiAmount;

        // Update delegator summary
        L1ReadLibrary.DelegatorSummary storage delegatorSummary = delegatorSummaries[deposit.msgSender];
        delegatorSummary.undelegated += deposit.weiAmount;
    }

    function processStakingWithdraw(StakingWithdraw memory withdraw) internal {
        // TODO: Handle 7-day unstaking queue
        // Add to spot balance
        spotBalances[withdraw.msgSender][systemAddressToTokenId[HYPE_SYSTEM_ADDRESS]] += withdraw.weiAmount;

        // Update delegator summary
        L1ReadLibrary.DelegatorSummary storage delegatorSummary = delegatorSummaries[withdraw.msgSender];
        delegatorSummary.undelegated -= withdraw.weiAmount;
        delegatorSummary.totalPendingWithdrawal += withdraw.weiAmount;
        delegatorSummary.nPendingWithdrawals += 1;
    }

    /// @dev HyperCore -> EVM transfer
    function processPendingSpotSend(SpotSend memory send) internal {
        spotBalances[send.msgSender][send.token] -= send.weiAmount;
        Vm(VM_ADDRESS).deal(send.msgSender, send.weiAmount.to18Decimals());
    }
}
