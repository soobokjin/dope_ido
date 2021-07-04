// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract MerkleProof {
    using SafeMath for uint32;

    function verify (
        bytes32[] memory _proof, bytes32 _root, bytes32 _leaf, uint32 _index
    )
        internal pure returns (bool)
    {
        bytes32 hash = _leaf;

        for (uint i = 0; i < _proof.length; i++) {
            bytes32 proofElement = _proof[i];

            if (_index.mod(2) == 0) {
                hash = keccak256(abi.encodePacked(hash, proofElement));
            } else {
                hash = keccak256(abi.encodePacked(proofElement, hash));
            }

            _index = _index.div(2);
        }

        return hash == _root;
    }
}
