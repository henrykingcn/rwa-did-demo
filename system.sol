// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// ================= 1. 代币合约 (含创世分配) =================
contract HKCoin is ERC20, Ownable {
    using SafeERC20 for IERC20;

    // 分配地址
    address public ecosystemWallet;
    address public complianceReserve;
    address public teamVestingContract;
    address public issuerStakingPool;

    constructor(
        address _ecosystem, 
        address _compliance, 
        address _vesting, 
        address _staking
    ) ERC20("Hong Kong Coin", "HKC") Ownable(msg.sender) {
        uint256 total = 1_000_000_000 * 10**18; // 10亿

        // 1. 生态系统激励 (30%)
        _mint(_ecosystem, total * 30 / 100);
        // 2. 合规储备金 (20%)
        _mint(_compliance, total * 20 / 100);
        // 3. 技术团队锁仓 (15%)
        _mint(_vesting, total * 15 / 100);
        // 4. 机构节点质押池 (10%)
        _mint(_staking, total * 10 / 100);
        // 5. 市场流通 (25%) -> 给 Root 方便加池子
        _mint(msg.sender, total * 25 / 100);
    }
}

// ================= 2. 团队锁仓合约 =================
contract TeamVesting is Ownable {
    IERC20 public token;
    address public beneficiary;
    uint256 public startTime;
    uint256 public duration = 730 days; // 2年
    uint256 public totalAmount;
    uint256 public released;

    constructor(IERC20 _token, address _beneficiary, uint256 _amount) Ownable(msg.sender) {
        token = _token;
        beneficiary = _beneficiary;
        totalAmount = _amount;
        startTime = block.timestamp;
    }

    function release() external {
        require(msg.sender == beneficiary, "Not beneficiary");
        uint256 vested = _vestedAmount();
        uint256 claimable = vested - released;
        require(claimable > 0, "Nothing to claim");

        released += claimable;
        token.transfer(beneficiary, claimable);
    }

    function _vestedAmount() internal view returns (uint256) {
        if (block.timestamp < startTime) return 0;
        if (block.timestamp >= startTime + duration) return totalAmount;
        return (totalAmount * (block.timestamp - startTime)) / duration;
    }
}

