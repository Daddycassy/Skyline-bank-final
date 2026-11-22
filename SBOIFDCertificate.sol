// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// SBOI Fixed Deposit Certificate (ERC-721, soulbound)
// One unique token per fixed deposit. Holds only a deposit reference number, the term and the
// maturity date. No name, address or amount is stored on-chain.
// Built on OpenZeppelin Contracts v5. In Remix the imports below resolve automatically.

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract SBOIFDCertificate is ERC721, Ownable, Pausable {
    struct Deposit {
        uint256 depositRef;   // opaque deposit reference; the bank's private database maps it to the customer
        uint16 termMonths;   // 6, 12, 24 or 36 in the demo plans
        uint64 maturityDate; // unix timestamp
    }

    uint256 private _nextId = 1;
    mapping(uint256 => Deposit) public deposits;
    mapping(uint256 => bool) public referenceUsed;
    mapping(uint16 => string) public planURI; // IPFS metadata link, one design per plan (fallback)
    mapping(uint256 => string) private _certificateURI; // personalised metadata, one per certificate

    event CertificateIssued(uint256 indexed tokenId, address indexed holder, uint16 termMonths, uint64 maturityDate);
    event CertificateMatured(uint256 indexed tokenId, address indexed holder, uint16 termMonths);
    event CertificateURISet(uint256 indexed tokenId, string uri);
    event CertificateReissued(uint256 indexed oldId, uint256 indexed newId, address indexed newWallet);

    // 'bank' is the issuer address. In production this should be a multisig wallet.
    constructor(address bank)
        ERC721("SBOI FD Certificate", "SBOIFD")
        Ownable(bank)
    {}

    // Link a plan (term in months) to its IPFS metadata, e.g. ipfs://<CID>/12.json
    function setPlanURI(uint16 termMonths, string calldata uri) external onlyOwner {
        planURI[termMonths] = uri;
    }

    // Link one certificate to its own personalised metadata on IPFS, e.g. ipfs://<CID>/0001.json
    // The file shows the certificate number, deposit reference, term and dates, but never a name or amount.
    function setTokenURI(uint256 tokenId, string calldata uri) external onlyOwner {
        _requireOwned(tokenId);
        _certificateURI[tokenId] = uri;
        emit CertificateURISet(tokenId, uri);
    }

    // Issue a certificate when the bank opens a deposit.
    // For the demo, pass a maturityDate a few minutes in the future.
    function issue(
        address to,
        uint256 depositRef,
        uint16 termMonths,
        uint64 maturityDate
    ) external onlyOwner whenNotPaused returns (uint256 tokenId) {
        require(!referenceUsed[depositRef], "Reference already used");
        require(maturityDate > block.timestamp, "Maturity must be in the future");
        referenceUsed[depositRef] = true;
        tokenId = _nextId++;
        deposits[tokenId] = Deposit(depositRef, termMonths, maturityDate);
        _mint(to, tokenId);
        emit CertificateIssued(tokenId, to, termMonths, maturityDate);
    }

    // At maturity the bank pays out in core banking, then burns the certificate.
    // The event tells the bank's integration service to mint the reward tokens.
    function mature(uint256 tokenId) external onlyOwner {
        address holder = ownerOf(tokenId);
        Deposit memory d = deposits[tokenId];
        require(block.timestamp >= d.maturityDate, "Not yet matured");
        _burn(tokenId);
        delete _certificateURI[tokenId];
        emit CertificateMatured(tokenId, holder, d.termMonths);
    }

    // Loophole fix: lost wallet. Because the certificate is soulbound, the customer cannot
    // move it. After re-verifying the customer, the bank burns the old one and issues a
    // new one to the new wallet. The real deposit stays safe in core banking throughout.
    function reissue(uint256 oldId, address newWallet)
        external
        onlyOwner
        whenNotPaused
        returns (uint256 newId)
    {
        ownerOf(oldId); // reverts if the certificate does not exist
        Deposit memory d = deposits[oldId];
        _burn(oldId);
        delete _certificateURI[oldId]; // the new certificate gets a new number, so the bank sets a new personalised URI
        newId = _nextId++;
        deposits[newId] = d;
        _mint(newWallet, newId);
        emit CertificateReissued(oldId, newId, newWallet);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory personal = _certificateURI[tokenId];
        if (bytes(personal).length > 0) {
            return personal;
        }
        return planURI[deposits[tokenId].termMonths]; // fallback: the plan design
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Soulbound: allow only minting (from == 0) and burning (to == 0). Any transfer reverts.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address)
    {
        address from = _ownerOf(tokenId);
        require(from == address(0) || to == address(0), "Soulbound: transfers disabled");
        return super._update(to, tokenId, auth);
    }
}
