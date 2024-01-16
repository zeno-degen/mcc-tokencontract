// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "@openzeppelin/contracts/access/AccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";

import {IMCC} from "./interfaces/IMCC.sol";

error ZERO_ADDRESS();

contract MCC is ERC20, AccessControl, IMCC {
    using SafeERC20 for IERC20;

    /// @dev name
    string private constant _name = "MCC";

    /// @dev symbol
    string private constant _symbol = "Meme Capital Corp";

    /// @dev initial supply
    uint256 private constant INITIAL_SUPPLY = 1000000 ether; // 1M

    /// @notice percent multiplier (100%)
    uint256 public constant MULTIPLIER = 10000;

    /// @notice Uniswap router
    IUniswapV2Router02 public router;

    /// @notice tax info
    struct TaxInfo {
        uint256 buyFee;
        uint256 sellFee;
    }
    TaxInfo public taxInfo;
    uint256 private pendingTax;
    uint256 public maxWallet;
    uint256 public teamShare;

    address public marketingAddress;
    address public teamAddress;
    address public treasury;

    address public staking;
    address public node;

    uint256 public ETHPrice;
    uint256 public USDCPrice;

    address public USDCAddress;

    mapping(address => uint256) public tokenPrice;

    /// @notice whether a wallet excludes fees
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isDexAddress;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;

    bool private inSwap;
    bool public canBuy;

    uint256 public swapThreshold;
    uint256 public duration;
    uint256 public discount;
    uint256 public maxBuyAmountPerTx;

    struct User {
        uint256 start;
        uint256 purchased;
        uint256 claimed;
        uint256 end;
    }

    mapping(address => User) public userInfo;

    /* ======== INITIALIZATION ======== */

    constructor(
        IUniswapV2Router02 _router,
        address _usdc
    ) ERC20(_name, _symbol) {
        _mint(address(this), INITIAL_SUPPLY);
        USDCAddress = _usdc;
        router = _router;
        _approve(address(this), address(_router), type(uint256).max);
        isExcludedFromFee[address(this)] = true;
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    receive() external payable {}

    /* ======== MODIFIERS ======== */

    modifier onlyOwner() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    modifier onlyStaking() {
        require(staking != address(0) && node != address(0), "Invalid");

        require(
            staking == _msgSender() || node == _msgSender(),
            "permission denied"
        );
        _;
    }

    /* ======== POLICY FUNCTIONS ======== */
    function mint(address _receiver, uint256 _amount) external onlyStaking {
        _mint(_receiver, _amount);
    }

    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function setOwner(address _owner) external onlyOwner {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function setCanBuy(bool _status) external onlyOwner {
        canBuy = _status;
    }

    function buyWithETH(uint256 _amount) external payable {
        require(canBuy, "Cannot buy now");
        require(ETHPrice != 0, "Invalid Token");
        require(treasury != address(0), "Invalid Treasury");
        require(maxBuyAmountPerTx > _amount, "Limited MaxAmount PerTx");

        uint256 _price = (ETHPrice * _amount) / 1e18;

        require(msg.value >= _price, "Invalid amount");
        (bool sent, ) = treasury.call{value: msg.value}("");
        require(sent, "Failed to send Ether");

        claim();

        User storage user = userInfo[msg.sender];
        user.start = block.timestamp;
        user.purchased += _amount;
        user.end = duration + block.timestamp;
    }

    function buyWithUSDC(uint256 _amount) external {
        require(canBuy, "Cannot buy now");
        require(USDCPrice != 0, "Invalid Token");
        require(treasury != address(0), "Invalid Treasury");
        require(maxBuyAmountPerTx >= _amount, "Limited MaxAmount PerTx");

        uint256 _price = (USDCPrice * _amount) / 1e6;

        IERC20(USDCAddress).transferFrom(_msgSender(), treasury, _price);

        claim();

        User storage user = userInfo[_msgSender()];
        user.start = block.timestamp;
        user.purchased += _amount;
        user.end = duration + block.timestamp;
    }

    function claim() public {
        uint256 amount = claimable(msg.sender);
        if (amount > 0) {
            IERC20(address(this)).approve(_msgSender(), amount);
            IERC20(address(this)).transfer(_msgSender(), amount);
            User storage user = userInfo[msg.sender];
            user.claimed += amount;
            user.purchased -= amount;
            user.start = block.timestamp;
            // user.end = block.timestamp + duration;
        }
    }

    function claimable(address _user) public view returns (uint256) {
        User memory user = userInfo[_user];

        if (user.start == 0) {
            return 0;
        }

        if (block.timestamp >= user.end) {
            return user.purchased;
        }

        return ((user.purchased * timePassed(_user)) / (user.end - user.start));
    }

    function timePassed(address _user) public view returns (uint256) {
        User memory user = userInfo[_user];

        if (user.start == 0) {
            return 0;
        }
        return block.timestamp - user.start;
    }

    function burn(uint256 _amount) external override {
        _burn(msg.sender, _amount);
    }

    function setPrice(
        uint256 _ethPrice,
        uint256 _usdcPrice,
        uint256 _discount
    ) external onlyOwner {
        require(_ethPrice > 0 && _usdcPrice > 0, "Invalid price");
        ETHPrice = _ethPrice;
        USDCPrice = _usdcPrice;
        discount = _discount;
    }

    function setStaking(address _staking, address _node) external onlyOwner {
        staking = _staking;
        node = _node;
    }

    function setAddress(
        address _team,
        address _marketing,
        address _treasury
    ) external onlyOwner {
        teamAddress = _team;
        marketingAddress = _marketing;
        treasury = _treasury;
    }

    function setTaxFee(uint256 buyFee, uint256 sellFee) public onlyOwner {
        taxInfo.buyFee = buyFee;
        taxInfo.sellFee = sellFee;
    }

    function setMaxBuyAmountPerTx(uint256 _maxBuyAmountPerTx) public onlyOwner {
        maxBuyAmountPerTx = _maxBuyAmountPerTx;
    }

    function excludeFromFee(address account, bool isEx) external onlyOwner {
        isExcludedFromFee[account] = isEx;
    }

    function excludeFromMaxTransaction(
        address account,
        bool isEx
    ) public onlyOwner {
        require(account != address(0), "zero address");
        _isExcludedMaxTransactionAmount[account] = isEx;
    }

    function includeFromDexAddresss(
        address updAds,
        bool isEx
    ) public onlyOwner {
        require(updAds != address(0), "zero address");
        isDexAddress[updAds] = isEx;
    }

    function setSwapTaxSettings(
        uint256 _swapThreshold,
        uint256 _maxWallet,
        uint256 _teamShare
    ) public onlyOwner {
        swapThreshold = _swapThreshold;
        maxWallet = _maxWallet;
        teamShare = _teamShare;
    }

    function recoverERC20(IERC20 token) external onlyOwner {
        token.safeTransfer(_msgSender(), token.balanceOf(address(this)));
    }

    function recoverETH() external onlyOwner {
        require(teamAddress != address(0) && marketingAddress != address(0));

        uint256 balance = address(this).balance;

        if (balance > 0) {
            (bool success, ) = payable(teamAddress).call{
                value: (balance * teamShare) / MULTIPLIER
            }("");
            require(success);

            (bool _success, ) = payable(marketingAddress).call{
                value: address(this).balance
            }("");
            require(_success);
        }
    }

    function setUp() external payable onlyOwner {
        // add liquidity
        _transfer(
            msg.sender,
            address(this),
            (INITIAL_SUPPLY * 8500) / MULTIPLIER
        );
        router.addLiquidityETH{value: msg.value}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            msg.sender,
            block.timestamp
        );

        IUniswapV2Pair pair = IUniswapV2Pair(
            IUniswapV2Factory(router.factory()).getPair(
                address(this),
                router.WETH()
            )
        );
        setSwapTaxSettings(1000e18, INITIAL_SUPPLY / 100, 7000);
        includeFromDexAddresss(address(pair), true);
        setTaxFee(1500, 2000);
        excludeFromMaxTransaction(address(pair), true);
    }

    /* ======== PUBLIC FUNCTIONS ======== */

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        address owner = _msgSender();
        _transferWithTax(owner, to, amount);
        return true;
    }

    // function transferFrom(
    //     address from,
    //     address to,
    //     uint256 amount
    // ) public override returns (bool) {
    //     address spender = _msgSender();
    //     _spendAllowance(from, spender, amount);
    //     _transferWithTax(from, to, amount);
    //     return true;
    // }

    /* ======== INTERNAL FUNCTIONS ======== */

    function _transferWithTax(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (amount == 0) return;

        if (maxWallet != 0) {
            if (!_isExcludedMaxTransactionAmount[to]) {
                require(
                    amount + balanceOf(to) <= maxWallet,
                    "Max wallet exceeded"
                );
            }
        }

        if (isExcludedFromFee[from] || isExcludedFromFee[to]) {
            _transfer(from, to, amount);
            return;
        }

        if (isDexAddress[from]) {
            uint256 buyTax = (amount * taxInfo.buyFee) / MULTIPLIER;
            unchecked {
                amount -= buyTax;
            }

            if (buyTax > 0) {
                require(
                    pendingTax + amount <= balanceOf(from),
                    "Exceeded the balance"
                );
                _transfer(from, address(this), buyTax);
            }
        } else if (isDexAddress[to]) {
            uint256 sellTax = (amount * taxInfo.sellFee) / MULTIPLIER;
            unchecked {
                amount -= sellTax;
            }
            if (sellTax > 0) {
                _transfer(from, address(this), sellTax);
            }
        }

        if (
            balanceOf(address(this)) >= swapThreshold &&
            !inSwap &&
            swapThreshold != 0 &&
            !isDexAddress[from]
        ) {
            swapTokensForEth();
        }
        _transfer(from, to, amount);
    }

    function swapTokensForEth() internal {
        require(address(router) != address(0), "Invalid router");

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        inSwap = true;
        uint256 _balance = balanceOf(address(this));
        _approve(address(this), address(router), _balance);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _balance,
            0,
            path,
            payable(address(this)),
            block.timestamp
        );
        inSwap = false;
    }
}
