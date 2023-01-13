// SPDX-License-Identifier: MIT

/*
    Disclaimer: The contract was created based off specific requirements provided by a client.
    Ideally, a large portion of the data here should be stored off-chain.
*/

pragma solidity >= 0.8.0; 

contract CarInsurance {
    uint256 public constant TPO_MONTHLY_PREMIUM = 0.05 ether; 
    uint256 public constant TPFT_MONTHLY_PREMIUM = 0.10 ether;
    uint256 public constant CC_MONTHLY_PREMIUM = 0.15 ether;

    uint256 public constant TPO_MAX_PAYOUT = 1.5 ether; 
    uint256 public constant TPFT_MAX_PAYOUT = 2.8 ether;
    uint256 public constant CC_MAX_PAYOUT = 3.5 ether;

    address private immutable _owner;
    uint256 private _counter;   
    

    struct Customer { 
        string name;
        string nationalId;
        string nationality;
        string phoneNumber;
        uint240 birthYear;
        bool maritalStatus;
        bool banned;
    }

    struct Insurance {
        uint256 engineCapacity;
        uint256 registrationYear;
        uint256 startYear;
        uint256 insurancePeriodInYears;
        uint256 lastPaidTimestamp;
        string numberPlate;
        string brand;
        address customer;
        Plan plan;
        bool electric;
        bool claimed;
    }
    
    enum Plan { TPO, TPFT, CC }

    mapping(uint256 => Insurance) private _insurances;
    mapping(address => Customer)  private _customers;
    mapping(string => bool)       private _registered;
    mapping(address => uint[])    private _userToInsurances;

    modifier auth() {
        _authenticate();
        _;
    }

    modifier notBanned() {
        _checkBanned();
        _;
    }

    constructor() { _owner = msg.sender; }

    receive() external payable {}

    /**
     * @notice Register as a customer 
     * @param name Name of the customer
     * @param nationalId national id number of customer
     * @param phoneNumber phone number of customer
     * @param birthYear birth year of customer
     * @param maritalStatus marital status of customer
     NOTE: Ensure the strings are non-empty. Contract does not check length to save gas
     */
    function register(
        string calldata name,
        string calldata nationalId,
        string calldata nationality,
        string calldata phoneNumber,
        uint240 birthYear,
        bool maritalStatus
    ) external {
        require(_customers[msg.sender].birthYear == 0, "already registered");

        _customers[msg.sender] = Customer(
            name,
            nationalId,
            nationality,
            phoneNumber,
            birthYear,
            maritalStatus,
            false
        );
    }

    /**
     * @notice Create new insurance
     * @param numberPlate number plate of the car
     * @param brand brand name of the car
     * @param engineCapacity cc of the car
     * @param registrationYear reg year of the car
     * @param insurancePeriodInYears number of years the insurance should remain active
     * @param electric true/false value of whether the car is electric
     * @param plan type of plan (0/1/2)
     */
    function createInsurance(
        string calldata numberPlate,
        string calldata brand,
        uint256 engineCapacity,
        uint256 registrationYear,
        uint256 insurancePeriodInYears,
        bool electric,
        Plan plan
    ) external notBanned {
        require(_customers[msg.sender].birthYear > 0, "unregistered");
        require(!_registered[numberPlate], "car already insured");
        require(plan == Plan.TPO || plan == Plan.TPFT || plan == Plan.CC, "invalid plan");

        _registered[numberPlate] = true;

        unchecked {
            ++_counter;
        }

        _insurances[_counter] = Insurance(
            engineCapacity,
            registrationYear,
            1970 + block.timestamp / 365 days,
            insurancePeriodInYears,
            0,
            numberPlate,
            brand,
            msg.sender,
            plan,
            electric,
            false
        );

        _userToInsurances[msg.sender].push(_counter);
    }  
    
    /**
     * @notice Claim insurance and receive payout
     * @param insuranceId insurance id to claim for
     * @param estimatedDamage value to receive for payout
     * @param accidentDate date of accident DD/MM/YY or MM/DD/YY 
     * @param documentUrl url of pdf form to claim insurance
     */
    function claimInsurance(
        uint insuranceId, 
        uint estimatedDamage,
        string calldata accidentDate, 
        string calldata documentUrl
    ) external notBanned {
        Insurance memory ins = _insurances[insuranceId];
        require(msg.sender == ins.customer, "invalid caller");
        require(!ins.claimed, "Claimed");
        require(bytes(accidentDate).length > 0 && bytes(documentUrl).length > 0 && estimatedDamage > 0, "all fields needed");
        uint256 currentYear = 1970 + block.timestamp / 365 days;
        require(currentYear <= ins.startYear + ins.insurancePeriodInYears, "insurance period expired");

        _insurances[insuranceId].claimed = true;
        uint256 maxPayout;

        if(ins.plan == Plan.TPO)
            maxPayout = TPO_MAX_PAYOUT;
        else if(ins.plan == Plan.TPFT)
            maxPayout = TPFT_MAX_PAYOUT;
        else 
            maxPayout = CC_MAX_PAYOUT;

        require(maxPayout >= estimatedDamage, "exceeding max payout");

        (bool sent, ) = payable(msg.sender).call{value: estimatedDamage}("");
        require(sent, "transfer failed");
    
    }   
    
    /**
     * @notice Pay monthly premium for current month
     * @param insuranceId insurance id to pay premium for
     * NOTE: Value provided with the tx must be equal to the monthly premium amount for given ìnsurance id
     */
    function payMonthlyPremium(uint256 insuranceId) external payable {
        require(msg.sender == _insurances[insuranceId].customer, "invalid caller");
        require(block.timestamp - _insurances[insuranceId].lastPaidTimestamp >= 30 days, "already paid this month");

        uint256 amount;
        Plan p = _insurances[insuranceId].plan;

        if(p == Plan.TPO)
            amount = TPO_MONTHLY_PREMIUM;
        else if(p == Plan.TPFT)
            amount = TPFT_MONTHLY_PREMIUM;
        else 
            amount = CC_MONTHLY_PREMIUM;

        assert(msg.value == amount);

        _insurances[insuranceId].lastPaidTimestamp = block.timestamp;
    }

    function _checkBanned() private view {
        require(!_customers[msg.sender].banned, "banned");
    }

    /* --- Getters --- */

    function hasBeenRegistered(string calldata numberPlate) external view returns (bool) {
        return _registered[numberPlate];
    }

    function getCustomerInformation(address customer) external view returns (Customer memory) {
        return _customers[customer];
    }

    function getUserInsurances(address customer) external view returns (uint[] memory ) {
        return _userToInsurances[customer];
    }

    function getInsuranceInformation(uint256 insuranceId) external view returns (Insurance memory) {
        return _insurances[insuranceId];
    }

    function totalInsurances() external view returns (uint256) {
        return _counter;
    }   

    /* --- | ADMIN ONLY | --- */

    function _authenticate() private view {
        require(msg.sender == _owner, "unauthorized");
    }
    
    /**
     * @notice Ban a user who has not paid monthly premium in over 30 days
     * @param insuranceId insurance id that has been unpaid for over 30 days
     * NOTE: Once banned, the customer will not be able to claim insurance or create new insurance
     */
    function ban(uint256 insuranceId) external auth {
        require(
            block.timestamp - _insurances[insuranceId].lastPaidTimestamp >= 30 days,
            "paid within 30 days"
        );

        _customers[_insurances[insuranceId].customer].banned = true;
    }

    /**
     * @notice Unban a customer
     * @param customer address of customer to unban
     */
    function unban(address customer) external auth {
        _customers[customer].banned = false;
    }

    /**
     * @notice Transfers liquidity from this contract to contract owner
     */
    function withdraw() external auth {
        (bool sent, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(sent, "transfer failed");
    }

}
