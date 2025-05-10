// pragma solidity ^0.8.26;
// import {Ownable} from 'solady/auth/Ownable.sol';
// import {IERC20, IAaveMarket, IFeeClaimer} from "../Interfaces.sol";

// contract FeeClaimer is Ownable, IFeeClaimer {
//     // Maximum numerator for Setting.ownerSplit param to ensure that the Owner can't claim more than 100% of revenue
//     uint8 constant MAX_SPLIT = 100;
//     // cap revenue per claim to avoid overflows on multiplication when calculating percentages
//     uint256 constant MAX_REVENUE = type(uint256).max / MAX_SPLIT;
//     address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

//     uint8 public ownerSplit; // x/100 % to Owner, rest to Operator
//     struct ClaimContract {
//         bytes4 claimFunction; // function signature on contract to call and claim revenue
//         bytes4 transferOwnerFunction; // function signature on contract to call and transfer ownership
//     }

//     /// @notice Economic owner of FeeClaimer revenue streams
//     // address owner; set in Ownable
//     /// @notice account in charge of running onchain ops of rev-shared contracts on behalf of owner
//     address operator;
//     /// @notice Total amount of revenue tokens help by the FeeClaimer and available to be claimed by owner
//     mapping(address => uint256) ownerTokens; // token -> claimable
//     /// @notice Total amount of revenue tokens help by the FeeClaimer and available to be claimed by operator
//     mapping(address => uint256) operatorTokens; // token -> claimable
//     /// @notice Functions that the operator is allowed to run on all revenue contracts controlled by the FeeClaimer
//     mapping(bytes4 => bool) whitelistedFunctions; // function -> allowed
//     /// @notice Configurations for revenue contracts related to the split of revenue, access control to claiming revenue tokens and transfer of FeeClaimer ownership
//     mapping(address => ClaimContract) settings; // revenue contract -> settings

//     // Fees Events
//     event AddFeeContract(address indexed feeContract, uint256 ownerSplit, bytes4 claimFnSig, bytes4 trsfrFnSig);
//     event RemoveFeeContract(address indexed feeContract, address token);
//     event UpdateWhitelistFunction(bytes4 indexed func, bool allowed);
//     event UpdateOwnerSplit(address indexed feeContract, uint8 split);
//     event ClaimFees(address indexed feeContract, address indexed token , uint256 amount, uint256 escrowed);
//     event ClaimOwnerTokens(address indexed token, address indexed owner, uint256 amount);
//     event ClaimOperatorTokens(address indexed token, address indexed operator, uint256 amount);
//     // Stakeholder Events
//     event UpdateOwner(address indexed newOwner);
//     event UpdateOperator(address indexed newOperator);

//     // Errors
//     error BadFunction();
//     error OnlyOperator();
//     error OperatorFnNotWhitelisted();
//     error OperatorFnNotValid();
//     error OperatorFnCallFailed();
//     error ClaimFailed();
//     error NoFees();
//     error UnclaimedFees();
//     error CallerAccessDenied();
//     error BadSetting();
//     error InvalidFeeContract();
//     error FeeContractSettingsExist();
//     error TransferFailed();
//     error InvalidRevenueSplit();

//     /**
//      * @notice          - Configure data for FeeClaimer stakeholders
//      *                  - Owner/operator/treasury can all be the same address when setting up a FeeClaimer
//      * @param _owner    - An address that controls the FeeClaimer and owns rights to some or all tokens earned by owned revenue contracts
//      * @param _operator - An active address for non-Owner that can execute whitelisted functions to manage and maintain product operations
//      *                  - on revenue generating contracts controlled by the FeeClaimer.
//      */
//     function initialize(address _owner, address _operator, uint8 _ownerSplit) public {
//         if(owner() != address(0)) revert AlreadyInitialized();
//         if(_ownerSplit > MAX_SPLIT)   revert InvalidRevenueSplit();

//         operator = _operator; // owner can set operator
//         ownerSplit = _ownerSplit;
//         _initializeOwner(msg.sender);
//     }

//     modifier onlyOperator() virtual {
//         if(msg.sender != operator) revert OnlyOperator();
//         _;
//     }

//     function _claimFees(
//         address feeContract,
//         address token,
//         bytes calldata data
//     ) public returns (uint256 claimed) {
//         if (settings[feeContract].transferOwnerFunction == bytes4(0)) {
//             revert InvalidFeeContract();
//         }

//         uint256 existingBalance = getBalance(token);

//         if (settings[feeContract].claimFunction == bytes4(0)) {
//             // push payments
//             // claimed = total balance - already accounted for balance
//             claimed = existingBalance - ownerTokens[token] - operatorTokens[token];
//             // underflow revert ensures we have more tokens than we started with and actually claimed revenue
//         } else {
//             // pull payments
//             if (bytes4(data) != settings[feeContract].claimFunction) {
//                 revert BadFunction();
//             }
//             (bool claimSuccess, ) = feeContract.call(data);
//             if (!claimSuccess) {
//                 revert ClaimFailed();
//             }

//             // claimed = total balance - existing balance
//             claimed = getBalance(token) - existingBalance;
//             // underflow revert ensures we have more tokens than we started with and actually claimed revenue
//         }

//         if (claimed == 0) {
//             revert NoFees();
//         }

