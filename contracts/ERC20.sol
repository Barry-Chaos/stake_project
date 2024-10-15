// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ERC20 {

    // 所有者
    address private owner;

    // 代币名称
    string private name;

    // 代币符号
    string private symbol;

    // 总发行量
    uint256 private totalSupply;

    // 账户余额
    mapping(address => uint256) private balances;

    // 授权额度
    mapping(address => mapping(address => uint256)) private allownces;

    event Approve(address indexed owner, address indexed approved, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
        owner = msg.sender;
    }

    // 查询代币名称
    function getName() public view returns(string memory) {
        return name;
    }

    // 查询代币符号
    function getSymbol() public view returns(string memory) {
        return symbol;
    }

    // 查询代币总量
    function getTotalSupply() public view returns(uint256) {
        return totalSupply;
    }

    // 查询余额
    function balanceOf(address account) public view returns(uint256) {
        return balances[account];
    }

    // 授权额度
    function approve(address approved, uint256 value) public {
        allownces[msg.sender][approved] += value;
        emit Approve(msg.sender, approved, value);
    }

    // 查询授权额度
    function allownceOf(address owner_, address approved) public view returns(uint256) {
        return allownces[owner_][approved];
    }

    // 从调用者地址向其他地址转账
    function transfer(address to, uint256 value) public {
        require(balances[msg.sender] >= value, "Insufficient balance");

        balances[msg.sender] -= value;
        balances[to] += value;

        emit Transfer(msg.sender, to, value);
    }

    // 从指定地址向其他地址转账
    function transfer(address from, address to, uint256 value) public {
        uint256 allownce = allownces[from][msg.sender];
        require(allownce >= value, "Allownce exceeded");
        require(balances[from] >= value, "Insufficient balance");

        balances[from] -= value;
        balances[to] += value;
        allownces[from][msg.sender] -=value;

        emit Transfer(from, to, value);
    }

    // 所有者修饰器
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // 增发代币
    function mint(address account, uint256 value) public onlyOwner {
        balances[account] += value;
        totalSupply += value;
        
        emit Transfer(address(0), account, value);
    }

    // 销毁代币
    function burn(address account, uint256 value) public onlyOwner {
        require(balances[account] >= value, "Insufficient balance to burn");

        balances[account] -= value;
        totalSupply -= value;

        emit Transfer(account, address(0), value);
    }


}