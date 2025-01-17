// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

// Open Zeppelin libraries for controlling upgradability and access.
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

// MerkleDistributor for airdrop to BTFS staker
contract BtfsAirdrop is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;

    bytes32 public merkleRoot;
    bytes32 public pendingMerkleRoot;
    uint256 public increaseTotalAmount;
    uint256 public pendingIncreaseTotalAmount;
    uint256 public lastTime;

    // admin address which can propose adding a new merkle root
    address public proposalAuthority;
    // admin address which approves or rejects a proposed merkle root
    address public reviewAuthority;
    // admin address which can withdraw all contract balance
    address public superAuthority;

    struct statistics {
        uint256 total;
        uint256 claimed;
    }

    statistics  public totalInfo;
    // TODO: change the datastruct to a map
    struct claimedUser {
        bytes32 lastMerkleRoot;
        uint256 claimed;
    }
    mapping(address => claimedUser) private claimedUserMap;
    uint8 public claimAvailable;

    event Claimed(bytes32 merkleRootInput, address account, uint256 amount);
    event SetTotalAmount(bytes32 merkleRoot, uint256 amount);
    event AddTotalAmount(bytes32 merkleRoot, uint256 increateAmount);
    event WithdrawAllBalance(address account, uint256 amount);

    // initialize
    function initialize(address _proposalAuthority, address _reviewAuthority, address _superAuthor) public initializer {
        proposalAuthority = _proposalAuthority;
        reviewAuthority = _reviewAuthority;
        superAuthority = _superAuthor;
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
    
    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // receive()
    receive() external payable {}


    function setProposalAuthority(address _account) public {
        require(msg.sender == proposalAuthority, "you can not set proposal authority.");
        proposalAuthority = _account;
    }
    function setReviewAuthority(address _account) public {
        require(msg.sender == reviewAuthority, "you can not set review authority.");
        reviewAuthority = _account;
    }
    function setSuperAuthority(address _account) public {
        require(msg.sender == superAuthority, "you can not set super authority.");
        superAuthority = _account;
    }

    // super authority withdraw all balance.
    // TODO: 大额资金建议加上时间延迟函数
    function withdrawAllBalance() external {
        require(msg.sender == superAuthority, "withdrawAmount: you are not super authority.");
        payable(msg.sender).transfer(address(this).balance);

        emit WithdrawAllBalance(msg.sender, address(this).balance);
    }

    function setClaimAvailable() public {
        require(msg.sender == reviewAuthority, "you can not set claim available.");
        claimAvailable = 1;
    }
    function setClaimNotAvailable() public {
        require(msg.sender == reviewAuthority, "you can not set claim available.");
        claimAvailable = 0;
    }
    function getClaimAvailable() view public returns(uint8) {
        return claimAvailable;
    }

    // every day, the proposal authority calls to submit the merkle root for a new airdrop.
    function proposeMerkleRoot(bytes32 _merkleRoot, uint256 _increaseTotalAmount) public {
        require(msg.sender == proposalAuthority, "proposeMerkleRoot: msg.sender != proposalAuthority");
        require(_merkleRoot != 0x00, "proposeMerkleRoot: _merkleRoot == 0x00");
        require(pendingMerkleRoot == 0x00, "proposeMerkleRoot: pendingMerkleRoot != 0x00");
        require(_merkleRoot != merkleRoot, "proposeMerkleRoot: merkleRoot is already used.");
        //require(block.timestamp >= lastRoot + 86400, "proposeMerkleRoot: it takes 1 day to modify it.");
        require(_increaseTotalAmount > 0, "proposeMerkleRoot: _increaseTotalAmount <= 0");

        pendingMerkleRoot = _merkleRoot;
        pendingIncreaseTotalAmount = _increaseTotalAmount;
    }

    // After validating the correctness of the pending merkle root, the reviewing authority
    // calls to confirm it and the distribution may begin.
    // 这个 reviewPendingMerkleRoot 只是为了多一道审核？那审核人具体能怎么审核呢？
    function reviewPendingMerkleRoot(bool _approved) public {
        require(msg.sender == reviewAuthority, "msg.sender != reviewAuthority");
        require(pendingMerkleRoot != 0x00, "pendingMerkleRoot != 0x00");

        if (_approved) {
            merkleRoot = pendingMerkleRoot;

            increaseTotalAmount = pendingIncreaseTotalAmount;
            totalInfo.total += increaseTotalAmount;
            emit AddTotalAmount(merkleRoot, increaseTotalAmount);
            // TODO: Why?
            lastTime = block.timestamp / 86400 * 86400;
        }
        delete pendingMerkleRoot;
    }

    // set the total amount of airdrop this period
    // TODO: deprecated
    function setTotalAmount(uint256 totalAmount) public onlyOwner {
        require(totalAmount > totalInfo.total, "totalAmount is less than totalInfo.total");
        totalInfo.total = totalAmount;

        emit SetTotalAmount(merkleRoot, totalAmount);
    }

    function getTotalClaimInfo() view external returns (uint256 total, uint256 claimed, bytes32 curMerkleRoot) {
        total = totalInfo.total;
        claimed = totalInfo.claimed;
        curMerkleRoot = merkleRoot;
    }

    function getUserClaimed() view external returns (uint256 userClaimed, bytes32 lastMerkleRoot) {
        userClaimed = claimedUserMap[msg.sender].claimed;
        lastMerkleRoot = claimedUserMap[msg.sender].lastMerkleRoot;
    }

    function isUserClaimed(bytes32 merkleRootInput) public view returns (bool) {
        if (claimedUserMap[msg.sender].lastMerkleRoot == 0x00) {
            return false;
        }
        if (claimedUserMap[msg.sender].lastMerkleRoot == merkleRootInput) {
            return true;
        }

        return false;
    }

    function _setTotalClaimed(uint256 transferAmount) private {
        totalInfo.claimed = totalInfo.claimed.add(transferAmount);
    }

    function _setUserClaimed(uint256 amount) private {
        claimedUserMap[msg.sender].claimed = amount;
        claimedUserMap[msg.sender].lastMerkleRoot = merkleRoot;
    }

    function _getUserTransferAmount(uint256 amount) private view returns (uint256) {
        return amount.sub(claimedUserMap[msg.sender].claimed);
    }

    function claim(bytes32 root, uint256 amount, bytes32[] calldata merkleProof) external {
        require(0 < claimAvailable, "claim: the current status is not available.");

        require(0 < merkleProof.length, "claim: Invalid merkleProof");
        require(root == merkleRoot, "claim: Invalid merkleRoot");
        require(!isUserClaimed(root), "claim: Drop already claimed.");

        // Verify the merkle proof1 with msg.sender.
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(MerkleProof.verify(merkleProof, root, leaf), "claim: Invalid proof1.");

        // get transfer amount
        uint256 transferAmount = _getUserTransferAmount(amount);
        require(0 < transferAmount, "claim: transfer amount should be greater than 0.");

        // transfer to msg.sender
        payable(msg.sender).transfer(transferAmount);

        // set claimed amount
        _setTotalClaimed(transferAmount);
        _setUserClaimed(amount);

        emit Claimed(root, msg.sender, transferAmount);
    }
}