// ================= 3. 身份与治理合约 (含收费/质押) =================
contract HierarchicalIdentity is Ownable {
    IERC20 public hkcToken;
    address public complianceReserve; // 费用接收地址

    // 费率配置
    uint256 public constant FEE_GOV_PROPOSAL = 50 * 10**18; // 提案费
    uint256 public constant FEE_ID_ISSUE = 5 * 10**18;      // 发证费
    uint256 public constant STAKE_NEW_ORG = 10_000 * 10**18; // 建机构质押

    struct Issuer { 
        bool isActive; 
        bool isPaused; 
        string name; 
        string scope;   
        address parent; 
        uint256 stakedAmount; // 质押金额
    }
    
    struct Identity { 
        address issuedBy; 
        string region; 
        string role; 
        uint256 expiry; 
        bool isValid; 
    }

    struct GovProposal {
        uint256 id;
        uint8 actionType; // 1=AddAdmin, 2=AddChildOrg, 3=TogglePause, 4=RevokeID
        address targetAddr; 
        address targetOrg;  
        string payloadName; 
        string payloadScope;
        address proposer;
        bool executed;
    }
    
    struct IDProposal {
        uint256 id;
        address targetUser;
        string region;
        string role;
        uint256 validityDays;
        address proposer;
        bool executed;
    }

    mapping(address => Issuer) public issuers;
    mapping(address => Identity) public identities;
    mapping(address => address) public adminOrg; 

    address[] public issuerList; 
    address[] public adminList;  
    mapping(address => address[]) public orgUsers; 

    mapping(uint256 => GovProposal) public govProposals;
    uint256 public govProposalCount;

    mapping(uint256 => IDProposal) public idProposals;
    uint256 public idProposalCount;

    event IssuerModified(address indexed issuer, string status);
    event IdentityIssued(address indexed user, address indexed issuer, string region);
    event IdentityRevoked(address indexed user, address indexed revoker);
    event ProposalCreated(string pType, uint256 id, address proposer);
    event ProposalExecuted(string pType, uint256 id, address executor);

    constructor(address _token, address _reserve) Ownable(msg.sender) {
        hkcToken = IERC20(_token);
        complianceReserve = _reserve;

        // Root 初始化
        issuers[msg.sender] = Issuer(true, false, "HK Government Root", "Global", address(0), 0);
        issuerList.push(msg.sender);
        _addAdminInternal(msg.sender, msg.sender); 
    }

    // ================= Root God Mode (免费) =================
    function rootAddIssuer(address _issuer, string calldata _name, string calldata _scope, address _parent) external onlyOwner {
        _createIssuerInternal(_issuer, _name, _scope, _parent);
    }
    function rootAddAdmin(address _admin, address _org) external onlyOwner {
        _addAdminInternal(_admin, _org);
    }
    function rootToggleIssuerPause(address _issuer, bool _pause) external onlyOwner {
        require(issuers[_issuer].isActive, "Not active");
        issuers[_issuer].isPaused = _pause;
        emit IssuerModified(_issuer, _pause ? "Paused" : "Unpaused");
    }
    function rootRevokeIdentity(address _user) external onlyOwner {
        identities[_user].isValid = false;
        emit IdentityRevoked(_user, msg.sender);
    }
    function rootIssue(address _user, string calldata _region, string calldata _role, uint256 _validityDays) external onlyOwner {
        _internalIssue(_user, _region, _role, _validityDays, msg.sender);
    }

    // ================= Gov Logic (收费 & 质押) =================
    function _hasGovAuth(address _user, address _targetOrg) internal view returns (bool) {
        if (_user == owner()) return true;
        address userOrg = adminOrg[_user];
        if (userOrg == address(0)) return false;
        if (userOrg == _targetOrg) return true;
        address parent = issuers[_targetOrg].parent; 
        if (userOrg == parent) return true;
        return false;
    }

    function proposeGovAction(uint8 _type, address _targetAddr, address _targetOrg, string calldata _name, string calldata _scope) external {
        address myOrg = adminOrg[msg.sender];
        require(myOrg != address(0), "Not Admin");
        require(issuers[myOrg].isActive && !issuers[myOrg].isPaused, "Org inactive/paused");

        // 🔥 收费逻辑
        if (_type == 2) { 
            // 建机构：质押 10,000 HKC (锁在合约里)
            require(hkcToken.transferFrom(msg.sender, address(this), STAKE_NEW_ORG), "Stake Failed");
        } else {
            // 其他提案：支付 50 HKC (给储备金)
            require(hkcToken.transferFrom(msg.sender, complianceReserve, FEE_GOV_PROPOSAL), "Fee Failed");
        }

        if (_type == 1) { 
            require(_hasGovAuth(msg.sender, _targetOrg), "No Auth");
        } 
        else if (_type == 2) { 
            string memory parentScope = issuers[myOrg].scope;
            if (keccak256(bytes(parentScope)) != keccak256(bytes("Global"))) {
                require(keccak256(bytes(parentScope)) == keccak256(bytes(_scope)), "Scope restricted");
            }
        }
        else if (_type == 3) { 
            require(_hasGovAuth(msg.sender, _targetOrg), "No Auth");
        }
        else if (_type == 4) { 
            address userIssuer = identities[_targetAddr].issuedBy;
            require(_hasGovAuth(msg.sender, userIssuer), "No Auth to Revoke");
        }

        govProposalCount++;
        govProposals[govProposalCount] = GovProposal(govProposalCount, _type, _targetAddr, _targetOrg, _name, _scope, msg.sender, false);
        emit ProposalCreated("GOV", govProposalCount, msg.sender);
    }

    function approveGovAction(uint256 _id) external {
        GovProposal storage p = govProposals[_id];
        require(!p.executed, "Executed");
        require(p.proposer != msg.sender, "Need 2 different admins");
        
        address targetContext;
        if (p.actionType == 1 || p.actionType == 3) targetContext = p.targetOrg;
        else if (p.actionType == 2) targetContext = adminOrg[p.proposer]; 
        else if (p.actionType == 4) targetContext = identities[p.targetAddr].issuedBy;

        require(_hasGovAuth(msg.sender, targetContext), "No Auth to Approve");

        p.executed = true;

        if (p.actionType == 1) {
            _addAdminInternal(p.targetAddr, p.targetOrg); 
        } else if (p.actionType == 2) {
            address parentOrg = adminOrg[p.proposer];
            _createIssuerInternal(p.targetAddr, p.payloadName, p.payloadScope, parentOrg);
            // 记录质押
            issuers[p.targetAddr].stakedAmount = STAKE_NEW_ORG;
        } else if (p.actionType == 3) {
            bool isPause = (keccak256(bytes(p.payloadName)) == keccak256(bytes("true")));
            issuers[p.targetOrg].isPaused = isPause;
            emit IssuerModified(p.targetOrg, isPause ? "Paused" : "Unpaused");
        } else if (p.actionType == 4) {
            identities[p.targetAddr].isValid = false;
            emit IdentityRevoked(p.targetAddr, msg.sender);
        }
        emit ProposalExecuted("GOV", _id, msg.sender);
    }

    // ================= ID MultiSig (收费) =================
    function proposeIdentity(address _user, string calldata _region, string calldata _role, uint256 _validityDays) external {
        address org = adminOrg[msg.sender];
        require(org != address(0), "Not Admin");
        
        // 🔥 发证费: 5 HKC
        require(hkcToken.transferFrom(msg.sender, complianceReserve, FEE_ID_ISSUE), "ID Fee Failed");

        string memory scope = issuers[org].scope;
        if (keccak256(bytes(scope)) != keccak256(bytes("Global"))) {
            require(keccak256(bytes(scope)) == keccak256(bytes(_region)), "Region out of scope");
        }
        idProposalCount++;
        idProposals[idProposalCount] = IDProposal(idProposalCount, _user, _region, _role, _validityDays, msg.sender, false);
        emit ProposalCreated("ID", idProposalCount, msg.sender);
    }

    function approveIdentity(uint256 _id) external {
        IDProposal storage p = idProposals[_id];
        require(!p.executed, "Executed");
        require(p.proposer != msg.sender, "Cannot approve self");
        address org = adminOrg[msg.sender];
        require(org == adminOrg[p.proposer], "Not same org");

        p.executed = true;
        _internalIssue(p.targetUser, p.region, p.role, p.validityDays, org);
        emit ProposalExecuted("ID", _id, msg.sender);
    }

    // ================= Helpers =================
    function _createIssuerInternal(address _issuer, string memory _name, string memory _scope, address _parent) internal {
        if (!issuers[_issuer].isActive) {
            issuerList.push(_issuer);
        }
        issuers[_issuer] = Issuer(true, false, _name, _scope, _parent, 0);
        _addAdminInternal(_issuer, _issuer); 
        emit IssuerModified(_issuer, "Created");
    }

    function _addAdminInternal(address _admin, address _org) internal {
        require(issuers[_org].isActive, "Org not active");
        adminOrg[_admin] = _org;
        adminList.push(_admin);
    }

    function _internalIssue(address _user, string memory _region, string memory _role, uint256 _days, address _issuer) internal {
        identities[_user] = Identity(_issuer, _region, _role, block.timestamp + (_days * 1 days), true);
        orgUsers[_issuer].push(_user);
        emit IdentityIssued(_user, _issuer, _region);
    }

    function checkCompliance(address _user, string calldata _reqRegion, address _reqIssuer) external view returns (bool, string memory) {
        address userOrg = adminOrg[_user];
        if (userOrg != address(0)) {
            Issuer memory orgInfo = issuers[userOrg];
            if (!orgInfo.isActive) return (false, "Admin's Org Revoked");
            if (orgInfo.isPaused) return (false, "Admin's Org Paused");
            if (keccak256(bytes(orgInfo.scope)) == keccak256(bytes("NK"))) return (false, "Sanctioned Region (NK)");
            return (true, "Admin Pass");
        }

        Identity memory id = identities[_user];
        if (!id.isValid) return (false, "Identity Invalid"); 
        if (block.timestamp > id.expiry) return (false, "Identity Expired");
        
        Issuer memory issuer = issuers[id.issuedBy];
        if (!issuer.isActive) return (false, "Issuer Revoked");
        if (issuer.isPaused) return (false, "Issuer Paused");
        if (keccak256(bytes(id.region)) == keccak256(bytes("NK"))) return (false, "Sanctioned Region (NK)");

        if (bytes(_reqRegion).length > 0 && keccak256(bytes(id.region)) != keccak256(bytes(_reqRegion))) return (false, "Region Mismatch");
        if (_reqIssuer != address(0) && id.issuedBy != _reqIssuer) return (false, "Issuer Restricted");

        return (true, "Success");
    }

    // Views
    function getIssuerInfo(address _issuer) external view returns (Issuer memory) { return issuers[_issuer]; }
    function getAdminOrg(address _admin) external view returns (address) { return adminOrg[_admin]; }
    function getAllIssuers() external view returns (address[] memory) { return issuerList; }
    function getOrgUsers(address _org) external view returns (address[] memory) { return orgUsers[_org]; }
    function getGovProposal(uint256 _id) external view returns (GovProposal memory) { return govProposals[_id]; }
    function getIDProposal(uint256 _id) external view returns (IDProposal memory) { return idProposals[_id]; }
}

