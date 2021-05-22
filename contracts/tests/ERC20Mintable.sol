pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mintable is ERC20 {
    constructor(string memory name, string memory symbol, uint256 amount)
        public
        ERC20(symbol, name)
    {
        mint(msg.sender, amount);
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}
