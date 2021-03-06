pragma solidity ^0.4.18;

import "zeppelin-solidity/contracts/crowdsale/FinalizableCrowdsale.sol";
import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "./TRIPToken.sol";

/**
 * @title TRIP Crowdsale contract - crowdsale contract for the TRIP tokens.
 * @author Gustavo Guimaraes - <gustavoguimaraes@gmail.com>
 */

contract TRIPCrowdsale is FinalizableCrowdsale, Pausable {

    uint256 public crowdsaleHardCapInWei; // 36000e18;
    uint256 public crowdsaleSoftCapInWei; // 26000e18;
    uint256 public preSaleCapInWei; // 18000e18;
    uint256 public crowdsaleEndsFromReachingSoftCap;

    // token figures
    uint256 constant public TOTAL_SUPPLY_CROWDSALE = 80000000e18;
    uint256 public constant COMPANY_SHARE = 20000000e18; // 10% to company
    uint256 public constant VAULT_SHARE = 80000000e18;

    uint256 public presaleEndTime;

    address public vault;

    /**
     * @dev Contract constructor function
     * @param _startTime The timestamp of the beginning of the crowdsale
     * @param _endTime Timestamp when the crowdsale will finish
     * @param _rate The token rate per ETH
     * @param _crowdsaleHardCapInWei max amount of wei to raise in the crowdsale
     * @param _crowdsaleSoftCapInWei min amount of wei to raise during crowdsale
     * @param _preSaleCapInWei max amount of wei for presale period
     * @param _wallet Multisig wallet that will hold the crowdsale funds.
     * @param _vault Multisig wallet for the vault
     */
    function TRIPCrowdsale
        (
            uint256 _startTime,
            uint256 _presaleEndTime,
            uint256 _endTime,
            uint256 _rate,
            uint256 _crowdsaleHardCapInWei,
            uint256 _crowdsaleSoftCapInWei,
            uint256 _preSaleCapInWei,
            address _wallet,
            address _vault
        )
        public
        FinalizableCrowdsale()
        Crowdsale(_startTime, _endTime, _rate, _wallet)
    {
        require(_crowdsaleHardCapInWei > _crowdsaleSoftCapInWei);

        presaleEndTime = _presaleEndTime;
        crowdsaleHardCapInWei = _crowdsaleHardCapInWei;
        crowdsaleSoftCapInWei = _crowdsaleSoftCapInWei;
        preSaleCapInWei = _preSaleCapInWei;
        vault = _vault;

        TRIPToken(token).pause();
    }

    /**
     * @dev payable function that allow token purchases
     * @param beneficiary Address of the purchaser
     */
    function buyTokens(address beneficiary)
        public
        whenNotPaused
        payable
    {
        require(beneficiary != address(0));
        require(validPurchase() && token.totalSupply() <= TOTAL_SUPPLY_CROWDSALE);

        if (now >= startTime && now <= presaleEndTime)
            require(checkPreSaleCap());

        uint256 weiAmount = msg.value;
        uint256 bonus = getBonusTier();

        // calculate token amount to be created
        uint256 tokens = weiAmount.mul(rate);

        if (bonus > 0) {
            uint256 tokensIncludingBonus = tokens.mul(bonus).div(100);

            tokens = tokens.add(tokensIncludingBonus);
        }

        // update state
        weiRaised = weiRaised.add(weiAmount);

        if (weiRaised >= crowdsaleSoftCapInWei && crowdsaleEndsFromReachingSoftCap == 0)
            crowdsaleEndsFromReachingSoftCap = now + 2 days;

        token.mint(beneficiary, tokens);

        TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);

        forwardFunds();
    }

    // overriding Crowdsale#hasEnded to add cap logic
    // @return true if crowdsale event has ended
    function hasEnded() public view returns (bool) {
        if (crowdsaleEndsFromReachingSoftCap > 0)
            return now >= crowdsaleEndsFromReachingSoftCap;

        bool capReached = weiRaised >= crowdsaleHardCapInWei;
        return super.hasEnded() || capReached;
    }

    // overriding Crowdsale#validPurchase to add extra cap logic
    // @return true if investors can buy at the moment
    function validPurchase() internal view returns (bool) {
        bool withinCap = weiRaised.add(msg.value) <= crowdsaleHardCapInWei;

        if (crowdsaleEndsFromReachingSoftCap > 0)
            return withinCap && now <= crowdsaleEndsFromReachingSoftCap;

        return super.validPurchase() && withinCap;
    }

    /**
     * @dev finalizes crowdsale
     */
    function finalization() internal {
        token.mint(wallet, COMPANY_SHARE);
        token.mint(vault, VAULT_SHARE);

        if (token.totalSupply() < TOTAL_SUPPLY_CROWDSALE) {
            uint256 remainingTokens = token.totalSupply().sub(TOTAL_SUPPLY_CROWDSALE);

            token.mint(vault, remainingTokens);
        }

        TRIPToken(token).unpause();

        super.finalization();
    }

    /**
     * @dev Creates TRIP token contract. This is called on the constructor function of the Crowdsale contract
     */
    function createTokenContract() internal returns (MintableToken) {
        return new TRIPToken();
    }

    /**
     * @dev checks whether it is pre sale and if there is minimum purchase requirement
     * @return truthy if token total supply is less or equal than preSaleCapInWei
     */
    function checkPreSaleCap() internal view returns (bool) {
        return weiRaised <= preSaleCapInWei;
    }

    /**
     * @dev calculates pre sale bonus tier
     * @return bonus percentage as uint
     */
    function calculatePreSaleBonus() internal returns (uint256) {
        require(msg.value >= 20 ether);
        /*
         Pre-sale bonuses**

         2%:	20 ETH - 99 ETH

         5%:	100 ETH - 399 ETH

         10%:	400 ETH - 999 ETH

         15%:	1,000+ ETH
        */
        if (msg.value >= 20 ether && msg.value < 100 ether)
            return 2;
        if (msg.value >= 100 ether && msg.value < 400 ether)
            return 5;
        if (msg.value >= 400 ether && msg.value < 1000 ether)
            return 10;
        if (msg.value >= 1000 ether)
            return 15;
    }

     /**
     * @dev Fetches Bonus tier percentage per bonus milestones
     * @return uint256 representing percentage of the bonus tier
     */
    function getBonusTier() internal returns (uint256) {
        bool preSalePeriod = now >= startTime && now <= presaleEndTime;
        bool crowdsalePeriod = now > presaleEndTime;

        if (preSalePeriod) return calculatePreSaleBonus();
        if (crowdsalePeriod) return 0;
    }
}
