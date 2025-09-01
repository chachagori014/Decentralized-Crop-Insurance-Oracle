
import { describe, expect, it, beforeEach } from "vitest";
import { simnet } from "@hirosystems/clarinet-sdk";
import { Cl } from "@stacks/transactions";

describe("Cropguard Contract Tests", () => {
  let accounts: Map<string, string>;
  let deployer: string;
  let wallet1: string;
  let wallet2: string;
  let oracle1: string;

  beforeEach(() => {
    simnet.deploySuite();
    accounts = simnet.getAccounts();
    deployer = accounts.get("deployer")!;
    wallet1 = accounts.get("wallet_1")!;
    wallet2 = accounts.get("wallet_2")!;
    oracle1 = accounts.get("wallet_3")!;
  });

  describe("Contract Initialization", () => {
    it("should initialize contract with correct default values", () => {
      const stats = simnet.callReadOnlyFn(
        "Cropguard",
        "get-contract-stats",
        [],
        deployer
      );
      expect(stats.result).toEqual(
        Cl.tuple({
          "total-policies": Cl.uint(0),
          "total-claims-paid": Cl.uint(0),
          "contract-balance": Cl.uint(0),
          "next-policy-id": Cl.uint(1),
        })
      );
    });
  });

  describe("Oracle Management", () => {
    it("should allow owner to authorize oracle", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "authorize-oracle",
        [Cl.principal(oracle1)],
        deployer
      );
      expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    });

    it("should verify oracle authorization", () => {
      // First authorize oracle
      simnet.callPublicFn(
        "Cropguard",
        "authorize-oracle",
        [Cl.principal(oracle1)],
        deployer
      );

      // Then check authorization
      const isAuthorized = simnet.callReadOnlyFn(
        "Cropguard",
        "is-oracle-authorized",
        [Cl.principal(oracle1)],
        deployer
      );
      expect(isAuthorized.result).toEqual(Cl.bool(true));
    });

    it("should not allow non-owner to authorize oracle", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "authorize-oracle",
        [Cl.principal(oracle1)],
        wallet1
      );
      expect(response.result).toEqual(Cl.err(Cl.uint(100))); // err-owner-only
    });
  });

  describe("Policy Creation", () => {
    beforeEach(() => {
      // Fund wallet1 for testing
      simnet.transferSTX(1000000, wallet1, deployer);
    });

    it("should create a policy successfully", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "create-policy",
        [
          Cl.stringAscii("corn"),
          Cl.uint(500000), // coverage amount
          Cl.uint(8640),   // duration blocks
          Cl.int(4000000), // latitude
          Cl.int(-9000000), // longitude
          Cl.uint(500),    // min rainfall
          Cl.uint(350)     // max temperature
        ],
        wallet1
      );
      expect(response.result).toEqual(Cl.ok(Cl.uint(1))); // policy ID 1
    });

    it("should fail with insufficient balance", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "create-policy",
        [
          Cl.stringAscii("corn"),
          Cl.uint(50000000), // very high coverage
          Cl.uint(8640),
          Cl.int(4000000),
          Cl.int(-9000000),
          Cl.uint(500),
          Cl.uint(350)
        ],
        wallet1
      );
      expect(response.result).toEqual(Cl.err(Cl.uint(109))); // err-insufficient-balance
    });

    it("should update contract stats after policy creation", () => {
      simnet.callPublicFn(
        "Cropguard",
        "create-policy",
        [
          Cl.stringAscii("corn"),
          Cl.uint(500000),
          Cl.uint(8640),
          Cl.int(4000000),
          Cl.int(-9000000),
          Cl.uint(500),
          Cl.uint(350)
        ],
        wallet1
      );

      const stats = simnet.callReadOnlyFn(
        "Cropguard",
        "get-contract-stats",
        [],
        deployer
      );
      expect(stats.result).toEqual(
        Cl.tuple({
          "total-policies": Cl.uint(1),
          "total-claims-paid": Cl.uint(0),
          "contract-balance": Cl.uint(25000), // 5% premium
          "next-policy-id": Cl.uint(2),
        })
      );
    });
  });

  describe("Weather Data Submission", () => {
    beforeEach(() => {
      simnet.transferSTX(1000000, wallet1, deployer);
      // Authorize oracle
      simnet.callPublicFn(
        "Cropguard",
        "authorize-oracle",
        [Cl.principal(oracle1)],
        deployer
      );
      // Create policy
      simnet.callPublicFn(
        "Cropguard",
        "create-policy",
        [
          Cl.stringAscii("corn"),
          Cl.uint(500000),
          Cl.uint(8640),
          Cl.int(4000000),
          Cl.int(-9000000),
          Cl.uint(500),
          Cl.uint(350)
        ],
        wallet1
      );
    });

    it("should allow authorized oracle to submit weather data", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "submit-weather-data",
        [
          Cl.uint(1), // policy ID
          Cl.uint(450), // rainfall
          Cl.uint(320), // temperature
          Cl.uint(75),  // humidity
          Cl.uint(25)   // wind speed
        ],
        oracle1
      );
      expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    });

    it("should reject weather data from unauthorized oracle", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "submit-weather-data",
        [
          Cl.uint(1),
          Cl.uint(450),
          Cl.uint(320),
          Cl.uint(75),
          Cl.uint(25)
        ],
        wallet2 // not authorized
      );
      expect(response.result).toEqual(Cl.err(Cl.uint(105))); // err-oracle-not-authorized
    });
  });

  describe("Claims Processing", () => {
    beforeEach(() => {
      simnet.transferSTX(1000000, wallet1, deployer);
      simnet.transferSTX(1000000, deployer, deployer); // Fund deployer for contract funding
      
      // Authorize oracle
      simnet.callPublicFn(
        "Cropguard",
        "authorize-oracle",
        [Cl.principal(oracle1)],
        deployer
      );
      
      // Create policy
      simnet.callPublicFn(
        "Cropguard",
        "create-policy",
        [
          Cl.stringAscii("corn"),
          Cl.uint(500000),
          Cl.uint(8640),
          Cl.int(4000000),
          Cl.int(-9000000),
          Cl.uint(500),
          Cl.uint(350)
        ],
        wallet1
      );
      
      // Fund contract for payouts
      simnet.callPublicFn(
        "Cropguard",
        "fund-contract",
        [],
        deployer
      );
    });

    it("should allow farmer to submit claim", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "submit-claim",
        [Cl.uint(1)], // policy ID
        wallet1
      );
      expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    });

    it("should not allow non-farmer to submit claim", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "submit-claim",
        [Cl.uint(1)],
        wallet2 // not the farmer
      );
      expect(response.result).toEqual(Cl.err(Cl.uint(100))); // err-owner-only
    });

    it("should not allow duplicate claims", () => {
      // Submit first claim
      simnet.callPublicFn(
        "Cropguard",
        "submit-claim",
        [Cl.uint(1)],
        wallet1
      );
      
      // Try to submit second claim
      const response = simnet.callPublicFn(
        "Cropguard",
        "submit-claim",
        [Cl.uint(1)],
        wallet1
      );
      expect(response.result).toEqual(Cl.err(Cl.uint(104))); // err-claim-already-processed
    });
  });

  describe("Insurance Pools", () => {
    beforeEach(() => {
      simnet.transferSTX(1000000, wallet1, deployer);
      simnet.transferSTX(1000000, wallet2, deployer);
    });

    it("should create insurance pool successfully", () => {
      const response = simnet.callPublicFn(
        "Cropguard",
        "create-insurance-pool",
        [
          Cl.stringAscii("corn-pool"),
          Cl.uint(10), // max members
          Cl.uint(50000), // min contribution
          Cl.stringAscii("low-risk"),
          Cl.uint(2) // coverage multiplier
        ],
        wallet1
      );
      expect(response.result).toEqual(Cl.ok(Cl.uint(1))); // pool ID 1
    });

    it("should allow joining insurance pool", () => {
      // Create pool first
      simnet.callPublicFn(
        "Cropguard",
        "create-insurance-pool",
        [
          Cl.stringAscii("corn-pool"),
          Cl.uint(10),
          Cl.uint(50000),
          Cl.stringAscii("low-risk"),
          Cl.uint(2)
        ],
        wallet1
      );
      
      // Join pool
      const response = simnet.callPublicFn(
        "Cropguard",
        "join-insurance-pool",
        [
          Cl.uint(1), // pool ID
          Cl.uint(100000) // contribution
        ],
        wallet2
      );
      expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    });
  });

  describe("Read-Only Functions", () => {
    beforeEach(() => {
      simnet.transferSTX(1000000, wallet1, deployer);
      simnet.callPublicFn(
        "Cropguard",
        "create-policy",
        [
          Cl.stringAscii("corn"),
          Cl.uint(500000),
          Cl.uint(8640),
          Cl.int(4000000),
          Cl.int(-9000000),
          Cl.uint(500),
          Cl.uint(350)
        ],
        wallet1
      );
    });

    it("should get policy details", () => {
      const policy = simnet.callReadOnlyFn(
        "Cropguard",
        "get-policy",
        [Cl.uint(1)],
        deployer
      );
      expect(policy.result).toBeSome();
    });

    it("should get policy status", () => {
      const status = simnet.callReadOnlyFn(
        "Cropguard",
        "get-policy-status",
        [Cl.uint(1)],
        deployer
      );
      expect(status.result).toEqual(
        Cl.tuple({
          exists: Cl.bool(true),
          "is-active": Cl.bool(true),
          expired: Cl.bool(false),
          "claim-processed": Cl.bool(false),
          "blocks-remaining": Cl.uint(8640),
        })
      );
    });

    it("should calculate premium", () => {
      const premium = simnet.callReadOnlyFn(
        "Cropguard",
        "calculate-premium",
        [Cl.uint(500000)],
        deployer
      );
      expect(premium.result).toEqual(Cl.uint(25000)); // 500000 / 20
    });
  });
});
