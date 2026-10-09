const test = require("node:test");
const assert = require("node:assert/strict");
const {
  FCM_TOPIC,
  extractQuickTunnelUrl,
  normalizeQuickTunnelUrl,
  publishMlApiUrl,
  verifyQuickTunnelHealth,
} = require("../ml-api-config");

function fakeConfigRef(initialValue = null) {
  const state = { value: initialValue };
  return {
    state,
    async once() {
      return { val: () => state.value };
    },
    async transaction(update) {
      const next = update(state.value);
      if (next === undefined) {
        return { committed: false, snapshot: { val: () => state.value } };
      }
      state.value = next;
      return { committed: true, snapshot: { val: () => state.value } };
    },
    async update(value) {
      state.value = { ...state.value, ...value };
    },
    child(key) {
      return {
        async transaction(update) {
          const current = state.value?.[key] ?? null;
          const next = update(current);
          if (next === undefined) {
            return { committed: false, snapshot: { val: () => current } };
          }
          state.value = { ...state.value, [key]: next };
          return { committed: true, snapshot: { val: () => next } };
        },
      };
    },
  };
}

test("normalizes an HTTPS Quick Tunnel origin", () => {
  assert.equal(
    normalizeQuickTunnelUrl("https://alpha-beta-gamma.trycloudflare.com/"),
    "https://alpha-beta-gamma.trycloudflare.com",
  );
});

test("extracts the generated Quick Tunnel URL from cloudflared output", () => {
  const output = [
    "2026-10-09T00:00:00Z INF Starting quick tunnel",
    "| https://alpha-beta-gamma.trycloudflare.com |",
  ].join("\n");
  assert.equal(
    extractQuickTunnelUrl(output),
    "https://alpha-beta-gamma.trycloudflare.com",
  );
  assert.equal(extractQuickTunnelUrl("quick tunnel URL unavailable"), null);
});

test("requires a healthy public API with models loaded before publication", async () => {
  let requestedUrl;
  const url = await verifyQuickTunnelHealth(
    "https://alpha-beta.trycloudflare.com",
    async (value) => {
      requestedUrl = value;
      return {
        ok: true,
        async json() {
          return { status: "healthy", models_loaded: true };
        },
      };
    },
  );
  assert.equal(url, "https://alpha-beta.trycloudflare.com");
  assert.equal(requestedUrl, `${url}/health`);

  await assert.rejects(
    verifyQuickTunnelHealth("https://alpha-beta.trycloudflare.com", async () => ({
      ok: true,
      async json() {
        return { status: "starting", models_loaded: false };
      },
    })),
    /not healthy with models loaded/,
  );

  await assert.rejects(
    verifyQuickTunnelHealth("https://alpha-beta.trycloudflare.com", async () => {
      throw new Error("simulated DNS failure");
    }),
    /could not be reached: simulated DNS failure/,
  );
});

test("rejects unsafe URLs and hostnames", () => {
  for (const url of [
    "http://alpha-beta.trycloudflare.com",
    "https://example.com",
    "https://alpha-beta.trycloudflare.com.evil.example",
    "https://user:pass@alpha-beta.trycloudflare.com",
    "https://alpha-beta.trycloudflare.com/path",
    "https://alpha-beta.trycloudflare.com/?next=evil",
  ]) {
    assert.throws(() => normalizeQuickTunnelUrl(url), TypeError, url);
  }
});

test("stores a new URL, sends one topic update, and suppresses duplicates", async () => {
  const configRef = fakeConfigRef();
  const messages = [];
  const dependencies = {
    configRef,
    verifyHealth: async () => {},
    sendMessage: async (message) => messages.push(message),
    now: () => 123456,
    createVersion: () => "version-1",
  };

  const first = await publishMlApiUrl(
    "https://alpha-beta.trycloudflare.com",
    dependencies,
  );
  const second = await publishMlApiUrl(
    "https://alpha-beta.trycloudflare.com/",
    dependencies,
  );

  assert.equal(first.changed, true);
  assert.equal(first.notificationSent, true);
  assert.equal(first.notificationPending, false);
  assert.equal(second.changed, false);
  assert.equal(second.notificationSent, false);
  assert.equal(second.notificationPending, false);
  assert.equal(messages.length, 1);
  assert.equal(messages[0].topic, FCM_TOPIC);
  assert.equal(messages[0].data.type, "ml_api_update");
  assert.equal(messages[0].data.version, "version-1");
  assert.equal(messages[0].notification, undefined);
  assert.equal(configRef.state.value.url, "https://alpha-beta.trycloudflare.com");
  assert.equal(typeof configRef.state.value.updatedAt, "number");
  assert.equal(configRef.state.value.version, "version-1");
  assert.equal(configRef.state.value.notificationSentAt, 123456);
});

test("suppresses simultaneous publishers for the same tunnel URL", async () => {
  const configRef = fakeConfigRef();
  let sends = 0;
  const dependencies = {
    configRef,
    verifyHealth: async () => {},
    sendMessage: async () => {
      sends += 1;
    },
    now: () => 123456,
    createVersion: () => "version-concurrent",
  };

  await Promise.all([
    publishMlApiUrl("https://alpha-beta.trycloudflare.com", dependencies),
    publishMlApiUrl("https://alpha-beta.trycloudflare.com", dependencies),
  ]);

  assert.equal(sends, 1);
});

test("retries an update message if the database write succeeded but FCM failed", async () => {
  const configRef = fakeConfigRef();
  let sends = 0;
  const dependencies = {
    configRef,
    verifyHealth: async () => {},
    now: () => 123456,
    createVersion: () => "version-2",
    sendMessage: async () => {
      sends += 1;
      if (sends === 1) throw new Error("temporary FCM failure");
    },
  };

  await assert.rejects(
    publishMlApiUrl("https://delta-epsilon.trycloudflare.com", dependencies),
    /temporary FCM failure/,
  );
  const retry = await publishMlApiUrl(
    "https://delta-epsilon.trycloudflare.com",
    dependencies,
  );

  assert.equal(retry.changed, false);
  assert.equal(retry.notificationSent, true);
  assert.equal(sends, 2);
  assert.equal(configRef.state.value.notificationSentAt, 123456);
});

test("does not access Firebase or send FCM before public health passes", async () => {
  const configRef = fakeConfigRef();
  let databaseReads = 0;
  let messagesSent = 0;
  configRef.once = async () => {
    databaseReads += 1;
    return { val: () => configRef.state.value };
  };

  await assert.rejects(
    publishMlApiUrl("https://alpha-beta.trycloudflare.com", {
      configRef,
      verifyHealth: async () => {
        throw new Error("models are not loaded");
      },
      sendMessage: async () => {
        messagesSent += 1;
      },
    }),
    /models are not loaded/,
  );

  assert.equal(databaseReads, 0);
  assert.equal(configRef.state.value, null);
  assert.equal(messagesSent, 0);
});

test("claims notification state on its own RTDB child after writing config", async () => {
  const configRef = fakeConfigRef();
  const messages = [];

  const result = await publishMlApiUrl(
    "https://alpha-beta.trycloudflare.com",
    {
      configRef,
      verifyHealth: async () => {},
      sendMessage: async (message) => messages.push(message),
      now: () => 123456,
      createVersion: () => "version-null-snapshot",
    },
  );

  assert.equal(result.changed, true);
  assert.equal(result.config.url, "https://alpha-beta.trycloudflare.com");
  assert.equal(messages.length, 1);
  assert.equal(configRef.state.value.notificationSentAt, 123456);
  assert.equal(configRef.state.value.notificationClaimedAt, 123456);
});
