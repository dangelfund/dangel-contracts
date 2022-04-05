// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title dAngelVesting
 */
contract dAngelVesting is Ownable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct VestingSchedule {
        address beneficiary;
        uint256 totalAmount;
        uint256 releasedAmount;
        bool revoked;
    }

    uint256 private _start;
    uint256 private _finish;
    uint256 private _duration;
    uint256 private _releasesCount;
    bool private _revocable;
    
    // address of the token
    IERC20 private _token;

    address[] private _vestingSchedulesAddresses;
    mapping(address => VestingSchedule) private _vestingSchedules;
    uint256 private _vestingSchedulesTotalAmount;

    event Released(address beneficiary, uint256 amount);
    event Revoked(address beneficiary, uint256 amount);
    /**
     * @dev Creates a vesting contract.
     * @param token address of the ERC20 token contract
     */
    constructor(address token, uint256 start, uint256 duration, uint256 releasesCount, bool revocable) {
        require(token != address(0), "dAngelVesting: token is the zero address!");
        require(duration > 0, "dAngelVesting: duration is 0!");
        require(releasesCount > 0, "dAngelVesting: releases count is 0!");
        require(block.timestamp <= start, "dAngelVesting: TIMESTAMP_INVALID");

        _token = IERC20(token);
        _start = start;
        _duration = duration;
        _releasesCount = releasesCount;
        _finish = _start + _releasesCount * _duration;
        _revocable = revocable;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
    }
    
  /****************************|
    |          Modifiers         |
    |___________________________*/

    modifier onlyOperator(){
        require(hasRole(OPERATOR_ROLE, _msgSender()));
        _;
    }


    /***********************|
    |        Modifiers      |
    |______________________*/
    /**
    * @dev Reverts if the vesting schedule does not exist or has been revoked.
    */
    modifier onlyIfNotRevoked(address _beneficiary) {
        require(_vestingSchedules[_beneficiary].beneficiary != address(0));
        require(_vestingSchedules[_beneficiary].revoked == false);
        _;
    }


    /***********************|
    |          Getters      |
    |______________________*/
    /**
     * @dev Returns the address of the ERC20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     */
    function getBeneficiarySchedule(address _beneficiary) public view returns (
        bool hasVesting,
        uint256 totalAmount,
        uint256 vestedAmount,
        uint256 releasedAmount,
        bool revoked
    )
    {
        VestingSchedule storage Schedule = _vestingSchedules[_beneficiary];
        return (
            (!Schedule.revoked && Schedule.beneficiary != address(0)),
            Schedule.totalAmount,
            _vestedAmount(_beneficiary),
            Schedule.releasedAmount,
            Schedule.revoked
        );
    }
        /**
     * @notice Returns the vesting schedule information for all beneficiaries.
     */
    function getVestingSchedule()
        external
        view
        returns (
            uint256 startTime,
            uint256 finishTime,
            uint256 interval,
            uint256 releasesCount,
            bool revocable,
            uint256 numberOfBeneficiaries
        )
    {
        return (
            _start, _finish, _duration, _releasesCount,
            _revocable, _vestingSchedulesAddresses.length
        );
    }

    /**
     * @notice Creates new vesting schedules.
     * @param __vestingSchedules array of vesting schedules to create.
     */

    function createVestingSchedules(VestingSchedule[] memory __vestingSchedules)
        public
        onlyOperator
    {
        for (uint256 i = 0; i < __vestingSchedules.length; i++) {
            createVestingSchedule(
                __vestingSchedules[i].beneficiary,
                __vestingSchedules[i].totalAmount
            );
        }
    }
    
   
    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _totalAmount total amount of tokens to be released at the end of the vesting
     */
     
    function createVestingSchedule(
        address _beneficiary,
        uint256 _totalAmount
    ) private onlyOperator {
        require(_beneficiary != address(0), "dAngelVesting: ZERO_ADDRESS");
        require(_totalAmount > 0, "dAngelVesting: ZERO_AMOUNT");

        VestingSchedule storage Schedule = _vestingSchedules[_beneficiary];
        require(Schedule.totalAmount == 0, "dAngelVesting: ADDRESS_ALREADY_INITIALIZED");
        _vestingSchedules[_beneficiary] = VestingSchedule(
                _beneficiary,
                _totalAmount,
                0, /*released*/
                false /*revoked*/
            );
        _vestingSchedulesAddresses.push(_beneficiary);
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount + _totalAmount;
    }

 

    /**
     * @notice Release vested tokens.
     */
    function claim() public nonReentrant onlyIfNotRevoked(msg.sender){
        VestingSchedule storage Schedule = _vestingSchedules[msg.sender];
        require(
            msg.sender == Schedule.beneficiary,
            "dAngelVesting: NOT_BENEFICIARY"
        );
        uint256 unreleased = _releasableAmount(msg.sender, Schedule.releasedAmount );
        require(unreleased > 0, "dAngelVesting: NO_RELEASABLE_AMOUNT");
        uint256 balance = _token.balanceOf(address(this));
        require(balance >= unreleased, "dAngelVesting: INSUFFICIENT_BALANCE");

        Schedule.releasedAmount = Schedule.releasedAmount + unreleased;
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount - unreleased;
        _token.safeTransfer(payable(msg.sender), unreleased);

        emit Released(msg.sender, unreleased);
    }


    function revokeVesting(address _beneficiary, address receiver) 
        external 
        onlyOperator
        onlyIfNotRevoked(_beneficiary)
    {
        require(_revocable, "dAngelVesting: VESTING_IRREVOCABLE");
        VestingSchedule storage Schedule = _vestingSchedules[_beneficiary];
        uint256 unreleased = _releasableAmount(_beneficiary, Schedule.releasedAmount);
        if (unreleased > 0){
          _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount - unreleased;
          _token.safeTransfer(payable(receiver), unreleased);
        }
        Schedule.revoked = true;

        emit Revoked(_beneficiary, unreleased);
    }
    
    function _releasableAmount(address _beneficiary, uint256 released) private view returns (uint256) {
        return _vestedAmount(_beneficiary) - released;
    }

    function _vestedAmount(address _beneficiary) internal view returns (uint256) {
        uint256 currentTime = block.timestamp;
        VestingSchedule storage Schedule = _vestingSchedules[_beneficiary];

        if (currentTime  < _start) {
            return 0;
        } else if (currentTime  >= _finish || Schedule.revoked) {
            return Schedule.totalAmount;
        } else {
            uint256 timeLeftAfterStart = currentTime - _start;
            uint256 availableReleases = timeLeftAfterStart / _duration;
            uint256 tokensPerRelease = Schedule.totalAmount / _releasesCount;
            
            return availableReleases * tokensPerRelease;
        }
    }
    
    function emergencyWithdraw(address receiver) external onlyOwner {
        require(receiver != address(0), "dAngelVesting: ADDRESS_INVALID");
        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(receiver, balance);
    }
    
}