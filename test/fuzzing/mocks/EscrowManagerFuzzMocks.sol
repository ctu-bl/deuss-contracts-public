// SPDX-License-Identifier: MIT
/* solhint-disable one-contract-per-file */
pragma solidity 0.8.34;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract FuzzERC20 is ERC20 {
    constructor() ERC20("Fuzz ERC20", "F20") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FuzzERC721 is ERC721 {
    constructor() ERC721("Fuzz ERC721", "F721") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract FuzzERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 tokenId, uint256 amount) external {
        _mint(to, tokenId, amount, "");
    }
}
