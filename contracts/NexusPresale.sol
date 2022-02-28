// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

import "./interfaces/INexus.sol";
import "./interfaces/INexusEcosystem.sol";

/// @custom:security-contact security@nexusdao.money
contract NexusPresale is Ownable, Pausable {
    uint256 public constant PRIVATE_SALE_PRICE = 1;
    uint256 public constant PUBLIC_SALE_PRICE = 2;

    uint256 public constant DECIMALS = 10**18;
    uint256 public constant MAX_SOLD = 100_000 * DECIMALS;
    uint256 public constant MAX_BUY_PER_ADDRESS = 500 * DECIMALS;
    uint256 public constant CAN_CLAIM_ONCE_IN = 1 days;

    uint256 public startTime;
    uint256 public endTime;

    bool public isAnnounced;
    bool public isPublicSale;
    bool public isClaimable;

    uint256 public claimablePerDay = 50 * DECIMALS;
    uint256 public totalSold;
    uint256 public totalOwed;

    mapping(address => uint256) public owed;
    mapping(address => uint256) public lastClaimedAt;
    mapping(address => bool) public isWhitelisted;

    IERC20 public constant MIM =
        IERC20(0x130966628846BFd36ff31a822705796e8cb8C18D);
    address public treasury;

    INexus public NXS;
    INexusEcosystem public ecosystem;

    //
    // Modifiers
    //

    modifier whenNotBlacklisted() {
        require(
            !NXS.isInBlacklist(_msgSender()),
            "NexusPresale: blacklisted address"
        );
        _;
    }

    modifier onlyEOA() {
        require(_msgSender() == tx.origin, "NexusPresale: not an EOA");
        _;
    }

    //
    // Events
    //

    event WhitelistUpdated(address account, bool value);
    event TokensBought(address account, uint256 amount, uint256 withMIM);
    event TokensClaimed(address account, uint256 amount);
    event NFTMinted(address by, uint256 tier, uint256 balance);

    //
    // Constructor
    //

    constructor(
        address _NXS,
        address _ecosystem,
        address _treasury
    ) {
        NXS = INexus(_NXS);
        ecosystem = INexusEcosystem(_ecosystem);
        treasury = _treasury;
    }

    //
    // Setters
    //

    function announceICO(uint256 _startTime, uint256 _endTime)
        external
        onlyOwner
    {
        isAnnounced = true;
        startTime = _startTime;
        endTime = _endTime;
    }

    function startPublicSale() external onlyOwner {
        isPublicSale = true;
    }

    function enableClaiming() external onlyOwner {
        require(
            isAnnounced && block.timestamp > endTime,
            "NexusPresale: presale not ended yet"
        );

        isClaimable = true;
    }

    function setClaimablePerDay(uint256 amount) external onlyOwner {
        claimablePerDay = amount * DECIMALS;
    }

    //
    // Whitelist functions
    //

    function addToWhitelist(address[] calldata accounts) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = true;
            emit WhitelistUpdated(accounts[i], true);
        }
    }

    function removeFromWhitelist(address[] calldata accounts)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = false;
            emit WhitelistUpdated(accounts[i], false);
        }
    }

    function updateWhitelist(address account, bool value) external onlyOwner {
        isWhitelisted[account] = value;
        emit WhitelistUpdated(account, value);
    }

    //
    // Main logic
    //

    function buyTokens(uint256 amount)
        external
        whenNotBlacklisted
        whenNotPaused
        onlyEOA
    {
        require(isAnnounced, "NexusPresale: not announced yet");

        require(
            block.timestamp > startTime,
            "NexusPresale: sale not started yet"
        );

        require(block.timestamp < endTime, "NexusPresale: sale ended");

        if (!isPublicSale) {
            require(
                isWhitelisted[_msgSender()],
                "NexusPresale: only whitelisted addresses allowed to buy in private sale"
            );
        }

        require(totalSold < MAX_SOLD, "NexusPresale: sold out");
        require(amount > 0, "NexusPresale: zero buy amount");

        require(
            owed[_msgSender()] + amount <= MAX_BUY_PER_ADDRESS,
            "NexusPresale: wallet limit reached"
        );

        uint256 price = isPublicSale ? PUBLIC_SALE_PRICE : PRIVATE_SALE_PRICE;
        uint256 remaining = MAX_SOLD - totalSold;

        if (amount > remaining) {
            amount = remaining;
        }

        uint256 amountInMIM = amount * price;

        MIM.transferFrom(_msgSender(), treasury, amountInMIM);

        owed[_msgSender()] += amount;
        totalSold += amount;
        totalOwed += amount;

        emit TokensBought(_msgSender(), amount, amountInMIM);
    }

    function claimTokens() external onlyEOA whenNotBlacklisted whenNotPaused {
        require(isClaimable, "NexusPresale: claiming not active");

        require(
            owed[_msgSender()] > 0,
            "NexusPresale: insufficient claimable balance"
        );

        require(
            block.timestamp > lastClaimedAt[_msgSender()] + CAN_CLAIM_ONCE_IN,
            "NexusPresale: already claimed once during permitted time"
        );

        lastClaimedAt[_msgSender()] = block.timestamp;

        uint256 claimableAmount = owed[_msgSender()];

        if (claimableAmount > claimablePerDay) {
            claimableAmount = claimablePerDay;
        }

        totalOwed -= claimableAmount;
        owed[_msgSender()] -= claimableAmount;

        NXS.transfer(_msgSender(), claimableAmount);

        emit TokensClaimed(_msgSender(), claimableAmount);
    }

    function mintFromInvested(uint256 tier, string calldata name)
        external
        onlyEOA
        whenNotBlacklisted
        whenNotPaused
    {
        require(isClaimable, "NexusPresale: presale not ended yet");

        uint256 price = ecosystem.getTierPrice(tier);

        require(
            owed[_msgSender()] >= price,
            "NexusPresale: insufficient presale balance"
        );

        totalOwed -= price;
        owed[_msgSender()] -= price;

        ecosystem.mint(_msgSender(), tier, name);
        emit NFTMinted(_msgSender(), tier, owed[_msgSender()]);
    }

    function withdrawTokens() external onlyOwner {
        require(totalOwed == 0, "NexusPresale: claim pending");
        NXS.transfer(_msgSender(), NXS.balanceOf(address(this)));
    }
}
