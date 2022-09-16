// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/OperatorInterface.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title The LinkTokenReceiver contract - used for the MockOracle below
 */
abstract contract LinkTokenReceiver {
    uint256 private constant SELECTOR_LENGTH = 4;
    uint256 private constant EXPECTED_REQUEST_WORDS = 2;
    uint256 private constant MINIMUM_REQUEST_LENGTH =
    SELECTOR_LENGTH + (32 * EXPECTED_REQUEST_WORDS);

    /**
     * @notice Called when LINK is sent to the contract via `transferAndCall`
     * @dev The data payload's first 2 words will be overwritten by the `_sender` and `_amount`
     * values to ensure correctness. Calls oracleRequest.
     * @param _sender Address of the sender
     * @param _amount Amount of LINK sent (specified in wei)
     * @param _data Payload of the transaction
     */
    function onTokenTransfer(
        address _sender,
        uint256 _amount,
        bytes memory _data
    )
        public
        onlyLINK
        validRequestLength(_data)
        permittedFunctionsForLINK(_data)
    {
        assembly {
            // solhint-disable-next-line avoid-low-level-calls
            mstore(add(_data, 36), _sender) // ensure correct sender is passed
            // solhint-disable-next-line avoid-low-level-calls
            mstore(add(_data, 68), _amount) // ensure correct amount is passed
        }
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = address(this).delegatecall(_data); // calls oracleRequest
        require(success, "Unable to create request");
    }

    function getChainlinkToken() public view virtual returns (address);

    /**
     * @dev Reverts if not sent from the LINK token
     */
    modifier onlyLINK() {
        require(msg.sender == getChainlinkToken(), "Must use LINK token");
        _;
    }

    /**
    * @notice Validate the function called on token transfer
    */
    function _validateTokenTransferAction(bytes4 funcSelector, bytes memory data) internal virtual;

    /**
    * @dev Reverts if the given data does not begin with the `oracleRequest` function selector
    * @param data The data payload of the request
    */
    modifier permittedFunctionsForLINK(bytes memory data) {
        bytes4 funcSelector;
        assembly {
        // solhint-disable-next-line avoid-low-level-calls
        funcSelector := mload(add(data, 32))
        }
        _validateTokenTransferAction(funcSelector, data);
        _;
    }

    /**
     * @dev Reverts if the given payload is less than needed to create a request
     * @param _data The request payload
     */
    modifier validRequestLength(bytes memory _data) {
        require(
            _data.length >= MINIMUM_REQUEST_LENGTH,
            "Invalid request length"
        );
        _;
    }
}

/**
 * @title The Chainlink Mock Oracle contract
 * @notice Chainlink smart contract developers can use this to test their contracts
 */
