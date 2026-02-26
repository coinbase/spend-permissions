// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SpendRouter} from "src/SpendRouter.sol";
import {SpendRouterTestBase} from "test/src/SpendRouter/SpendRouterTestBase.sol";

contract EncodeExtraDataTest is SpendRouterTestBase {
    /// @notice Reverts with ZeroAddress when executor is address(0).
    /// @dev First check in encodeExtraData(). Recipient is a valid non-zero address.
    function test_reverts_whenExecutorIsZeroAddress() public {
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.encodeExtraData(address(0), address(2));
    }

    /// @notice Reverts with ZeroAddress when recipient is address(0).
    /// @dev Second check in encodeExtraData(). Executor is a valid non-zero address.
    function test_reverts_whenRecipientIsZeroAddress() public {
        vm.expectRevert(SpendRouter.ZeroAddress.selector);
        router.encodeExtraData(address(1), address(0));
    }

    /// @notice Encodes two addresses into a 64-byte payload that roundtrips correctly through decodeExtraData.
    /// @dev Fuzz both addresses, excluding address(0). Asserts decoded values match inputs and length is 64.
    function test_encodesAndDecodesCorrectly(address fuzzExecutor, address fuzzRecipient) public view {
        vm.assume(fuzzExecutor != address(0));
        vm.assume(fuzzRecipient != address(0));

        bytes memory extraData = router.encodeExtraData(fuzzExecutor, fuzzRecipient);
        assertEq(extraData.length, 64);

        (address decodedExecutor, address decodedRecipient) = abi.decode(extraData, (address, address));
        assertEq(decodedExecutor, fuzzExecutor);
        assertEq(decodedRecipient, fuzzRecipient);
    }
}
