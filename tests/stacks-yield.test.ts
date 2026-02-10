import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const user1 = accounts.get("wallet_1")!;

describe("Stacks Yield – Time Weighted Deposits", () => {
  it("initializes simnet correctly", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("records weighted entry block on first deposit", () => {
    const depositAmount = 100_000n;

    const depositTx = simnet.callPublicFn(
      "stacks-yield",
      "deposit",
      [
        simnet.makePrincipal("sip010-token"),
        simnet.makeUint(depositAmount),
      ],
      user1
    );

    expect(depositTx.result).toBeOk();

    const { result } = simnet.callReadOnlyFn(
      "stacks-yield",
      "get-user-deposit",
      [simnet.makePrincipal(user1)],
      user1
    );

    const deposit = result.expectSome();
    expect(deposit.amount).toBeUint(depositAmount);
    expect(deposit.weighted-entry-block).toBeUint(simnet.blockHeight);
  });

  it("increases time weight as blocks advance", () => {
    const startHeight = simnet.blockHeight;

    simnet.mineEmptyBlocks(500);

    const { result } = simnet.callReadOnlyFn(
      "stacks-yield",
      "get-user-time-weight",
      [simnet.makePrincipal(user1)],
      user1
    );

    const weight = result.expectOk();
    expect(weight).toBeGreaterThan(2500n);
    expect(weight).toBeLessThanOrEqual(10000n);

    expect(simnet.blockHeight).toBeGreaterThan(startHeight);
  });
});