contract MockOperator is LinkTokenReceiver {
    using Strings for uint256;
    uint256 private constant SELECTOR_LENGTH = 4;
    uint256 private constant EXPECTED_REQUEST_WORDS = 2;
    uint256 private constant MINIMUM_REQUEST_LENGTH = SELECTOR_LENGTH + (32 * EXPECTED_REQUEST_WORDS);
    bytes4 private constant ORACLE_REQUEST_SELECTOR = this.oracleRequest.selector;
    // operatorRequest is intended for version 2, enabling multi-word responses
    bytes4 private constant OPERATOR_REQUEST_SELECTOR = this.operatorRequest.selector;
    uint256 public constant EXPIRY_TIME = 5 minutes;
    uint256 private constant MINIMUM_CONSUMER_GAS_LIMIT = 400000;

    struct Commitment {
        bytes31 paramsHash;
        uint8 dataVersion;
    }

    LinkTokenInterface internal LinkToken;
    mapping(bytes32 => Commitment) private s_commitments;

    bytes32 public lastRequestIdReceived;
    address public lastCallbackAddress;
    bytes4 public lastCallbackFunctionId;

    event OracleRequest(
        bytes32 indexed specId,
        address requester,
        bytes32 requestId,
        uint256 payment,
        address callbackAddr,
        bytes4 callbackFunctionId,
        uint256 cancelExpiration,
        uint256 dataVersion,
        bytes data
    );

    event CancelOracleRequest(bytes32 indexed requestId);
    event OracleResponse(bytes32 indexed requestId);

    /**
     * @notice Deploy with the address of the LINK token
     * @dev Sets the LinkToken address for the imported LinkTokenInterface
     * @param _link The address of the LINK token
     */
    constructor(address _link) {
        LinkToken = LinkTokenInterface(_link); // external but already deployed and unalterable
    }


    function oracleRequest(
    address sender,
    uint256 payment,
    bytes32 specId,
    address callbackAddress,
    bytes4 callbackFunctionId,
    uint256 nonce,
    uint256 dataVersion,
    bytes calldata data
  ) external onlyLINK {
    (bytes32 requestId, uint256 expiration) = _verifyAndProcessOracleRequest(sender, payment, callbackAddress, callbackFunctionId, nonce, dataVersion);

    emit OracleRequest(specId, sender, requestId, payment, sender, callbackFunctionId, expiration, dataVersion, data);
  }

    function _verifyAndProcessOracleRequest(
    address sender,
    uint256 payment,
    address callbackAddress,
    bytes4 callbackFunctionId,
    uint256 nonce,
    uint256 dataVersion
  ) private returns (bytes32 requestId, uint256 expiration) {
    requestId = keccak256(abi.encodePacked(sender, nonce));
    require(s_commitments[requestId].paramsHash == 0, "Must use a unique ID");
    // solhint-disable-next-line not-rely-on-time
    expiration = block.timestamp + EXPIRY_TIME;
    bytes31 paramsHash = _buildParamsHash(payment, callbackAddress, callbackFunctionId, expiration);
    s_commitments[requestId] = Commitment(paramsHash, uint8(dataVersion));
    return (requestId, expiration);
  }

      /**
   * @notice Creates the Chainlink request
   * @dev Stores the hash of the params as the on-chain commitment for the request.
   * Emits OracleRequest event for the Chainlink node to detect.
   * @param sender The sender of the request
   * @param payment The amount of payment given (specified in wei)
   * @param specId The Job Specification ID
   * @param callbackFunctionId The callback function ID for the response
   * @param nonce The nonce sent by the requester
   * @param dataVersion The specified data version
   * @param data The extra request parameters
   */
    function operatorRequest(
        address sender,
        uint256 payment,
        bytes32 specId,
        bytes4 callbackFunctionId,
        uint256 nonce,
        uint256 dataVersion,
        bytes calldata data
    ) external onlyLINK {
        bytes32 requestId = keccak256(abi.encodePacked(sender, nonce));
        lastRequestIdReceived = requestId;
        lastCallbackAddress = sender;
        lastCallbackFunctionId = callbackFunctionId;
                require(
            s_commitments[requestId].paramsHash == 0,
            "Must use a unique ID"
        );
        // solhint-disable-next-line not-rely-on-time
        uint256 expiration = EXPIRY_TIME;
        bytes31 paramsHash = _buildParamsHash(payment, sender, callbackFunctionId, expiration);
        s_commitments[requestId] = Commitment(paramsHash, uint8(dataVersion));

        emit OracleRequest(specId, sender, requestId, payment, sender, callbackFunctionId, expiration, dataVersion, data);
    }

    function fullfillLastInfoRequest() public {
        fulfillOracleRequest2(lastRequestIdReceived, 0.1 ether, lastCallbackAddress, lastCallbackFunctionId,
         EXPIRY_TIME, abi.encode(lastRequestIdReceived, 77));
    }

    function fullfillLastTweetPublication() public {
        fulfillOracleRequest2(lastRequestIdReceived, 0.1 ether, lastCallbackAddress, lastCallbackFunctionId,
         EXPIRY_TIME, abi.encode(lastRequestIdReceived, block.timestamp + 1 days, 1337));
    }

    function _buildParamsHash(
        uint256 payment,
        address callbackAddress,
        bytes4 callbackFunctionId,
        uint256 expiration
    ) internal pure returns (bytes31) {
        return bytes31(keccak256(abi.encodePacked(payment, callbackAddress, callbackFunctionId, expiration)));
    }

    /**
    * @notice Require that the token transfer action is valid
    * @dev OPERATOR_REQUEST_SELECTOR = multiword, ORACLE_REQUEST_SELECTOR = singleword
    */
    function _validateTokenTransferAction(bytes4 funcSelector, bytes memory data) internal pure override {
        require(data.length >= MINIMUM_REQUEST_LENGTH, "Invalid request length");
        require(
        funcSelector == OPERATOR_REQUEST_SELECTOR || funcSelector == ORACLE_REQUEST_SELECTOR,
        "Must use whitelisted functions"
        );
    }

      /**
   * @notice Called by the Chainlink node to fulfill requests
   * @dev Given params must hash back to the commitment stored from `oracleRequest`.
   * Will call the callback address' callback function without bubbling up error
   * checking in a `require` so that the node can get paid.
   * @param requestId The fulfillment request ID that must match the requester's
   * @param payment The payment amount that will be released for the oracle (specified in wei)
   * @param callbackAddress The callback address to call for fulfillment
   * @param callbackFunctionId The callback function ID to use for fulfillment
   * @param expiration The expiration that the node should respond by before the requester can cancel
   * @param data The data to return to the consuming contract
   * @return Status if the external call was successful
   */
  function fulfillOracleRequest(
    bytes32 requestId,
    uint256 payment,
    address callbackAddress,
    bytes4 callbackFunctionId,
    uint256 expiration,
    bytes32 data
  )
    public
    
    isValidRequest(requestId)
    returns (bool)
  {
    bytes31 paramsHash = _buildParamsHash(payment, callbackAddress, callbackFunctionId, expiration);
    require(s_commitments[requestId].paramsHash == paramsHash, "Params do not match request ID");
    require(s_commitments[requestId].dataVersion <= uint8(2), "Data versions must match");
    delete s_commitments[requestId];
    emit OracleResponse(requestId);
    require(gasleft() >= MINIMUM_CONSUMER_GAS_LIMIT, "Must provide consumer enough gas");
    // All updates to the oracle's fulfillment should come before calling the
    // callback(addr+functionId) as it is untrusted.
    // See: https://solidity.readthedocs.io/en/develop/security-considerations.html#use-the-checks-effects-interactions-pattern
    (bool success, ) = callbackAddress.call(abi.encodeWithSelector(callbackFunctionId, requestId, data)); // solhint-disable-line avoid-low-level-calls
    return success;
  }

  /**
   * @notice Called by the Chainlink node to fulfill requests with multi-word support
   * @dev Given params must hash back to the commitment stored from `oracleRequest`.
   * Will call the callback address' callback function without bubbling up error
   * checking in a `require` so that the node can get paid.
   * @param requestId The fulfillment request ID that must match the requester's
   * @param payment The payment amount that will be released for the oracle (specified in wei)
   * @param callbackAddress The callback address to call for fulfillment
   * @param callbackFunctionId The callback function ID to use for fulfillment
   * @param expiration The expiration that the node should respond by before the requester can cancel
   * @param data The data to return to the consuming contract
   * @return Status if the external call was successful
   */
  function fulfillOracleRequest2(
    bytes32 requestId,
    uint256 payment,
    address callbackAddress,
    bytes4 callbackFunctionId,
    uint256 expiration,
    bytes memory data
  )
    public
    
    isValidRequest(requestId)
    returns (bool)
  {
    bytes31 paramsHash = _buildParamsHash(payment, callbackAddress, callbackFunctionId, expiration);
    require(s_commitments[requestId].paramsHash == paramsHash, "Params do not match request ID");
    require(s_commitments[requestId].dataVersion <= uint8(2), "Data versions must match");
    delete s_commitments[requestId];
    emit OracleResponse(requestId);
    require(gasleft() >= MINIMUM_CONSUMER_GAS_LIMIT, string(abi.encodePacked("Must provide consumer enough gas: ", gasleft().toString())));
    // All updates to the oracle's fulfillment should come before calling the
    // callback(addr+functionId) as it is untrusted.
    // See: https://solidity.readthedocs.io/en/develop/security-considerations.html#use-the-checks-effects-interactions-pattern
    (bool success, ) = callbackAddress.call(abi.encodePacked(callbackFunctionId, data)); // solhint-disable-line avoid-low-level-calls
    return success;
  }

    /**
     * @notice Allows requesters to cancel requests sent to this oracle contract. Will transfer the LINK
     * sent for the request back to the requester's address.
     * @dev Given params must hash to a commitment stored on the contract in order for the request to be valid
     * Emits CancelOracleRequest event.
     * @param _requestId The request ID
     * @param _payment The amount of payment given (specified in wei)
     * @param _expiration The time of the expiration for the request
     */
    function cancelOracleRequest(
        bytes32 _requestId,
        uint256 _payment,
        bytes4,
        uint256 _expiration
    ) external  {
        require(
            s_commitments[_requestId].paramsHash != 0,
            "Must use a unique ID"
        );
        // solhint-disable-next-line not-rely-on-time
        require(_expiration <= block.timestamp, "Request is not expired");

        delete s_commitments[_requestId];
        emit CancelOracleRequest(_requestId);

        assert(LinkToken.transfer(msg.sender, _payment));
    }

    /**
     * @notice Returns the address of the LINK token
     * @dev This is the public implementation for chainlinkTokenAddress, which is
     * an internal method of the ChainlinkClient contract
     */
    function getChainlinkToken() public view override returns (address) {
        return address(LinkToken);
    }

    // MODIFIERS

    /**
     * @dev Reverts if request ID does not exist
     * @param _requestId The given request ID to check in stored `commitments`
     */
    modifier isValidRequest(bytes32 _requestId) {
        require(
            s_commitments[_requestId].paramsHash != 0,
            "Must have a valid requestId"
        );
        _;
    }

    /**
     * @dev Reverts if the callback address is the LINK token
     * @param _to The callback address
     */
    modifier checkCallbackAddress(address _to) {
        require(_to != address(LinkToken), "Cannot callback to LINK");
        _;
    }
}