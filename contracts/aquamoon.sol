//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./BEP20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Address.sol";
import "./Ownable.sol";
import "./interfaces/IPancakeV2Factory.sol";
import "./interfaces/IPancakeV2Pair.sol";
import "./interfaces/IPancakeV2Router01.sol";
import "./interfaces/IPancakeV2Router02.sol";


contract AQUAMOON is BEP20, Ownable {
    using SafeMath for uint;
    using Address for address;

    address  public constant CHARITY_WALLET = 0x4517A5a65FeE8F67aDF82ED682DB51503FF9508f; //Charity address index 1
    address  public constant MARKETING_WALLET = 0x45f6d019DdC798A7da3937b0297421754aB9D1Ca; // Marketing account index 2

    mapping(address => bool) public _isExcluded;
    uint public constant _totalSupply = 250*(10**6)*(10**6); // 250T
    address public constant BURN_ADDRESS = address(0);

    address public owner_ = msg.sender;
    uint public CHARITY_WALLET_TAX_BP = 2; // 2%
    uint public LP_LOCK_BP = 3; // 0%
    uint public DISTRIBUTION_BP = 4; // 2%
    uint public MARKETING_BP = 2; // 2%
    uint public PERCENTAGE_MULTIPLIER = 100;

    mapping(address => uint) public distributionDebt;
    uint public accSeaPerShare = 0;
    uint public constant MINIMUM_DISTRIBUTION_VALUE = 10 ** 9;


    IPancakeV2Router02 public immutable pancakeV2Router;
    address public immutable pancakeV2Pair;

    uint256 public TotalBurnedLpTokens;

    bool public inSwapAndLiquify;

    event Burned(uint amount);

    event SwapLiquifyAndBurn(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }


    constructor() BEP20( "AQUAMOON", "AQUA") {
        _mint(owner_, _totalSupply.mul(10**decimals())); // 100% to ADMIN_WALLET

      IPancakeV2Router02 _pancakeV2Router = IPancakeV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // Mainnet
//        IPancakeV2Router02 _pancakeV2Router = IPancakeV2Router02(0xD99D1c33F9fC3444f8101754aBC46c52416550D1); // testnet // https://twitter.com/PancakeSwap/status/1369547285160370182

        // Create a uniswap pair for this new token PancakeSwap testnet factory: 0x6725F303b657a9451d8BA641348b6761A6CC7a17
        pancakeV2Pair = IPancakeV2Factory(_pancakeV2Router.factory())
        .createPair(address(this), _pancakeV2Router.WETH());

        // set the rest of the contract variables
        pancakeV2Router = _pancakeV2Router;

        excludeAddress( owner_);
        excludeAddress( address(this) );
        transferOwnership(owner_); // Make admin owner

    }

    function swapLiquifyAndBurn(uint256 amount) private lockTheSwap{
        // split the contract balance into halves
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> SEA swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        // Burn received LP tokens
        burnLpTokens();

        emit SwapLiquifyAndBurn(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeV2Router.WETH();

        _approve(address(this), address(pancakeV2Router), tokenAmount);

        // make the swap
        pancakeV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(pancakeV2Router), tokenAmount);

        // add the liquidity
        pancakeV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner_,
            block.timestamp
        );
    }
    

    function burnLpTokens() private {
        IPancakeV2Pair _token = IPancakeV2Pair(pancakeV2Pair);
        uint256 amount = _token.balanceOf(address(this));
        TotalBurnedLpTokens = TotalBurnedLpTokens.add(amount);
        _token.transfer(BURN_ADDRESS, amount);
    }

    function calcPercent(uint amount, uint percentBP) internal view returns (uint){
        return amount.mul(percentBP).div(PERCENTAGE_MULTIPLIER);
    }

    function sync(address user) internal {
        // for first user this will result in 0
        _balances[user] = balanceOf(user);
        distributionDebt[user] = accSeaPerShare;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */

    function excludeAddress( address user) public onlyOwner {
        require(user != address(0));
        _isExcluded[user] = true;
    }
    
    function setDistributionPercent(uint256 Fee) external onlyOwner {
        DISTRIBUTION_BP = Fee;
    }
    
    function setCharityPercent(uint256 Fee) external onlyOwner {
        CHARITY_WALLET_TAX_BP = Fee;
    }
    function setMarketingPercent(uint256 Fee) external onlyOwner {
        MARKETING_BP = Fee;
    }
    function setLocklpPercent(uint256 Fee) external onlyOwner {
        LP_LOCK_BP = Fee;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        sync(sender);
        sync(recipient);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        // Start taxing after Burn event is done and liquidity pool is ready


        if (
            recipient != BURN_ADDRESS &&
            !inSwapAndLiquify &&
            sender != pancakeV2Pair &&
            sender != owner()
        ) {
            if ( _isExcluded[sender] == true || _isExcluded[recipient] == true ){
                _transferWithoutTax(sender, recipient, amount);
            }
            else{
                _transferWithTax(sender, recipient, amount);
            }
        } else {
            _transferWithoutTax(sender, recipient, amount);
        }
        
        
    }

    function _transferWithoutTax(address sender, address recipient, uint256 amount) internal {
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _transferWithTax(address sender, address recipient, uint256 amount) internal {
        uint CHARITY_Tax = calcPercent(amount, CHARITY_WALLET_TAX_BP);
        uint lpLockTax = calcPercent(amount, LP_LOCK_BP);
        uint distributionTax = calcPercent(amount, DISTRIBUTION_BP);
        uint marketingTax = calcPercent(amount, MARKETING_BP);

        _balances[sender] = _balances[sender].sub(amount);

        // send 2% to charity wallet
        _balances[CHARITY_WALLET] = _balances[CHARITY_WALLET].add(CHARITY_Tax);
        // send 2% to marketing wallet
        _balances[MARKETING_WALLET] = _balances[MARKETING_WALLET].add(marketingTax);
        
        // lock 4% in liquidity
        _balances[address(this)] = _balances[address(this)].add(lpLockTax); // give lp tax to self and then swap, liquify and burn
        //swapLiquifyAndBurn(lpLockTax);
        // distribute 2% to all other holders
        
        accSeaPerShare = accSeaPerShare.add(distributionTax.div(totalSupply().div(MINIMUM_DISTRIBUTION_VALUE)));

        uint amountToRecipient = amount.sub(CHARITY_Tax).sub(lpLockTax).sub(distributionTax).sub(marketingTax);

        _balances[recipient] = _balances[recipient].add(amountToRecipient);

        emit Transfer(sender, recipient, amountToRecipient);
        emit Transfer(sender,MARKETING_WALLET, marketingTax);
        emit Transfer(sender, CHARITY_WALLET, CHARITY_Tax);
    }

    /**
     * @dev See {IERC20-balanceOf}.
     * 
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account].add(accSeaPerShare.sub(distributionDebt[account]).mul(_balances[account].div(MINIMUM_DISTRIBUTION_VALUE)));
    }

    function burn(uint256 amount) public onlyOwner {
        _transferWithoutTax(msg.sender, BURN_ADDRESS, amount);
        emit Burned(amount);
    }

    //to receive ETH from uniswapV2Router when swapping
    receive() external payable {}
}

