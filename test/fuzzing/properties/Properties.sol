// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/* solhint-disable no-empty-blocks */

import {Properties_SPLY} from "./Properties_SPLY.sol";
import {Properties_ESCROW} from "./Properties_ESCROW.sol";
import {Properties_MKT} from "./Properties_MKT.sol";
import {Properties_OFFER} from "./Properties_OFFER.sol";
import {Properties_DEAL} from "./Properties_DEAL.sol";
import {Properties_INTEREST} from "./Properties_INTEREST.sol";
import {Properties_BMF} from "./Properties_BMF.sol";
import {Properties_ORDERBOOK} from "./Properties_ORDERBOOK.sol";
import {Properties_PAUSE} from "./Properties_PAUSE.sol";
import {Properties_ER} from "./Properties_ER.sol";
import {Properties_ASSET} from "./Properties_ASSET.sol";
import {Properties_BOND} from "./Properties_BOND.sol";
import {Properties_ESAU} from "./Properties_ESAU.sol";
import {Properties_PR} from "./Properties_PR.sol";
import {Properties_TKN} from "./Properties_TKN.sol";
import {Properties_DEP} from "./Properties_DEP.sol";
import {Properties_WALLET} from "./Properties_WALLET.sol";
import {Properties_TL} from "./Properties_TL.sol";

abstract contract Properties is
    Properties_SPLY,
    Properties_ESCROW,
    Properties_MKT,
    Properties_OFFER,
    Properties_DEAL,
    Properties_INTEREST,
    Properties_BMF,
    Properties_ORDERBOOK,
    Properties_PAUSE,
    Properties_ER,
    Properties_TKN,
    Properties_ASSET,
    Properties_BOND,
    Properties_ESAU,
    Properties_PR,
    Properties_DEP,
    Properties_WALLET,
    Properties_TL
{}
