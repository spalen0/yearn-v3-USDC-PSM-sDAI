// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";
import {IPSM} from "./interfaces/IPSM.sol";
import {ISDAI} from "./interfaces/ISDAI.sol";

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
    address private constant gemJoin = 0x0A59649758aa4d66E25f08Dd01271e891fe52199;
    address private constant pool = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    
    uint256 private constant SCALER = 1e12;
    uint256 private constant WAD = 1e18;

    constructor(address _asset, string memory _name) BaseHealthCheck(_asset, _name) {
        depositLimit = 100e6 * 1e6; //100M USDC deposit limit to start with
        //use setMaxAcceptableFeeOutPSM(0) to force swap through Uniswap
        maxAcceptableFeeOutPSM = 5e16 + 1; //0.05% expressed in WAD. If the PSM fee out is equal or bigger than this amount, it is probably better to swap through the uniswap pool, accepting slippage.
        swapSlippageBPS = 50; //0.5% expressed in BPS. Allow a slippage of 0.5% for swapping through uniswap.

        // Set uni swapper values
        base = _asset;
        _setUniFees(_asset, DAI, 100);

        //approvals:
        ERC20(_asset).safeApprove(PSM, type(uint).max); //approve the PSM
        ERC20(_asset).safeApprove(gemJoin, type(uint).max); //approve the gemJoin of the PSM
        ERC20(DAI).safeApprove(PSM, type(uint).max); //approve the PSM
        ERC20(DAI).safeApprove(SDAI, type(uint).max);
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        if (IPSM(PSM).tin() == 0 && IPSM(PSM).tout() == 0) { //only allow deposits if PSM fee in and fee out are 0
            uint256 totalDeposits = TokenizedStrategy.totalAssets();
            if (depositLimit > totalDeposits) {
                return depositLimit - totalDeposits;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }

    function _deployFunds(uint256 _amount) internal override {
        IPSM(PSM).sellGem(address(this), _amount); //swap USDC --> DAI 1:1 through PSM (in USDC amount)
        ISDAI(SDAI).deposit(_balanceDAI(), address(this));
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        if (IPSM(PSM).tout() >= maxAcceptableFeeOutPSM) {
            return asset.balanceOf(pool);
        } else {
            return asset.balanceOf(gemJoin);
        }
    }

    function _freeFunds(uint256 _amount) internal override {
        //Redeem sDAI shares proportional to the strategy shares redeemed:
        uint256 totalDebt = TokenizedStrategy.totalAssets() - _balanceAsset();
        uint256 sharesToRedeem = _balanceSDAI() * _amount / totalDebt;
        _uninvest(sharesToRedeem);
    }

    function _uninvest(uint256 _amount) internal {
        if (_amount == 0) return;
        //SDAI --> DAI
        _amount = ISDAI(SDAI).redeem(_amount, address(this), address(this)); //SDAI --> DAI
        uint256 feeOut = IPSM(PSM).tout(); //in WAD
        if (feeOut >= maxAcceptableFeeOutPSM) { //if PSM fee is not 0
            _swapFrom(DAI, address(asset), _amount, _amount * (MAX_BPS - swapSlippageBPS) / MAX_BPS / SCALER); //swap DAI --> USDC through Uniswap (in DAI amount)
        } else {
            IPSM(PSM).buyGem(address(this), _amount * (WAD - feeOut) / SCALER / WAD); //swap DAI --> USDC 1:1 through PSM (in USDC amount). Need to account for fees that will be added on top & USDC decimals.
            //due to the need for USDC decimals in buyGem we can have DAI leftover up to the size of the decimal mismatch of 1e11
            //it will be redeposited in the next report
        }
    }

    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        uint256 currentBalance;
        if (!TokenizedStrategy.isShutdown()) {
            currentBalance = _balanceAsset();
            if (currentBalance > 0) {
                IPSM(PSM).sellGem(address(this), currentBalance); //swap USDC --> DAI 1:1 through PSM (in USDC amount)
            }
        }

        currentBalance = _balanceDAI();
        if (currentBalance > 0) {
            ISDAI(SDAI).deposit(currentBalance, address(this)); //DAI --> SDAI
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
        require(_maxAcceptableFeeOutPSM <= WAD);
        maxAcceptableFeeOutPSM = _maxAcceptableFeeOutPSM;
    }
    
    // Set the slippage for deposits in basis points.
    function setSwapSlippageBPS(uint256 _swapSlippageBPS) external onlyManagement {
        require(_swapSlippageBPS <= MAX_BPS);
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