// ================= 4. 市场合约 (含交易挖矿 & 手续费) =================
contract ComplianceRWAMarket is Ownable {
    IERC20 public paymentToken;
    HierarchicalIdentity public idContract;
    address public ecosystemWallet; // 奖励池
    address public complianceReserve; // 手续费收入

    uint256 public constant LISTING_FEE = 200 * 10**18;
    uint256 public constant TRADING_REWARD = 1 * 10**18; // 每次购买奖励 1 HKC
    
    struct Asset { string name; uint256 price; string requiredRegion; address requiredIssuer; bool isActive; bool isPaused; }
    
    mapping(uint256 => Asset) public assets;
    uint256 public assetCount;
    mapping(address => mapping(uint256 => uint256)) public userBalances;
    
    event TradeExecuted(address indexed user, string type_, uint256 assetId, string assetName, uint256 price, uint256 timestamp);

    constructor(address _paymentToken, address _idContract, address _ecosystem, address _compliance) Ownable(msg.sender) {
        paymentToken = IERC20(_paymentToken);
        idContract = HierarchicalIdentity(_idContract);
        ecosystemWallet = _ecosystem;
        complianceReserve = _compliance;
    }
    
    function _hasAssetControl(address _user, uint256 _assetId) internal view returns (bool) {
        if (_user == owner()) return true; 
        address assetIssuer = assets[_assetId].requiredIssuer;
        address userOrg = idContract.getAdminOrg(_user); 
        if (userOrg == address(0)) return false;
        if (userOrg == assetIssuer) return true;
        address current = assetIssuer;
        while (current != address(0)) {
            (,,,, address parent,) = idContract.issuers(current); // 6返回参数
            if (userOrg == parent) return true;
            current = parent;
        }
        return false;
    }

    function addAsset(string calldata _name, uint256 _price, string calldata _region, address _issuer) external {
        if (msg.sender != owner()) {
            require(idContract.getAdminOrg(msg.sender) == _issuer, "Only issue for own org");
            // 🔥 上架费
            require(paymentToken.transferFrom(msg.sender, complianceReserve, LISTING_FEE), "Listing Fee Failed");
        }
        assetCount++; 
        assets[assetCount] = Asset(_name, _price, _region, _issuer, true, false);
    }
    
    function setAssetStatus(uint256 _assetId, bool _status) external { 
        require(_hasAssetControl(msg.sender, _assetId), "Unauthorized");
        assets[_assetId].isActive = _status; 
    }

    function setAssetPause(uint256 _assetId, bool _status) external {
        require(_hasAssetControl(msg.sender, _assetId), "Unauthorized");
        assets[_assetId].isPaused = _status;
    }

    function buyAsset(uint256 _assetId) external {
        Asset memory asset = assets[_assetId]; 
        require(asset.isActive, "Inactive");
        require(!asset.isPaused, "Paused");
        (bool compliant, string memory reason) = idContract.checkCompliance(msg.sender, asset.requiredRegion, asset.requiredIssuer);
        require(compliant, reason); 

        uint256 totalPrice = asset.price * 10**18;
        uint256 fee = totalPrice * 2 / 100; // 2% Fee
        uint256 sellerAmount = totalPrice - fee;

        // 检查
        require(paymentToken.allowance(msg.sender, address(this)) >= totalPrice, "Allowance Low");
        require(paymentToken.balanceOf(msg.sender) >= totalPrice, "Balance Low");

        // 资金划转
        require(paymentToken.transferFrom(msg.sender, complianceReserve, fee), "Fee Transfer Failed");
        require(paymentToken.transferFrom(msg.sender, address(this), sellerAmount), "Payment Failed"); 
        // 注：Demo中简化为钱进合约，实际应该是进 Seller 钱包。这里假设合约是托管方。

        // 🔥 交易挖矿 (尝试发放奖励，如果池子没钱或没授权则跳过)
        if (paymentToken.balanceOf(ecosystemWallet) >= TRADING_REWARD && 
            paymentToken.allowance(ecosystemWallet, address(this)) >= TRADING_REWARD) {
            try paymentToken.transferFrom(ecosystemWallet, msg.sender, TRADING_REWARD) {} catch {}
        }

        userBalances[msg.sender][_assetId] += 1;
        emit TradeExecuted(msg.sender, "BUY", _assetId, asset.name, asset.price, block.timestamp);
    }

    function sellAsset(uint256 _assetId) external {
        require(userBalances[msg.sender][_assetId] > 0, "No asset");
        Asset memory asset = assets[_assetId];
        require(!asset.isPaused, "Paused");

        (bool compliant, string memory reason) = idContract.checkCompliance(msg.sender, asset.requiredRegion, asset.requiredIssuer);
        require(compliant, reason);

        uint256 refund = (asset.price * 10**18) * 98 / 100; // 卖出也扣 2% 或者原价退？这里按 98% 退
        require(paymentToken.balanceOf(address(this)) >= refund, "Liquidity low");
        
        userBalances[msg.sender][_assetId] -= 1;
        require(paymentToken.transfer(msg.sender, refund), "Refund failed");
        emit TradeExecuted(msg.sender, "SELL", _assetId, asset.name, asset.price, block.timestamp);
    }
}