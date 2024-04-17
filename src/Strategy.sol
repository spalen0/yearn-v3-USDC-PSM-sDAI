// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

/// @title yearn-v3-USDC-PSM-sDAI
/// @author mil0x
/// @notice yearn-v3 Strategy that trades USDC through PSM to farm sDAI.
contract Strategy is BaseHealthCheck, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    uint256 public depositLimit; //in 1e6
    uint256 public maxAcceptableFeeOutPSM; //in WAD
    uint256 public swapSlippageBPS; //in BPS
    
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant SDAI = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    address private constant PSM = 0x89B78CfA322F6C5dE0aBcEecab66Aee45393cC5A;
    
    uint256 private constant SCALER = 1e12;
    uint256 private constant WAD = 1e18;

    constructor(address _asset, string memory _name) BaseHealthCheck(_asset, _name) {
        depositLimit = 100e6 * 1e6; //100M USDC deposit limit to start with
        maxAcceptableFeeOutPSM = 5e16 + 1; //0.05% expressed in WAD. If the PSM fee out is equal or bigger than this amount, it is probably better to swap through the uniswap pool, accepting slippage.
        swapSlippageBPS = 50; //0.5% expressed in BPS. Allow a slippage of 0.5% for swapping through uniswap.

        // Set uni swapper values
        base = _asset;
        _setUniFees(_asset, DAI, 100);
        //approvals:
        ERC20(_asset).safeApprove(PSM, type(uint).max); //approve the PSM
        ERC20(_asset).safeApprove(IPSM(PSM).gemJoin(), type(uint).max); //approve the gemJoin of the PSM
        ERC20(DAI).safeApprove(PSM, type(uint).max); //approve the PSM
        ERC20(DAI).safeApprove(SDAI, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        if (IPSM(PSM).tin() == 0 && IPSM(PSM).tout() == 0) { //only allow deposits if fee in and fee out are 0
            return depositLimit;
        } else {
            return 0;
        }
    }

    function _deployFunds(uint256 _amount) internal override {
        IPSM(PSM).sellGem(address(this), _amount);
        ISDAI(SDAI).deposit(_balanceDAI(), address(this));
    }

    function _freeFunds(uint256 _amount) internal override {
        //Redeem sDAI shares proportional to the strategy shares redeemed:
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        uint256 totalDebt = totalAssets - _balanceAsset();
        uint256 sharesToRedeem = _balanceSDAI() * _amount / totalDebt;
        _uninvest(sharesToRedeem);
    }

    function _uninvest(uint256 _amount) internal {
        if (_amount == 0) return;
        //SDAI --> DAI
        _amount = ISDAI(SDAI).redeem(_amount, address(this), address(this));
        if (IPSM(PSM).tout() >= maxAcceptableFeeOutPSM) {
            _swapFrom(DAI, address(asset), _amount, _amount * (MAX_BPS - swapSlippageBPS) / MAX_BPS / SCALER);
        } else {
            IPSM(PSM).buyGem(address(this), _amount / SCALER); //buyGem in USDC amount
            //we have satisfied USDC withdrawal at this point 
            //due to the need for USDC decimals in buyGem we can have DAI leftover up to the size of the decimal mismatch of 1e11
            //so we deposit the leftover DAI back into SDAI
            _amount = _balanceDAI();
            if (_amount > 0) {
                ISDAI(SDAI).deposit(_balanceDAI(), address(this));
            }
        }
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 assetBalance = _balanceAsset();
            if (assetBalance > 0) {
                _deployFunds(assetBalance);
            }
        _totalAssets = _balanceAsset() + ISDAI(SDAI).convertToAssets(_balanceSDAI()) / SCALER;
    }

    function _balanceAsset() internal view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function _balanceDAI() internal view returns (uint256) {
        return ERC20(DAI).balanceOf(address(this));
    }

    function _balanceSDAI() internal view returns (uint256) {
        return ERC20(SDAI).balanceOf(address(this));
    }

    // Set the deposit limit in 1e6 units. Set this to 0 to disallow deposits.
    function setDepositLimit(uint256 _depositLimit) external onlyManagement {
        depositLimit = _depositLimit;
    }

    // Set the maximum acceptable fee out of the PSM before we automatically switch to Uniswap swapping.
    // Set this to 0 to force swapping through uniswap
    function setMaxAcceptableFeeOutPSM(uint256 _maxAcceptableFeeOutPSM) external onlyManagement {
        maxAcceptableFeeOutPSM = _maxAcceptableFeeOutPSM;
    }
    
    // Set the slippage for deposits in basis points.
    function setSwapSlippageBPS(uint256 _swapSlippageBPS) external onlyManagement {
        swapSlippageBPS = _swapSlippageBPS;
    }

    /*//////////////////////////////////////////////////////////////
                EMERGENCY
    //////////////////////////////////////////////////////////////*/

    function _emergencyWithdraw(uint256 _amount) internal override {
        uint256 currentBalance = _balanceSDAI();
        if (_amount > currentBalance) {
            _amount = currentBalance;
        }
        _uninvest(_amount);
    }
}

interface IPSM {
    function gemJoin() external view returns (address);
    function sellGem(address usr, uint256 gemAmt) external;
    function buyGem(address usr, uint256 gemAmt) external;
    function tin() external view returns(uint256);
    function tout() external view returns(uint256);
}

interface ISDAI {
    function deposit(uint256 assets, address receiver) external;
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function withdraw(uint256 assets, address receiver, address owner) external;
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
}
