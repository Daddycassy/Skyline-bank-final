// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// SBOI Deposit Reward Token (ERC-20)
// 1 token = Rs 1 of reward value (internal price only, not redeemable for cash).
// Built on OpenZeppelin Contracts v5. In Remix the imports below resolve automatically.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract SBOIRewardToken is ERC20, ERC20Burnable, Ownable, Pausable {
    // Loophole fix: cap on any single mint (matches the Rs 2,000 cap per deposit),
    // so a stolen or misused issuer key cannot print unlimited tokens in one call.
    uint256 public constant MAX_MINT_PER_CALL = 2000;

    // Loophole fix: only KYC-verified wallets may hold or receive tokens,
    // so tokens cannot drift to anonymous wallets and be traded like money.
    mapping(address => bool) public verified;

    event WalletVerified(address indexed wallet, bool status);
    event RewardMinted(address indexed to, uint256 amount);

    // 'bank' is the issuer address. In production this should be a multisig wallet.
    constructor(address bank)
        ERC20("SBOI Deposit Reward", "SBOIR")
        Ownable(bank)
    {}

    // Whole tokens only: 1 token = Rs 1.
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    // The bank marks a wallet as verified after KYC. One wallet per customer is
    // enforced off-chain, in the bank's own customer database.
    function setVerified(address wallet, bool status) external onlyOwner {
        verified[wallet] = status;
        emit WalletVerified(wallet, status);
    }

    // Only the bank can create tokens.
    function mintReward(address to, uint256 amount) external onlyOwner {
        require(amount > 0 && amount <= MAX_MINT_PER_CALL, "Amount exceeds cap");
        _mint(to, amount);
        emit RewardMinted(to, amount);
    }

    // ---- Redemption: customers spend tokens on bank perks ----
    // Tokens are burned on redemption. The bank listens for PerkRedeemed and delivers
    // the perk (e.g. forex charge waiver) through its normal systems, off-chain.
    // Tokens are never exchanged for cash.
    struct Perk {
        string name;
        uint256 cost; // in tokens (1 token = Rs 1)
        bool active;
    }
    mapping(uint256 => Perk) public perks;

    event PerkSet(uint256 indexed perkId, string name, uint256 cost, bool active);
    event PerkRedeemed(address indexed customer, uint256 indexed perkId, uint256 cost);

    // The bank defines or changes a perk, e.g. (1, "Forex charge waiver", 200, true).
    function setPerk(uint256 perkId, string calldata name, uint256 cost, bool active)
        external
        onlyOwner
    {
        require(cost > 0, "Cost must be above zero");
        perks[perkId] = Perk(name, cost, active);
        emit PerkSet(perkId, name, cost, active);
    }

    // A verified customer spends their own tokens on a perk.
    function redeem(uint256 perkId) external whenNotPaused {
        require(verified[msg.sender], "Wallet not verified");
        Perk memory p = perks[perkId];
        require(p.active, "Perk not available");
        _burn(msg.sender, p.cost); // reverts if balance is too low
        emit PerkRedeemed(msg.sender, perkId, p.cost);
    }

    // Emergency stop if the issuer key is compromised or a bug is found.
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Every mint, transfer and burn passes through here (OpenZeppelin v5).
    function _update(address from, address to, uint256 value)
        internal
        override
        whenNotPaused
    {
        // Mint or transfer: the receiver must be verified.
        if (to != address(0)) {
            require(verified[to], "Receiver not verified");
        }
        // Transfer between holders: the sender must be verified too.
        if (from != address(0) && to != address(0)) {
            require(verified[from], "Sender not verified");
        }
        super._update(from, to, value);
    }
}
