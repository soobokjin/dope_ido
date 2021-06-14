pragma solidity ^0.4.0;

contract MockFund {
    event LenderClaimCalled (
        address user,
        uint256 lenderDepositPercent,
        uint256 percentRate
    );

    event IncreaseCollateralCalled (
        address user,
        uint256 collateralAmount
    );

    event DecreaseCollateralCalled (
        address user,
        uint256 lenderDepositPercent,
        uint256 percentRate
    );

    function lenderClaim (
        address user,
        uint256 lenderDepositPercent,
        uint256 percentRate
    ) public {
        emit LenderClaimCalled(user, lenderDepositPercent, percentRate);
    }

    function increaseCollateral (
        address user,
        uint256 collateralAmount
    ) public  {
        emit IncreaseCollateralCalled(user, collateralAmount);
    }

    function decreaseCollateral (
        address user,
        uint256 interestAmount,
        uint256 unlockCollateralAmount
    ) public  {
        emit DecreaseCollateralCalled(user, interestAmount, unlockCollateralAmount);
    }
}
