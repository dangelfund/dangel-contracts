// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Staking is Ownable, AccessControl{
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");   
    
    struct StakeInfo {
        uint256 amount;
        uint256 endTime;
        bool hasStaked;
    }

    mapping(address => StakeInfo) private _stakes;

    IERC20  public token;
    uint256 public totalStaked;
    uint256 public lockDuration = 3600 * 15;

    event Staked(address from, uint256 amount, uint256 time);
    event Unstaked(address from, uint256 amount, uint256 time);

    constructor(address _token) {
        require(_token != address(0), "ZERO_ADRESS");
        token = IERC20(_token);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
    }

    //GETTERS
    function getStakeAmount(address account) external view returns (uint256){
        return _stakes[account].amount;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        StakeInfo storage staker = _stakes[msg.sender];
        if (!staker.hasStaked){
            staker.hasStaked = true;
        }else {
            require(
                    block.timestamp < staker.endTime,
                    "Lock expired, please withdraw and stake again"
            );
        }
        staker.amount = staker.amount + amount;
        staker.endTime = block.timestamp + lockDuration;
        totalStaked = totalStaked + amount;
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, block.timestamp);
    }


    function withdraw(uint256 amount) external {
        require(amount > 0, "ZERO_AMOUNT");
        StakeInfo storage staker = _stakes[msg.sender];
        require(staker.hasStaked, "NO_STAKES");
        require(
            block.timestamp >= staker.endTime,
            "STAKE_LOCKED"
        );   
        
        staker.amount = staker.amount - amount;
        totalStaked = totalStaked - amount;
        if (staker.amount == 0){
            staker.hasStaked = false;
        }
        token.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, block.timestamp);
    }
    //SETTERS
    function setLockDuration(uint256 _lockDuration) external onlyRole(OPERATOR_ROLE){
        lockDuration = _lockDuration;
    }

}