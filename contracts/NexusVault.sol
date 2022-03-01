// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./interfaces/INexus.sol";
import "./interfaces/INexusEcosystem.sol";

/// @custom:security-contact security@nexusdao.money
contract NexusVault is ERC721Holder, Ownable {
    mapping(uint256 => uint256) public tokenIdToTimestamp;
    mapping(uint256 => address) public tokenIdToStaker;
    mapping(address => uint256[]) public stakerToTokenIds;
    mapping(address => uint256) public reflections;

    address public distributor;
    uint256 public nextDistributionIn;
    uint256 public distributeOnceIn = 1 days;
    uint256 public totalDistributed;

    uint256 public maxPerWallet = 100;

    address[] public shareholders;
    uint256[] public shares;
    uint256 public totalShares;

    mapping(address => bool) public isShareCalculated;
    bool public isDataCalculated;

    INexus public NXS;
    INexusEcosystem public ecosystem;

    //
    // Modifiers
    //

    modifier whenNotBlacklisted() {
        require(
            !NXS.isInBlacklist(_msgSender()),
            "NexusVault: blacklisted address"
        );
        _;
    }

    modifier onlyDistributor() {
        require(
            _msgSender() == distributor,
            "NexusVault: unauthorized address"
        );
        _;
    }

    modifier whenNotDistributing() {
        require(!isDataCalculated, "NexusVault: distribution in progress");
        _;
    }

    //
    // Events
    //

    event AVAXDistributed(uint256 amount, address to);
    event AVAXReceived(uint256 amount, address from);

    event TokenStaked(uint256 tokenId);
    event TokenUnstaked(uint256 tokenId);
    event RewardsClaimed(uint256 amount, address by);

    event NXSAddressUpdated(address from, address to);
    event EcosystemAddressUpdated(address from, address to);

    //
    // Constructor
    //

    constructor(address _NXS, address _ecosystem) {
        NXS = INexus(_NXS);
        ecosystem = INexusEcosystem(_ecosystem);

        distributor = _msgSender();
        nextDistributionIn = block.timestamp + distributeOnceIn;
    }

    receive() external payable {
        emit AVAXReceived(msg.value, _msgSender());
    }

    function withdraw() external onlyOwner {
        Address.sendValue(payable(_msgSender()), address(this).balance);
    }

    //
    // Getters
    //

    function getTokensOf(address staker)
        external
        view
        returns (uint256[] memory)
    {
        return stakerToTokenIds[staker];
    }

    function getTokenRewards(uint256 tokenId) public view returns (uint256) {
        return
            ecosystem.ownerOf(tokenId) != address(this)
                ? 0
                : (block.timestamp - tokenIdToTimestamp[tokenId]) *
                    ecosystem.getTokenEmissionRate(tokenId);
    }

    function getAllRewards(address staker) public view returns (uint256) {
        uint256[] memory tokenIds = stakerToTokenIds[staker];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalRewards += getTokenRewards(tokenIds[i]);
        }

        return totalRewards;
    }

    //
    // Setters
    //

    function setDistributorAddress(address account) external onlyOwner {
        distributor = account;
    }

    function setNextDistributionIn(uint256 timestamp) external onlyOwner {
        nextDistributionIn = timestamp;
    }

    function setDistributeOnceIn(uint256 time) external onlyOwner {
        distributeOnceIn = time;
    }

    function setMaxPerWallet(uint256 limit) external onlyOwner {
        maxPerWallet = limit;
    }

    function setNXSAddress(address _NXS) external onlyOwner {
        emit NXSAddressUpdated(address(NXS), _NXS);
        NXS = INexus(_NXS);
    }

    function setEcosystemAddress(address _ecosystem) external onlyOwner {
        emit EcosystemAddressUpdated(address(ecosystem), _ecosystem);
        ecosystem = INexusEcosystem(_ecosystem);
    }

    //
    // Distribution functions
    //

    function calcDistributionData() external {
        require(
            block.timestamp >= (nextDistributionIn - 30 minutes),
            "NexusVault: try again later"
        );

        shareholders = new address[](0);
        shares = new uint256[](0);
        totalShares = 0;

        for (uint256 i = 0; i < ecosystem.balanceOf(address(this)); i++) {
            uint256 tokenId = ecosystem.tokenOfOwnerByIndex(address(this), i);
            address ownedBy = tokenIdToStaker[tokenId];

            if (!isShareCalculated[ownedBy]) {
                isShareCalculated[ownedBy] = true;

                uint256 ownerRewards = getAllRewards(ownedBy);
                totalShares += ownerRewards;

                shareholders.push(ownedBy);
                shares.push(ownerRewards);
            }
        }

        isDataCalculated = true;
    }

    function resetCalculatedData() external onlyOwner {
        shareholders = new address[](0);
        shares = new uint256[](0);
        totalShares = 0;

        isDataCalculated = false;
    }

    function distribute() external onlyDistributor {
        require(isDataCalculated, "NexusVault: data not calculated");

        require(
            block.timestamp >= nextDistributionIn,
            "NexusVault: try again later"
        );

        uint256 avaxBalance = address(this).balance;

        for (uint256 i = 0; i < shareholders.length; i++) {
            uint256 reflection = (shares[i] / totalShares) * avaxBalance;
            address payee = shareholders[i];

            emit AVAXDistributed(reflection, payee);

            Address.sendValue(payable(payee), reflection);
            reflections[payee] += reflection;
            isShareCalculated[payee] = false;
        }

        isDataCalculated = false;
        nextDistributionIn = block.timestamp + distributeOnceIn;
        totalDistributed += avaxBalance;
    }

    //
    // Stake/Unstake/Claim
    //

    function stake(uint256[] calldata tokenIds)
        external
        whenNotBlacklisted
        whenNotDistributing
    {
        require(
            stakerToTokenIds[_msgSender()].length + tokenIds.length <=
                maxPerWallet,
            "NexusVault: wallet limit reached"
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                ecosystem.ownerOf(tokenIds[i]) == _msgSender(),
                "NexusVault: owner and caller differ"
            );

            require(
                tokenIdToStaker[tokenIds[i]] == address(0),
                "NexusVault: token already staked"
            );

            emit TokenStaked(tokenIds[i]);

            ecosystem.safeTransferFrom(
                _msgSender(),
                address(this),
                tokenIds[i]
            );

            stakerToTokenIds[_msgSender()].push(tokenIds[i]);
            tokenIdToTimestamp[tokenIds[i]] = block.timestamp;
            tokenIdToStaker[tokenIds[i]] = _msgSender();
        }
    }

    function unstake(uint256[] calldata tokenIds)
        external
        whenNotBlacklisted
        whenNotDistributing
    {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == _msgSender(),
                "NexusVault: owner and caller differ"
            );

            emit TokenUnstaked(tokenIds[i]);

            totalRewards += getTokenRewards(tokenIds[i]);
            _removeTokenIdFromStaker(_msgSender(), tokenIds[i]);
            tokenIdToStaker[tokenIds[i]] = address(0);

            ecosystem.safeTransferFrom(
                address(this),
                _msgSender(),
                tokenIds[i]
            );
        }

        emit RewardsClaimed(totalRewards, _msgSender());
        NXS.transfer(_msgSender(), totalRewards);
    }

    function claim(uint256[] calldata tokenIds)
        external
        whenNotBlacklisted
        whenNotDistributing
    {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == _msgSender(),
                "NexusVault: owner and caller differ"
            );

            totalRewards += getTokenRewards(tokenIds[i]);
            tokenIdToTimestamp[tokenIds[i]] = block.timestamp;
        }

        emit RewardsClaimed(totalRewards, _msgSender());
        NXS.transfer(_msgSender(), totalRewards);
    }

    //
    // Cleanup
    //

    function _remove(address staker, uint256 index) internal {
        if (index >= stakerToTokenIds[staker].length) return;

        for (uint256 i = index; i < stakerToTokenIds[staker].length - 1; i++) {
            stakerToTokenIds[staker][i] = stakerToTokenIds[staker][i + 1];
        }

        stakerToTokenIds[staker].pop();
    }

    function _removeTokenIdFromStaker(address staker, uint256 tokenId)
        internal
    {
        for (uint256 i = 0; i < stakerToTokenIds[staker].length; i++) {
            if (stakerToTokenIds[staker][i] == tokenId) {
                _remove(staker, i);
            }
        }
    }
}