//         // cap so uint doesnt overflow in split calculations.
//         // can sweep by "attaching" a push payment fee contract with same token
//         if (claimed > MAX_REVENUE) claimed = MAX_REVENUE;

//         return claimed;
//     }

//     /** see FeeContract.claimFees */
//     function claimFees(
//         address feeContract,
//         address token,
//         bytes calldata data
//     ) external returns (uint256 claimed) {
//         claimed = _claimFees(feeContract, token, data);

//         // splits revenue stream according to FeeContract settings
//         uint256 newOwnerTokens = (claimed * ownerSplit) / 100;
//         // update escrowed balance
//         ownerTokens[token] = ownerTokens[token] + newOwnerTokens;

//         // update operator amount
//         if (claimed > newOwnerTokens) {
//             operatorTokens[token] = operatorTokens[token] + (claimed - newOwnerTokens);
//         }

//         emit ClaimFees(feeContract, token, claimed, newOwnerTokens);

//         return claimed;
//     }

//     /** see FeeContract.operate */
//     function operate(address feeContract, bytes calldata data) onlyOperator external returns (bool) {

//         // extract function signature from tx data and check whitelist
//         bytes4 func = bytes4(data);

//         if (!whitelistedFunctions[func]) {
//             revert OperatorFnNotWhitelisted();
//         }

//         // cant claim revenue via operate() because that fucks up accounting logic. Owner shouldn't whitelist it anyway but just in case
//         // also can't transfer ownership so Owner retains control of revenue contract
//         if (
//             func == settings[feeContract].claimFunction ||
//             func == settings[feeContract].transferOwnerFunction
//         ) {
//             revert OperatorFnNotValid();
//         }

//         (bool success, ) = feeContract.call(data);
//         if (!success) {
//             revert OperatorFnCallFailed();
//         }

//         return true;
//     }

//     /** see FeeContract.claimOwnerTokens */
//     function claimOwnerTokens(address token) external returns (uint256 claimed) {
//         // TODO add if(owner != address(this) && != owner) to allow contract that implements to be able to claim fees e.g. RSA
//         if (msg.sender != owner()) {
//             revert CallerAccessDenied();
//         }

//         claimed = ownerTokens[token];

//         ownerTokens[token] = 0; // reset before send to prevent reentrancy

//         if(owner() != address(this)) {
//             _sendOutTokenOrETH(token, owner(), claimed);
//         }

//         emit ClaimOwnerTokens(token, owner(), claimed);

//         return claimed;
//     }

//     /** see FeeContract.claimOperatorTokens */
//     function claimOperatorTokens(address token) external returns (uint256 claimed) {
//         if (msg.sender != operator) {
//             revert CallerAccessDenied();
//         }

//         claimed = operatorTokens[token];

//         if (claimed == 0) {
//             revert ClaimFailed();
//         }

//         operatorTokens[token] = 0; // reset before send to prevent reentrancy

//         _sendOutTokenOrETH(token, operator, claimed);

//         emit ClaimOperatorTokens(token, operator, claimed);

//         return claimed;
//     }

//     /** see FeeContract.addFeeContract */
//     function addFeeContract(
//         address feeContract,
//         ClaimContract memory setting
//     ) external returns (bool) {
//         if (msg.sender != owner()) {
//             revert CallerAccessDenied();
//         }

//         if (feeContract == address(this)) {
//             revert InvalidFeeContract();
//         }

//         // fee contract setting already exists
//         if (settings[feeContract].transferOwnerFunction != bytes4(0)) {
//             revert AlreadyInitialized();
//         }

//         // must set transfer func
//         if (setting.transferOwnerFunction == bytes4(0)) {
//             revert BadSetting();
//         }

//         if (ownerSplit > MAX_SPLIT) {
//             revert BadSetting();
//         }

//         settings[feeContract] = setting;
//         emit AddFeeContract(feeContract, ownerSplit, setting.claimFunction, setting.transferOwnerFunction);

//         return true;
//     }

//     function removeFeeContract(address feeContract) onlyOwner external virtual {
//         (bool success, ) = feeContract.call(
//             abi.encodeWithSelector(
//                 settings[feeContract].transferOwnerFunction,
//                 operator // assume function only takes one param that is new owner address
//             )
//         );
//         require(success);

//         delete settings[feeContract];
//         emit RemoveFeeContract(feeContract);
//     }

//     /**
//      * @notice - Send ETH or ERC20 token from this contract to an external contract
//      * @param token - address of token to send out. Denominations.ETH for raw ETH
//      * @param receiver - address to send tokens to
//      * @param amount - amount of tokens to send
//      */
//     function _sendOutTokenOrETH(address token, address receiver, uint256 amount) internal returns (bool) {
//         if (token == address(0)) {
//             revert TransferFailed();
//         }

//         // both branches revert if call failed
//         if (token != ETH) {
//             // ERC20
//             IERC20(token).transfer(receiver, amount);
//         } else {
//             // ETH
//             (bool success, ) = payable(receiver).call{value: amount}("");
//             if (!success) {
//                 revert TransferFailed();
//             }
//         }
//         return true;
//     }

//     function getBalance(address token) internal view returns (uint256) {
//         if (token == address(0)) return 0;
//         return token != ETH ? IERC20(token).balanceOf(address(this)) : address(this).balance;
//     }
// }