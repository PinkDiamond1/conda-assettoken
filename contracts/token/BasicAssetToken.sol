pragma solidity ^0.4.24;

/*
    Copyright 2018, CONDA
    This contract is a fork from Jordi Baylina
    https://github.com/Giveth/minime/blob/master/contracts/MiniMeToken.sol

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./library/AssetTokenSupplyL.sol";

import "./abstract/IBasicAssetToken.sol";

/** @title Basic AssetToken. */
contract BasicAssetToken is IBasicAssetToken, Ownable {
    /*
    * @title This contract includes the basic AssetToken features
    * @author Paul Pöltner / Conda
    * @dev DividendAssetToken inherits from CRWDAssetToken which inherits from BasicAssetToken
    */

    using SafeMath for uint256;
    using AssetTokenSupplyL for AssetTokenSupplyL.Supply;
    using AssetTokenSupplyL for AssetTokenSupplyL.Availability;

///////////////////
// Variables
///////////////////

    string public name;                 //The Token's name

    uint8 public decimals = 0;          //Number of decimals of the smallest unit

    string public symbol;               //An identifier

    string public version = "CRWD_0.1_alpha"; //An arbitrary versioning scheme

    // defines the baseCurrency of the token
    address public baseCurrency;

    // defines the base conversion of number of tokens to the initial rate
    // this amount will be used for regulatory checks. 
    uint256 public baseRate;
    
    // mintControl can mint and burn when token is configured
    address public mintControl;

    //can rescue tokens
    address public tokenRescueControl;

    //supply: balance, checkpoints etc.
    AssetTokenSupplyL.Supply supply;

    //availability: what's paused
    AssetTokenSupplyL.Availability availability;

    function isMintingAndBurningPaused() public view returns (bool) {
        return availability.mintingAndBurningPaused;
    }

    function getPauseControl() public view returns (address) {
        return availability.pauseControl;
    }

    function isTransfersPaused() public view returns (bool) {
        return availability.transfersPaused;
    }

///////////////////
// Events
///////////////////

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Mint(address indexed to, uint256 amount);
    event MintDetailed(address indexed initiator, address indexed to, uint256 amount);
    event MintFinished();
    event Burn(address indexed burner, uint256 value);
    event BurnDetailed(address indexed initiator, address indexed burner, uint256 value);
    event TransferPaused(address indexed initiator);
    event TransferResumed(address indexed initiator);
    event Reopened(address indexed initiator);

///////////////////
// Modifiers
///////////////////
    modifier onlyPauseControl() {
        require(msg.sender == availability.pauseControl);
        _;
    }

    //can be overwritten in inherited contracts...
    function _canDoAnytime() internal view returns (bool) {
        return false;
    }

    modifier onlyOwnerOrOverruled() {
        if(_canDoAnytime() == false) { 
            require(msg.sender == owner);
        }
        _;
    }

    modifier canMintOrBurn() { //ERROR: canMint (burn fliegt raus)
        if(_canDoAnytime() == false) { 
            require(msg.sender == mintControl);
            require(availability.tokenConfigured);
            require(!availability.crowdsalePhaseFinished);
            require(!availability.mintingAndBurningPaused);
        }
        _;
    }

    function checkCanSetMetadata() internal returns (bool) {
        if(_canDoAnytime() == false) {
            require(msg.sender == owner);
            require(!availability.tokenConfigured);
            require(!availability.crowdsalePhaseFinished);
        }

        return true;
    }

    modifier canSetMetadata() {
        checkCanSetMetadata();
        _;
    }

    modifier onlyTokenConfigured() {
        require(availability.tokenConfigured);
        _;
    }

    modifier onlyTokenRescueControl() {
        require(msg.sender == tokenRescueControl);
        _;
    }

///////////////////
// Set / Get Metadata
///////////////////

    /** @dev Change the token's metadata.
      * @param _name The name of the token.
      * @param _symbol The symbol of the token.
      */
    function setMetaData(string _name, string _symbol) public 
    canSetMetadata 
    {
        name = _name;
        symbol = _symbol;
    }

    /** @dev Change the token's currency metadata.
      * @param _tokenBaseCurrency Address of the token used as underlying base currency.
      * @param _baseRate Base conversion of number of tokens to the initial rate.
      */
    function setCurrencyMetaData(address _tokenBaseCurrency, uint256 _baseRate) public 
    canSetMetadata
    {
        require(_tokenBaseCurrency != address(0));
        require(_tokenBaseCurrency != address(this));
        require(_baseRate != 0);

        baseCurrency = _tokenBaseCurrency;
        baseRate = _baseRate;
    }

    /** @dev Set the address of the crowdsale contract.
      * @param _mintControl The address of the crowdsale.
      */
    //Error setMintControl
    function setMintControl(address _mintControl) public canSetMetadata { //ERROR: only as capitalControl (initial assignment?)
        require(_mintControl != address(0));

        mintControl = _mintControl;
    }

    function setRoles(address _pauseControl, address _tokenRescueControl) public 
    canSetMetadata
    {
        availability.setPauseControl(_pauseControl);
        tokenRescueControl = _tokenRescueControl;
    }

    function setTokenConfigured() public 
    onlyOwner
    {
        availability.setTokenConfigured();
    }

///////////////////
// ERC20 Methods
///////////////////

    /// @notice Send `_amount` tokens to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    /// @return Whether the transfer was successful or not
    //ERROR: crowdsale zuende und configured
    // Inside library
    function transfer(address _to, uint256 _amount) public returns (bool success) {
        supply.doTransfer(availability, msg.sender, _to, _amount);
        return true;
    }

    /// @notice Send `_amount` tokens to `_to` from `_from` on the condition it
    ///  is approved by `_from`
    /// @param _from The address holding the tokens being transferred
    /// @param _to The address of the recipient
    /// @param _amount The amount of tokens to be transferred
    /// @return True if the transfer was successful

    //ERROR: siehe transfer
    function transferFrom(address _from, address _to, uint256 _amount) public returns (bool success) {
        require(!availability.transfersPaused);

        return supply.transferFrom(availability, _from, _to, _amount);
    }

    /// @param _owner The address that's balance is being requested
    /// @return The balance of `_owner` at the current block
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return supply.balanceOfAt(_owner, block.number);
    }

    /// @notice `msg.sender` approves `_spender` to spend `_amount` tokens on
    ///  its behalf. This is a modified version of the ERC20 approve function
    ///  to be a little bit safer
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _amount The amount of tokens to be approved for transfer
    /// @return True if the approval was successful
    function approve(address _spender, uint256 _amount) public returns (bool success) {
        return supply.approve(_spender, _amount);
    }

    /// @dev This function makes it easy to read the `allowed[]` map
    /// @param _owner The address of the account that owns the token
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens of _owner that _spender is allowed
    ///  to spend
    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return supply.allowed[_owner][_spender];
    }

     /// @dev This function makes it easy to get the total number of tokens
    /// @return The total number of tokens
    function totalSupply() public view returns (uint) {
        return supply.totalSupplyAt(block.number);
    }


    /// @dev Increase the amount of tokens that an owner allowed to a spender.
    /// 
    /// approve should be called when allowed[_spender] == 0. To increment
    ///  allowed value is better to use this function to avoid 2 calls (and wait until
    ///  the first transaction is mined)
    ///  From MonolithDAO Token.sol
    /// @param _spender The address which will spend the funds.
    ///  @param _addedValue The amount of tokens to increase the allowance by.
    function increaseApproval(address _spender, uint _addedValue) public returns (bool) {
        return supply.increaseApproval(_spender, _addedValue);
    }

    /// @dev Decrease the amount of tokens that an owner allowed to a spender.
    ///
    /// approve should be called when allowed[_spender] == 0. To decrement
    /// allowed value is better to use this function to avoid 2 calls (and wait until
    /// the first transaction is mined)
    /// From MonolithDAO Token.sol
    /// @param _spender The address which will spend the funds.
    /// @param _subtractedValue The amount of tokens to decrease the allowance by.
    function decreaseApproval(address _spender, uint _subtractedValue) public returns (bool) {
        return supply.decreaseApproval(_spender, _subtractedValue);
    }

