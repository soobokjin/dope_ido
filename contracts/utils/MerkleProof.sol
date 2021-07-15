// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";


library MerkleProof {
    using SafeMath for uint32;

    function verify(
        bytes32 _leaf,
        bytes32 _root,
        bytes32[] memory _proof,
        uint32 _index
    ) internal pure returns (bool) {
        bytes32 hash = _leaf;

        for (uint256 i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index.mod(2) == 0) {
                hash = keccak256(abi.encodePacked(hash, proofElement));
            } else {
                hash = keccak256(abi.encodePacked(proofElement, hash));
            }

            _index = uint32(_index.div(2));
        }

        return hash == _root;
    }
}
