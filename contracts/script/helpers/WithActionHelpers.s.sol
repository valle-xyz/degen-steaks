// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import "forge-std/Script.sol";
import "script/helpers/WithFileHelpers.s.sol";
import "test/setup/Constants.t.sol";
import "src/BetRegistry.sol";
import "src/SteakedDegen.sol";
import "src/auxiliary/DegenToken.sol";
import "src/auxiliary/MockPriceFeed.sol";

/// @dev holds action like deploying the system and creating some traction for testnet
contract WithActionHelpers is Script, WithFileHelpers {
    IBetRegistry betRegistry;
    DegenToken degenToken;
    ISteakedDegen steakedDegen;
    MockPriceFeed priceFeed;
    uint256 betAmount;
    uint256 marketDuration = 35; // the script will sleep for this duration

    /// @dev testnet deployment with MockDEGEN and MockPriceFeed
    function deployTestnet() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(deployerPrivateKey);

        priceFeed = new MockPriceFeed();
        degenToken = new DegenToken("Degen Token", "DEGEN");
        steakedDegen = new SteakedDegen("Steaked Degen", "SDEGEN", degenToken, address(this));
        betRegistry = new BetRegistry(degenToken, steakedDegen, IPriceFeed(address(priceFeed)), address(this));
        steakedDegen.setFan(address(betRegistry), true);

        uint256 initialDeposit = 10 * 1e6 * 1e18;
        degenToken.mint(initialDeposit);
        degenToken.approve(address(steakedDegen), initialDeposit);
        steakedDegen.initialDeposit(initialDeposit, address(this));

        vm.stopBroadcast();

        // Write Files

        _writeJson("priceFeed", address(priceFeed));
        _writeJson("degenToken", address(degenToken));
        _writeJson("steakedDegen", address(steakedDegen));
        _writeJson("betRegistry", address(betRegistry));

        string memory addressFile = string.concat("deployments/", _network, "_addresses.ts");

        string memory addresses = string(
            abi.encodePacked(
                "export const priceFeedAddress = \"",
                vm.toString(address(priceFeed)),
                "\";\n",
                "export const degenTokenAddress = \"",
                vm.toString(address(degenToken)),
                "\";\n",
                "export const steakedDegenAddress = \"",
                vm.toString(address(steakedDegen)),
                "\";\n",
                "export const betRegistryAddress = \"",
                vm.toString(address(betRegistry)),
                "\";\n"
            )
        );
        vm.writeFile(addressFile, addresses);
    }

    /// @dev open and close several markets and bets
    /// the actions are separated into different functions that need 10 seconds of time in between them on testnet
    /// locally the time difference can be simulated
    function traction() public {
        traction_setup();
        traction_1();

        sleep(marketDuration);

        traction_2();
        traction_3();
        traction_4();
        traction_5();

        sleep(marketDuration);

        traction_6();
        traction_7();
    }

    function sleep(uint256 seconds_) public {
        if (keccak256(abi.encodePacked(_network)) == keccak256(abi.encodePacked("local"))) {
            vm.warp(block.timestamp + seconds_);
        } else if (keccak256(abi.encodePacked(_network)) == keccak256(abi.encodePacked("testnet"))) {
            vm.sleep(seconds_ * 1_000);
        } else if (keccak256(abi.encodePacked(_network)) == keccak256(abi.encodePacked("testrun"))) {
            vm.warp(block.timestamp + seconds_);
        } else {
            revert("unsupported network");
        }
    }

    function traction_setup() public {
        betRegistry = IBetRegistry(_getAddress("betRegistry"));
        degenToken = DegenToken(_getAddress("degenToken"));
        priceFeed = MockPriceFeed(_getAddress("priceFeed"));
        betAmount = 1e6 * 1e18;

        marketDuration = vm.envOr("MARKET_DURATION", uint256(35));
    }

    function traction_1() public {
        // Set grace and slash period to 0
        // create a market
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        betRegistry.setGracePeriod(0);
        betRegistry.setSlashPeriod(0);
        betRegistry.createMarket(uint40(block.timestamp + marketDuration), DEGEN_PRICE_1 - 1);
        vm.stopBroadcast();

        // Place bets
        vm.startBroadcast(vm.envUint("ALICE_PK"));
        degenToken.mint(betAmount);
        degenToken.approve(address(betRegistry), betAmount);
        betRegistry.placeBet(0, betAmount, IBetRegistry.BetDirection.HIGHER);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("BOB_PK"));
        degenToken.mint(betAmount);
        degenToken.approve(address(betRegistry), betAmount);
        betRegistry.placeBet(0, betAmount, IBetRegistry.BetDirection.LOWER);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("CAROL_PK"));
        degenToken.mint(betAmount);
        degenToken.approve(address(betRegistry), betAmount);
        betRegistry.placeBet(0, betAmount, IBetRegistry.BetDirection.HIGHER);
        vm.stopBroadcast();
    }

    function traction_2() public {
        // Resolve the market
        // HIGHER wins
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        priceFeed.setPrice(DEGEN_PRICE_1);
        betRegistry.resolveMarket(0);
        vm.stopBroadcast();
    }

    function traction_3() public {
        // Cash out Alice
        // (Bob lost his bet)
        vm.startBroadcast(vm.envUint("ALICE_PK"));
        betRegistry.cashOut(0);
        vm.stopBroadcast();
    }

    function traction_4() public {
        // Simulate slash
        vm.startBroadcast(vm.envUint("ALICE_PK"));
        betRegistry.slash(0);
        vm.stopBroadcast();

        // Create two new markets with different end times
        // 1 will stay open, 2 will close earlier
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        betRegistry.createMarket(uint40(block.timestamp + 1 days), DEGEN_PRICE_1 - 1);
        betRegistry.createMarket(uint40(block.timestamp + marketDuration), DEGEN_PRICE_1 + 1);
        vm.stopBroadcast();
    }

    function traction_5() public {
        // Place bets
        vm.startBroadcast(vm.envUint("ALICE_PK"));
        degenToken.mint(betAmount * 2);
        degenToken.approve(address(betRegistry), betAmount * 2);
        betRegistry.placeBet(1, betAmount, IBetRegistry.BetDirection.HIGHER);
        betRegistry.placeBet(2, betAmount, IBetRegistry.BetDirection.LOWER);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("BOB_PK"));
        degenToken.mint(betAmount * 2);
        degenToken.approve(address(betRegistry), betAmount * 2);
        betRegistry.placeBet(1, betAmount, IBetRegistry.BetDirection.LOWER);
        betRegistry.placeBet(2, betAmount, IBetRegistry.BetDirection.HIGHER);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("CAROL_PK"));
        degenToken.mint(betAmount * 2);
        degenToken.approve(address(betRegistry), betAmount * 2);
        betRegistry.placeBet(1, betAmount, IBetRegistry.BetDirection.HIGHER);
        betRegistry.placeBet(2, betAmount, IBetRegistry.BetDirection.LOWER);
        vm.stopBroadcast();
    }

    function traction_6() public {
        vm.startBroadcast(vm.envUint("DEPLOYER_PK"));
        betRegistry.resolveMarket(2);
        vm.stopBroadcast();
    }

    function traction_7() public {
        // Cash out
        vm.startBroadcast(vm.envUint("ALICE_PK"));
        betRegistry.cashOut(2);
        vm.stopBroadcast();

        vm.startBroadcast(vm.envUint("CAROL_PK"));
        betRegistry.cashOut(2);
        vm.stopBroadcast();
    }
}
