// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.0;
pragma experimental ABIEncoderV2;

import {SafeMath} from '@openzeppelin/contracts/math/SafeMath.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import {UniswapV2Library} from '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import {IUniswapV2Router02} from '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

import {IDefiBridge} from './interfaces/IDefiBridge.sol';
import {Types} from './Types.sol';

// import 'hardhat/console.sol';


// @marc we will come up with our own uniswap bridge contract to implement TWAP
// @marc challenge one is to enhance this bridge contract for multiple asset? 
// @marc at the moment it is ETH to any token or any token to ETH
contract UniswapBridge is IDefiBridge {
    using SafeMath for uint256;

    address public immutable rollupProcessor;
    address public weth;

    uint public creationTime = block.timestamp;

    uint256 inputs;
    uint256 outputs;
    Types.AztecAsset inputAssetA;
    Types.AztecAsset outputAssetA; 

    IUniswapV2Router02 router;

    constructor(address _rollupProcessor, address _router) public {
        rollupProcessor = _rollupProcessor;
        router = IUniswapV2Router02(_router);
        weth = router.WETH();
    }

    receive() external payable {}

    // Too early, let's wait for some time maybe more depositers will come.
    error TooEarly();

    modifier swapOnlyAfter(uint _time) {
        if (block.timestamp < _time)
            revert TooEarly();
        _;
    }

    function convert(
        Types.AztecAsset calldata _inputAssetA,
        Types.AztecAsset calldata,
        Types.AztecAsset calldata _outputAssetA,
        Types.AztecAsset calldata,
        uint256 inputValue,
        uint256,
        uint64
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        require(msg.sender == rollupProcessor, 'UniswapBridge: INVALID_CALLER');
        isAsync = true;
        outputValueA = 0;
        // TODO This should check the pair exists on UNISWAP instead of blindly trying to swap.

        inputAssetA = _inputAssetA
        outputAssetA = _outputAssetA

        inputs += inputValue
    }

    function swap(uint256 inputValue) external payable onlyAfter(creationTime + 2 minutes) {
        isAsync = false;
        uint256[] memory amounts;
        uint256 deadline = block.timestamp;

        if (inputAssetA.assetType == Types.AztecAssetType.ETH && outputAssetA.assetType == Types.AztecAssetType.ERC20) {
            address[] memory path = new address[](2);
            path[0] = weth;
            path[1] = outputAssetA.erc20Address;
            amounts = router.swapExactETHForTokens{value: inputValue}(0, path, rollupProcessor, deadline);
            
            inputs -= inputValue
            outputs += amounts[1]
        } else if (
            inputAssetA.assetType == Types.AztecAssetType.ERC20 && outputAssetA.assetType == Types.AztecAssetType.ETH
        ) {
            address[] memory path = new address[](2);
            path[0] = inputAssetA.erc20Address;
            path[1] = weth;
            require(
                IERC20(inputAssetA.erc20Address).approve(address(router), inputValue),
                'UniswapBridge: APPROVE_FAILED'
            );
            amounts = router.swapExactTokensForETH(inputValue, 0, path, rollupProcessor, deadline);

            inputs -= inputValue
            outputs += amounts[1]
        } else {  // inputAssetA.assetType == Types.AztecAssetType.ERC20 && outputAssetA.assetType == Types.AztecAssetType.ERC20
            require(inputAssetA.erc20Address != outputAssetA.erc20Address, 'Cannot trade same token');
            address[] memory path = new address[](2);
            path[0] = inputAssetA.erc20Address;
            path[1] = outputAssetA.erc20Address;
            
            require(
                IERC20(inputAssetA.erc20Address).approve(address(router), inputValue),
                'UniswapBridge: APPROVE_FAILED'
            );
            amounts = router.swapExactTokensForTokens(inputValue, 0, path, rollupProcessor, deadline);

            inputs -= inputValue
            outputs += amounts[1]
        }
    }

    function canFinalise(
        uint256 /*interactionNonce*/
    ) external view override returns (bool) {
        return inputs == 0;
    }

    function finalise(uint256) external payable override returns (uint256 outputValueA, uint256) {
        require(msg.sender == rollupProcessor, 'UniswapBridge: INVALID_CALLER');
        outputValueA = outputs;
    }
}