////////////////
// Miniting 
////////////////

    function mint(address _to, uint256 _amount) public canMintOrBurn returns (bool) {
        return supply.mint(_to, _amount);
    }

    ///  @dev Function to stop minting new tokens (as mintControl).
    ///  @return True if the operation was successful.
    function finishMinting() public canMintOrBurn returns (bool) {
        return availability.finishMinting();
    }

////////////////
// Burn - only during minting 
////////////////

    //ERROR: we remove (make comment) burn completely
    function burn(address _who, uint256 _amount) public canMintOrBurn {
        return supply.burn(_who, _amount);
    }

////////////////
// Rescue Tokens 
////////////////
    //if this contract gets a balance in some other ERC20 contract - or even iself - then we can rescue it.
    function rescueToken(address _foreignTokenAddress, address _to)
    onlyTokenRescueControl
    public
    {
        availability.rescueToken(_foreignTokenAddress, _to);
    }

////////////////
// Query balance and totalSupply in History
////////////////

    /// @dev Queries the balance of `_owner` at a specific `_blockNumber`
    /// @param _owner The address from which the balance will be retrieved
    /// @param _blockNumber The block number when the balance is queried
    /// @return The balance at `_blockNumber`
    function balanceOfAt(address _owner, uint _blockNumber) public view returns (uint256) {
        return supply.balanceOfAt(_owner, _blockNumber);
    }

    /// @notice Total amount of tokens at a specific `_blockNumber`.
    /// @param _blockNumber The block number when the totalSupply is queried
    /// @return The total amount of tokens at `_blockNumber`
    function totalSupplyAt(uint _blockNumber) public view returns(uint) {
        return supply.totalSupplyAt(_blockNumber);
    }

////////////////
// Enable tokens transfers
////////////////

    function enableTransferInternal(bool _transfersEnabled) internal {
        availability.transfersPaused = (_transfersEnabled == false);
    }

    /// @notice Enables token holders to transfer their tokens freely if true
    /// @param _transfersEnabled True if transfers are allowed
    function enableTransfers(bool _transfersEnabled) public 
    onlyOwnerOrOverruled 
    {
        enableTransferInternal(_transfersEnabled);
    }

////////////////
// Pausing token for unforeseen reasons
////////////////

    /// @dev `pauseTransfer` is an alias for `enableTransfers` using the pauseControl modifier
    /// @param _transfersEnabled False if transfers are allowed
    function pauseTransfer(bool _transfersEnabled) public
    onlyPauseControl
    {
        enableTransferInternal(_transfersEnabled);
    }

    /// @dev `pauseMinting` can pause mint/burn
    /// @param _mintingAndBurningEnabled False if minting/burning is allowed
    function pauseCapitalIncreaseOrDecrease(bool _mintingAndBurningEnabled) public
    onlyPauseControl
    {
        availability.pauseCapitalIncreaseOrDecrease(_mintingAndBurningEnabled);
    }

    /** 
      * @dev capitalControl can reopen the crowdsale.
      */
    function reopenCrowdsaleInternal() internal returns (bool) {
        return availability.reopenCrowdsale();
    }

    function inforcedTransferFromInternal(address _from, address _to, uint256 _value) internal returns (bool) {
        return supply.enforcedTransferFrom(availability, _from, _to, _value);
    }
}