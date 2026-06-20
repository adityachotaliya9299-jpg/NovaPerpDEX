// Auto-extracted from frontend/lib/abis.ts by keeper/gen-keeper-files.js
// Regenerate after any contract interface change or redeploy:
//   node keeper/gen-keeper-files.js

export const OrderBookAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "priceFeed_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "marginManager_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "cancelOrder",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "executeOrder",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "isExecutable",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "marginManager",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract MarginManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "nextOrderId",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "orders",
    "inputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "collateralDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "triggerPrice",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "triggerAbove",
        "type": "bool",
        "internalType": "bool"
      },
      {
        "name": "active",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "placeOrder",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "collateralDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "triggerPrice",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "triggerAbove",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "priceFeed",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPriceFeed"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "OrderCancelled",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OrderExecuted",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "executionPrice",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "OrderPlaced",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "indexed": true,
        "internalType": "uint256"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "NotOrderOwner",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "caller",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "OrderNotActive",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "TriggerNotMet",
    "inputs": [
      {
        "name": "orderId",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "price",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "trigger",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "ZeroSize",
    "inputs": []
  }
];

export const StopLossManagerAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "priceFeed_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "marginManager_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "cancelTrigger",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "executeTrigger",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "isExecutable",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "marginManager",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract MarginManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "priceFeed",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPriceFeed"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "setTrigger",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "triggerPrice",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "triggerAbove",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "triggers",
    "inputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "triggerPrice",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "triggerAbove",
        "type": "bool",
        "internalType": "bool"
      },
      {
        "name": "active",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "TriggerCancelled",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum DataTypes.Side"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TriggerExecuted",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "price",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "TriggerSet",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "price",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "above",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "NoPosition",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoTrigger",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ]
  },
  {
    "type": "error",
    "name": "TriggerNotMet",
    "inputs": [
      {
        "name": "price",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "trigger",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  }
];

export const LiquidationEngineAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "roleManager",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "marginManager_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "isLiquidatable",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "liquidate",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "liquidateFor",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "keeper",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "marginManager",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract MarginManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "paused",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "roles",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract RoleManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "setPaused",
    "inputs": [
      {
        "name": "paused_",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "event",
    "name": "Liquidated",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "keeper",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PausedSet",
    "inputs": [
      {
        "name": "paused",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "EnginePaused",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NotGuardian",
    "inputs": [
      {
        "name": "caller",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "PositionNotLiquidatable",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ]
  }
];

export const MarginManagerAbi = [
  {
    "type": "constructor",
    "inputs": [
      {
        "name": "roleManager",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "priceFeed_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "leverage_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "collateralVault_",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "feeDistributor_",
        "type": "address",
        "internalType": "address"
      }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "addCollateral",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "authorizedRouter",
    "inputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "closePosition",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "collateralVault",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract CollateralVault"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "decreasePosition",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "decreasePositionFor",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "emergencyController",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract EmergencyController"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "feeDistributor",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract FeeDistributor"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "fundingEngine",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract FundingRateEngine"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getLeverage",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getPosition",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "internalType": "struct DataTypes.Position",
        "components": [
          {
            "name": "owner",
            "type": "address",
            "internalType": "address"
          },
          {
            "name": "market",
            "type": "bytes32",
            "internalType": "bytes32"
          },
          {
            "name": "side",
            "type": "uint8",
            "internalType": "enum DataTypes.Side"
          },
          {
            "name": "size",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "collateral",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "entryPrice",
            "type": "uint256",
            "internalType": "uint256"
          },
          {
            "name": "entryFundingIndex",
            "type": "int256",
            "internalType": "int256"
          },
          {
            "name": "lastIncreasedAt",
            "type": "uint64",
            "internalType": "uint64"
          },
          {
            "name": "status",
            "type": "uint8",
            "internalType": "enum DataTypes.PositionStatus"
          }
        ]
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "increasePosition",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "collateralDelta",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "increasePositionFor",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "collateralDelta",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "isLiquidatable",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "leverageController",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract LeverageController"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "liquidate",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "keeper",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "longOpenInterest",
    "inputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "positionKey",
    "inputs": [
      {
        "name": "account",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "stateMutability": "pure"
  },
  {
    "type": "function",
    "name": "priceFeed",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract IPriceFeed"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "removeCollateral",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "amount",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "riskManager",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract RiskManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "roles",
    "inputs": [],
    "outputs": [
      {
        "name": "",
        "type": "address",
        "internalType": "contract RoleManager"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "setEmergencyController",
    "inputs": [
      {
        "name": "controller",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setFundingEngine",
    "inputs": [
      {
        "name": "engine",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setMarginMode",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "mode",
        "type": "uint8",
        "internalType": "enum DataTypes.MarginMode"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setRiskManager",
    "inputs": [
      {
        "name": "rm",
        "type": "address",
        "internalType": "address"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "setRouter",
    "inputs": [
      {
        "name": "router",
        "type": "address",
        "internalType": "address"
      },
      {
        "name": "allowed",
        "type": "bool",
        "internalType": "bool"
      }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "shortOpenInterest",
    "inputs": [
      {
        "name": "",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ],
    "outputs": [
      {
        "name": "",
        "type": "uint256",
        "internalType": "uint256"
      }
    ],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "CollateralAdded",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "CollateralRemoved",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "amount",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "EmergencyControllerSet",
    "inputs": [
      {
        "name": "controller",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "FundingEngineSet",
    "inputs": [
      {
        "name": "engine",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PositionDecreased",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "realizedPnl",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      },
      {
        "name": "price",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PositionIncreased",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "side",
        "type": "uint8",
        "indexed": false,
        "internalType": "enum DataTypes.Side"
      },
      {
        "name": "sizeDelta",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "collateralDelta",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "price",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "PositionLiquidated",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "account",
        "type": "address",
        "indexed": true,
        "internalType": "address"
      },
      {
        "name": "market",
        "type": "bytes32",
        "indexed": true,
        "internalType": "bytes32"
      },
      {
        "name": "keeper",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "size",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      },
      {
        "name": "pnl",
        "type": "int256",
        "indexed": false,
        "internalType": "int256"
      },
      {
        "name": "price",
        "type": "uint256",
        "indexed": false,
        "internalType": "uint256"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RiskManagerSet",
    "inputs": [
      {
        "name": "riskManager",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      }
    ],
    "anonymous": false
  },
  {
    "type": "event",
    "name": "RouterSet",
    "inputs": [
      {
        "name": "router",
        "type": "address",
        "indexed": false,
        "internalType": "address"
      },
      {
        "name": "allowed",
        "type": "bool",
        "indexed": false,
        "internalType": "bool"
      }
    ],
    "anonymous": false
  },
  {
    "type": "error",
    "name": "CollateralBelowMin",
    "inputs": []
  },
  {
    "type": "error",
    "name": "NoPosition",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotGovernor",
    "inputs": [
      {
        "name": "caller",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotLiquidatable",
    "inputs": [
      {
        "name": "key",
        "type": "bytes32",
        "internalType": "bytes32"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotLiquidator",
    "inputs": [
      {
        "name": "caller",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "NotRouter",
    "inputs": [
      {
        "name": "caller",
        "type": "address",
        "internalType": "address"
      }
    ]
  },
  {
    "type": "error",
    "name": "OpenInterestCap",
    "inputs": [
      {
        "name": "market",
        "type": "bytes32",
        "internalType": "bytes32"
      },
      {
        "name": "attempted",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "cap",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "ProtocolPaused",
    "inputs": []
  },
  {
    "type": "error",
    "name": "SizeExceedsPosition",
    "inputs": [
      {
        "name": "sizeDelta",
        "type": "uint256",
        "internalType": "uint256"
      },
      {
        "name": "size",
        "type": "uint256",
        "internalType": "uint256"
      }
    ]
  },
  {
    "type": "error",
    "name": "ZeroSize",
    "inputs": []
  }
];

