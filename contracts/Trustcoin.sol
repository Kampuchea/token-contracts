/**
 *  Trustcoin contract, code based on multiple sources:
 *
 *  https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/token/ERC20.sol
 *  https://github.com/golemfactory/golem-crowdfunding/tree/master/contracts
 *  https://github.com/ConsenSys/Tokens/blob/master/Token_Contracts/contracts/StandardToken.sol
 *  https://github.com/ConsenSys/Tokens/blob/master/Token_Contracts/contracts/HumanStandardToken.sol
 */

pragma solidity ^0.4.7;

import './deps/ERC20TokenInterface.sol';
import './deps/SafeMath.sol';
import './deps/OutgoingMigrationTokenInterface.sol';
import './deps/IncomingMigrationTokenInterface.sol';

contract Trustcoin is OutgoingMigrationTokenInterface, ERC20TokenInterface, SafeMath {

  string public constant name = 'Trustcoin';
  uint256 public constant decimals = 6;
  string public constant symbol = 'TRST';
  string public constant version = 'TRST1.0';
  uint256 public constant minimumMigrationDuration = 26 weeks; // Minumum allowed migration period
  uint256 public totalSupply = 100000000 * (10 ** decimals); // One hundred million (ERC20)
  uint256 public totalMigrated; // Begins at 0 and increments as tokens are migrated to a new contract
  IncomingMigrationTokenInterface public newToken;
  uint256 public allowOutgoingMigrationsUntilAtLeast;
  bool public allowOutgoingMigrations = false;
  address public migrationMaster; // The Ethereum address which is allowed to set the new token's address

  mapping (address => uint256) public balances; // (ERC20)

  // This is an int256 so that we can implement a fix for this weakness in ERC20:
  // https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
  // See the comment on the appove function for our solution outline
  // @todo explain why this would never overflow
  mapping (address => mapping (address => int256)) public allowed; // (ERC20)

  modifier onlyFromMigrationMaster() {
    if (msg.sender != migrationMaster) throw;
    _;
  }

  function Trustcoin(address _migrationMaster) {
    if (_migrationMaster == 0) throw;
    migrationMaster = _migrationMaster;
    balances[msg.sender] = totalSupply;
  }

  // See ERC20
  function transfer(address _to, uint256 _value) external returns (bool) {
    if (balances[msg.sender] >= _value && _value > 0) {
      balances[msg.sender] -= _value;
      balances[_to] += _value;
      Transfer(msg.sender, _to, _value);
      return true;
    }
    return false;
  }

  // See ERC20
  function transferFrom(address _from, address _to, uint256 _value) external returns (bool) {
    if (
      balances[_from] >= _value &&
      allowed[_from][msg.sender] > 0 && 
      uint256(allowed[_from][msg.sender]) >= _value &&
      _value > 0
    ) {
      balances[_to] += _value;
      balances[_from] -= _value;
      allowed[_from][msg.sender] -= int256(_value);
      Transfer(_from, _to, _value);
      return true;
    }
    return false;
  }

  // See ERC20
  function balanceOf(address _owner) constant external returns (uint256) {
    return balances[_owner];
  }

  // See ERC20
  function approve(address _spender, uint256 _value) external returns (bool) {
    // https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    // @todo explain this
    int256 valueToSet = 0;
    if (
      allowed[msg.sender][_spender] < 0 &&
      ((_value != 0) && (allowed[msg.sender][_spender] + int256(block.number)) < 0)
    ) {
      // @todo also explain this
      return false;
    }
    if (_value == 0) {
      valueToSet = 0 - int256(block.number);
    } else {
      valueToSet = int256(_value);
    }
    allowed[msg.sender][_spender] = valueToSet;
    Approval(msg.sender, _spender, uint256(valueToSet));
    return true;
  }

  // See ERC20
  function allowance(address _owner, address _spender) constant external returns (uint256) {
    if (allowed[_owner][_spender] < 0) return 0;
    return uint256(allowed[_owner][_spender]);
  }


  //
  //  Migration methods
  //

  /// Changes the owner for the migration behaviour
  /// @param _master Address of the user who has control of setting the new token's address
  function changeMigrationMaster(address _master) onlyFromMigrationMaster external {
    if (_master == 0) throw;
    migrationMaster = _master;
  }

  // See OutgoingMigrationTokenInterface
  function finalizeOutgoingMigration() onlyFromMigrationMaster external {
    if (!allowOutgoingMigrations) throw;
    if (now < allowOutgoingMigrationsUntilAtLeast) throw;
    newToken.finalizeIncomingMigration();
    allowOutgoingMigrations = false;
  }

  // See OutgoingMigrationTokenInterface
  function beginMigrationPeriod(address _newTokenAddress) onlyFromMigrationMaster external {
    if (allowOutgoingMigrations) throw; // Ensure we haven't already started allowing migrations
    if (_newTokenAddress == 0) throw;
    if (newTokenAddress != 0) throw;
    newTokenAddress = _newTokenAddress;
    newToken = IncomingMigrationTokenInterface(newTokenAddress);
    allowOutgoingMigrationsUntilAtLeast = (now + minimumMigrationDuration);
    allowOutgoingMigrations = true;
  }

  // See OutgoingMigrationTokenInterface
  function migrateToNewContract(uint256 _value) external {
    if (!allowOutgoingMigrations) throw;
    if (_value == 0) throw;
    balances[msg.sender] = safeSub(balances[msg.sender], _value);
    totalSupply = safeSub(totalSupply, _value);
    totalMigrated = safeAdd(totalMigrated, _value);
    newToken.migrateFromOldContract(msg.sender, _value);
    OutgoingMigration(msg.sender, _value);
  }

}
