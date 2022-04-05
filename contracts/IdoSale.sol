// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * Users can purchase tokens after sale started and claim after sale ended
 */

contract IDOSale is Ownable, Pausable, AccessControl,  ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    // user address => amounts
    mapping(address => uint256) private whitelist;
    // user address => purchased token amount
    mapping(address => uint256) private purchasedAmounts;
    // Once-whitelisted user address array, even removed users still remain
    address[] private _whitelistedUsers;
    // IDO token price
    uint256 public idoPrice;
    // USDT address
    IERC20 public purchaseToken;
    // The total purchased amount
    uint256 public totalPurchasedAmount;
    // Date timestamp when token sale start
    uint256 public startTime;
    // Date timestamp when token sale ends
    uint256 public endTime;

    // Used for returning purchase history
    struct Purchase {
        address account;
        uint256 amount;
    }

    event IdoPriceChanged(uint256 idoPrice);
    event WhitelistAdded(address indexed account);
    event WhitelistRemoved(address indexed account);
    event Purchased(address indexed sender, uint256 amount);
    event Swept(address indexed sender, uint256 amount);
    event IdoStartTimeChanged(uint256 startTime);
    event IdoEndTimeChanged(uint256 endTime);

    constructor(
        IERC20 _purchaseToken,
        uint256 _idoPrice,
        uint256 _startTime,
        uint256 _endTime
    ) {
        require(address(_purchaseToken) != address(0), "PURCHASE_TOKEN_ADDRESS_INVALID");
        require(_idoPrice > 0, "TOKEN_PRICE_INVALID");
        require(block.timestamp <= _startTime && _startTime < _endTime, "TIMESTAMP_INVALID");

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());

        purchaseToken = _purchaseToken;
        idoPrice = _idoPrice;
        startTime = _startTime;
        endTime = _endTime;
    }

    modifier onlyOperator(){
        require(hasRole(OPERATOR_ROLE, _msgSender()));
        _;
    }
    /**************************|
    |          Getters         |
    |_________________________*/
    function getWhitelistedAmount(address account) public view onlyOperator returns (uint256) {
        return whitelist[account];
    } 
    function getPurchasedAmount(address account) public view onlyOperator returns (uint256) {
        return purchasedAmounts[account];
    }

    /**************************|
    |          Setters         |
    |_________________________*/

    /**
     * @dev Set ido token price in purchaseToken
     */
    function setIdoPrice(uint256 _idoPrice) external onlyOwner {
        idoPrice = _idoPrice;

        emit IdoPriceChanged(_idoPrice);
    }

    /**
     * @dev Set ido start time
     */
    function setStartTime(uint256 _startTime) external onlyOwner {
        startTime = _startTime;

        emit IdoStartTimeChanged(_startTime);
    }

        /**
     * @dev Set ido start time
     */
    function setEndTime(uint256 _endTime) external onlyOwner {
        endTime = _endTime;

        emit IdoEndTimeChanged(_endTime);
    }

    /****************************|
    |          Whitelist         |
    |___________________________*/

    /**
     * @dev Return whitelisted users
     * The result array can include zero address
     */
    function whitelistedUsers() external view returns (Purchase[] memory) {
       Purchase[] memory __whitelistedUsers = new Purchase[](_whitelistedUsers.length);
        for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
            if (whitelist[_whitelistedUsers[i]] == 0) {
                continue;
            }
            __whitelistedUsers[i].account = _whitelistedUsers[i];
            __whitelistedUsers[i].amount = whitelist[_whitelistedUsers[i]];
        }

        return __whitelistedUsers;
    }

    /**
     * @dev Add wallet to whitelist
     * If wallet is added, removed and added to whitelist, the account is repeated
     */

    function addWhitelist(Purchase[] memory _accounts) external onlyOperator whenNotPaused {
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i].account != address(0), "ZERO_ADDRESS");
            if (whitelist[_accounts[i].account] == 0) {
                whitelist[_accounts[i].account] = _accounts[i].amount;
                _whitelistedUsers.push(_accounts[i].account);
                emit WhitelistAdded(_accounts[i].account);
            }          
        }
    }

    /**
     * @dev Remove wallet from whitelist
     * Removed wallets still remain in `_whitelistedUsers` array
     */
    function removeWhitelist(Purchase[] memory _accounts) external onlyOperator whenNotPaused {
        for (uint256 i = 0; i < _accounts.length; i++) {
            require(_accounts[i].account != address(0), "ZERO_ADDRESS");
            if (whitelist[_accounts[i].account]>0) {
                whitelist[_accounts[i].account] = 0;

                emit WhitelistRemoved(_accounts[i].account);
            }         
        }
    }

    /***************************|
    |          Purchase         |
    |__________________________*/

    /**
     * @dev Return purchase history (wallet address, amount)
     * The result array can include zero amount item
     */
    function purchaseHistory() external view returns (Purchase[] memory) {
        Purchase[] memory purchases = new Purchase[](_whitelistedUsers.length);
        for (uint256 i = 0; i < _whitelistedUsers.length; i++) {
            purchases[i].account = _whitelistedUsers[i];
            purchases[i].amount = purchasedAmounts[_whitelistedUsers[i]];
        }

        return purchases;
    }

    /**
     * @dev Purchase IDO token
     * Only whitelisted users can purchase within `purchcaseCap` amount
     */
    function purchase(uint256 amount) external nonReentrant whenNotPaused {
        require(startTime <= block.timestamp, "SALE_NOT_STARTED");
        require(block.timestamp < endTime, "SALE_ALREADY_ENDED");
        require(amount > 0, "PURCHASE_AMOUNT_INVALID");
        require(whitelist[_msgSender()]>=0, "CALLER_NO_WHITELIST");
        uint256 purchaseTokenAmount = amount * idoPrice / (10 ** 18);
        require(purchaseTokenAmount <= purchaseToken.balanceOf(_msgSender()), "INSUFFICIENT_FUNDS");

        purchasedAmounts[_msgSender()] += amount;
        totalPurchasedAmount += amount;
        purchaseToken.safeTransferFrom(_msgSender(), address(this), purchaseTokenAmount);

        emit Purchased(_msgSender(), amount);
    }

    /**
     * @dev `Operator` sweeps `purchaseToken` from the sale contract to `to` address
     */
    function sweep(address to) external onlyOwner {
        require(to != address(0), "ADDRESS_INVALID");
        require(endTime <= block.timestamp, "SALE_NOT_ENDED");
        uint256 bal = purchaseToken.balanceOf(address(this));
        purchaseToken.safeTransfer(to, bal);

        emit Swept(to, bal);
    }
}