// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {RoleManager} from "./RoleManager.sol";

/// @title StrategyRegistry
/// @author Aditya Chotaliya [adityachotaliya.xyz]
/// @notice On-chain index of all StrategyVault instances. Allows the frontend
///         to discover all strategies without relying on off-chain databases.
///         Only the authorized StrategyFactory can register new strategies.
///
/// @dev Registration is permissioned (factory-only) to prevent spam. However,
///      anyone can read all registered strategies.
contract StrategyRegistry {
    struct StrategyInfo {
        address vault;
        address creator;
        string name;
        string thesis;
        uint256 registeredAt;
        bool active;
    }

    RoleManager public immutable roles;

    /// @notice The factory authorized to register new strategies.
    address public factory;

    /// @notice All registered strategies in registration order.
    StrategyInfo[] public strategies;

    /// @notice vault address → index in strategies array (1-indexed; 0 = not found)
    mapping(address => uint256) public vaultIndex;

    /// @notice creator address → list of vault addresses
    mapping(address => address[]) public creatorStrategies;

    event StrategyRegistered(
        address indexed vault,
        address indexed creator,
        uint256 indexed strategyId,
        string name
    );
    event StrategyDeactivated(address indexed vault);
    event FactorySet(address indexed factory);

    error NotFactory(address caller);
    error NotGovernor(address caller);
    error AlreadyRegistered(address vault);
    error NotFound(address vault);

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory(msg.sender);
        _;
    }

    modifier onlyGovernor() {
        if (!roles.isGovernor(msg.sender)) revert NotGovernor(msg.sender);
        _;
    }

    constructor(address roles_) {
        require(roles_ != address(0), "SR: zero roles");
        roles = RoleManager(roles_);
    }

    /// @notice Set the authorized factory. Governor-only.
    function setFactory(address factory_) external onlyGovernor {
        require(factory_ != address(0), "SR: zero factory");
        factory = factory_;
        emit FactorySet(factory_);
    }

    /// @notice Register a new strategy. Only callable by the factory.
    function register(
        address vault,
        address creator,
        string calldata name,
        string calldata thesis
    ) external onlyFactory {
        if (vaultIndex[vault] != 0) revert AlreadyRegistered(vault);

        strategies.push(StrategyInfo({
            vault: vault,
            creator: creator,
            name: name,
            thesis: thesis,
            registeredAt: block.timestamp,
            active: true
        }));

        uint256 id = strategies.length; // 1-indexed
        vaultIndex[vault] = id;
        creatorStrategies[creator].push(vault);

        emit StrategyRegistered(vault, creator, id - 1, name);
    }

    /// @notice Deactivate a strategy (hide from discovery, but don't delete).
    ///         Governor-only — used to remove spam or broken strategies.
    function deactivate(address vault) external onlyGovernor {
        uint256 idx = vaultIndex[vault];
        if (idx == 0) revert NotFound(vault);
        strategies[idx - 1].active = false;
        emit StrategyDeactivated(vault);
    }

    // ------------------------------------------------------------------ //
    //                              Views                                  //
    // ------------------------------------------------------------------ //

    /// @notice Total number of registered strategies (including deactivated).
    function totalStrategies() external view returns (uint256) {
        return strategies.length;
    }

    /// @notice Get strategy info by its 0-indexed ID.
    function getStrategy(uint256 id) external view returns (StrategyInfo memory) {
        require(id < strategies.length, "SR: out of bounds");
        return strategies[id];
    }

    /// @notice Get all strategies created by a specific address.
    function getCreatorStrategies(address creator)
        external
        view
        returns (address[] memory)
    {
        return creatorStrategies[creator];
    }

    /// @notice Get a paginated slice of all active strategies.
    ///         Frontend calls this to build the discovery page without reading
    ///         the full array at once.
    function getActiveStrategies(uint256 offset, uint256 limit)
        external
        view
        returns (StrategyInfo[] memory result, uint256 total)
    {
        // Count active first for accurate total
        uint256 activeCount = 0;
        for (uint256 i = 0; i < strategies.length; i++) {
            if (strategies[i].active) activeCount++;
        }
        total = activeCount;

        if (offset >= activeCount || limit == 0) {
            return (new StrategyInfo[](0), total);
        }

        uint256 resultLen = limit;
        if (offset + limit > activeCount) resultLen = activeCount - offset;
        result = new StrategyInfo[](resultLen);

        uint256 found = 0;
        uint256 skipped = 0;
        for (uint256 i = 0; i < strategies.length && found < resultLen; i++) {
            if (!strategies[i].active) continue;
            if (skipped < offset) { skipped++; continue; }
            result[found++] = strategies[i];
        }
    }
}