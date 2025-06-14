// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity ^0.8.23;

import "../../src/utils/Types.sol";
import { Execution } from "../../src/utils/Types.sol";
import { CaveatEnforcerBaseTest } from "./CaveatEnforcerBaseTest.t.sol";
import { NativeBalanceChangeEnforcer } from "../../src/enforcers/NativeBalanceChangeEnforcer.sol";
import { ICaveatEnforcer } from "../../src/interfaces/ICaveatEnforcer.sol";
import { Counter } from "../utils/Counter.t.sol";

contract NativeBalanceChangeEnforcerTest is CaveatEnforcerBaseTest {
    ////////////////////////////// State //////////////////////////////
    NativeBalanceChangeEnforcer public enforcer;
    address delegator;
    address delegate;
    address dm;
    Execution noExecution;
    bytes executionCallData = abi.encode(noExecution);

    ////////////////////// Set up //////////////////////

    function setUp() public override {
        super.setUp();
        delegator = address(users.alice.deleGator);
        delegate = address(users.bob.deleGator);
        dm = address(delegationManager);
        enforcer = new NativeBalanceChangeEnforcer();
        vm.label(address(enforcer), "Native Balance Change Enforcer");
        noExecution = Execution(address(0), 0, hex"");
    }

    ////////////////////// Basic Functionality //////////////////////

    // Validates the terms get decoded correctly
    function test_decodedTheTerms() public {
        bytes memory terms_ = abi.encodePacked(false, address(users.carol.deleGator), uint256(100));
        bool enforceDecrease_;
        uint256 amount_;
        address recipient_;
        (enforceDecrease_, recipient_, amount_) = enforcer.getTermsInfo(terms_);
        assertFalse(enforceDecrease_);
        assertEq(recipient_, address(users.carol.deleGator));
        assertEq(amount_, 100);
    }

    // Validates that a balance has increased at least the expected amount
    function test_allow_ifBalanceIncreases() public {
        address recipient_ = delegator;
        // Expect it to increase by at least 100
        bytes memory terms_ = abi.encodePacked(false, recipient_, uint256(100));

        // Increase by 100
        vm.startPrank(dm);
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        _increaseBalance(delegator, 100);
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);

        // Increase by 1000
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        _increaseBalance(delegator, 1000);
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
    }

    // Validates that a balance has decreased at most the expected amount
    function test_allow_ifBalanceDecreases() public {
        address recipient_ = delegator;
        vm.deal(recipient_, 1000); // Start with 1000
        // Expect it to decrease by at most 100
        bytes memory terms_ = abi.encodePacked(true, recipient_, uint256(100));

        // Decrease by 50
        vm.startPrank(dm);
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        _decreaseBalance(delegator, 50);
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);

        // Decrease by 100
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        _decreaseBalance(delegator, 100);
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
    }

    ////////////////////// Errors //////////////////////

    // Reverts if a balance hasn't increased by the specified amount
    function test_notAllow_insufficientIncrease() public {
        address recipient_ = delegator;
        // Expect it to increase by at least 100
        bytes memory terms_ = abi.encodePacked(false, recipient_, uint256(100));

        // Increase by 10, expect revert
        vm.startPrank(dm);
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        _increaseBalance(delegator, 10);
        vm.expectRevert(bytes("NativeBalanceChangeEnforcer:insufficient-balance-increase"));
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
    }

    // Reverts if a balance has decreased more than the specified amount
    function test_notAllow_excessiveDecrease() public {
        address recipient_ = delegator;
        vm.deal(recipient_, 1000); // Start with 1000
        // Expect it to decrease by at most 100
        bytes memory terms_ = abi.encodePacked(true, recipient_, uint256(100));

        // Decrease by 150, expect revert
        vm.startPrank(dm);
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        _decreaseBalance(delegator, 150);
        vm.expectRevert(bytes("NativeBalanceChangeEnforcer:exceeded-balance-decrease"));
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
    }

    // Reverts if a enforcer is locked
    function test_notAllow_reenterALockedEnforcer() public {
        address recipient_ = delegator;
        // Expect it to increase by at least 100
        bytes memory terms_ = abi.encodePacked(false, recipient_, uint256(100));
        bytes32 delegationHash_ = bytes32(uint256(99999999));

        // Increase by 100
        vm.startPrank(dm);
        // Locks the enforcer
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, delegationHash_, delegator, delegate);
        bytes32 hashKey_ = enforcer.getHashKey(address(delegationManager), delegationHash_);
        assertTrue(enforcer.isLocked(hashKey_));
        vm.expectRevert(bytes("NativeBalanceChangeEnforcer:enforcer-is-locked"));
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, delegationHash_, delegator, delegate);
        _increaseBalance(delegator, 1000);
        vm.startPrank(dm);

        // Unlocks the enforcer
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, delegationHash_, delegator, delegate);
        assertFalse(enforcer.isLocked(hashKey_));
        // Can be used again, and locks it again
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, delegationHash_, delegator, delegate);
        assertTrue(enforcer.isLocked(hashKey_));
    }

    // Validates the terms are well formed
    function test_invalid_decodedTheTerms() public {
        address recipient_ = delegator;
        bytes memory terms_;

        // Too small
        terms_ = abi.encodePacked(false, recipient_, uint8(100));
        vm.expectRevert(bytes("NativeBalanceChangeEnforcer:invalid-terms-length"));
        enforcer.getTermsInfo(terms_);

        // Too large
        terms_ = abi.encodePacked(false, uint256(100), uint256(100));
        vm.expectRevert(bytes("NativeBalanceChangeEnforcer:invalid-terms-length"));
        enforcer.getTermsInfo(terms_);
    }

    // Validates that an invalid ID reverts
    function test_notAllow_expectingOverflow() public {
        address recipient_ = delegator;

        // Expect balance to increase so much that the validation overflows
        bytes memory terms_ = abi.encodePacked(false, recipient_, type(uint256).max);
        vm.deal(recipient_, type(uint256).max);
        vm.startPrank(dm);
        enforcer.beforeHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
        vm.expectRevert();
        enforcer.afterHook(terms_, hex"", singleDefaultMode, executionCallData, bytes32(0), delegator, delegate);
    }

    // should fail with invalid call type mode (try instead of default)
    function test_revertWithInvalidExecutionMode() public {
        vm.prank(address(delegationManager));
        vm.expectRevert("CaveatEnforcer:invalid-execution-type");
        enforcer.beforeHook(hex"", hex"", singleTryMode, hex"", bytes32(0), address(0), address(0));
    }

    function _increaseBalance(address _recipient, uint256 _amount) internal {
        vm.deal(_recipient, _recipient.balance + _amount);
    }

    function _decreaseBalance(address _recipient, uint256 _amount) internal {
        vm.deal(_recipient, _recipient.balance - _amount);
    }

    function _getEnforcer() internal view override returns (ICaveatEnforcer) {
        return ICaveatEnforcer(address(enforcer));
    }
}
