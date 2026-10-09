const { randomUUID } = require("node:crypto");

// Keep config messages separate: legacy announcement handlers would otherwise
// store a data-only config payload in the user-visible announcement history.
const FCM_TOPIC = "detect_co_ml_config";
const QUICK_TUNNEL_HOST = /^[a-z0-9]+(?:-[a-z0-9]+){1,3}\.trycloudflare\.com$/;

function normalizeQuickTunnelUrl(value) {
  if (typeof value !== "string" || value.length > 255) {
    throw new TypeError("ML API URL must be a valid Cloudflare Quick Tunnel URL.");
  }

  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new TypeError("ML API URL must be a valid Cloudflare Quick Tunnel URL.");
  }

  if (
    parsed.protocol !== "https:" ||
    !QUICK_TUNNEL_HOST.test(parsed.hostname) ||
    parsed.username ||
    parsed.password ||
    parsed.port ||
    (parsed.pathname !== "/" && parsed.pathname !== "") ||
    parsed.search ||
    parsed.hash
  ) {
    throw new TypeError("ML API URL must use an HTTPS *.trycloudflare.com hostname.");
  }

  return parsed.origin;
}

function extractQuickTunnelUrl(output) {
  if (typeof output !== "string") return null;
  const candidates = output.match(
    /https:\/\/[a-z0-9]+(?:-[a-z0-9]+){1,3}\.trycloudflare\.com/gi,
  ) || [];
  for (let index = candidates.length - 1; index >= 0; index -= 1) {
    try {
      return normalizeQuickTunnelUrl(candidates[index]);
    } catch {
      // Ignore URLs that resemble, but do not satisfy, the expected host form.
    }
  }
  return null;
}

async function verifyQuickTunnelHealth(value, fetchImpl = fetch) {
  const url = normalizeQuickTunnelUrl(value);
  let response;
  try {
    response = await fetchImpl(`${url}/health`, {
      signal: AbortSignal.timeout(8_000),
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Public ML API health check could not be reached: ${detail}`,
      { cause: error },
    );
  }
  if (!response.ok) {
    throw new Error(`Public ML API health check returned HTTP ${response.status}.`);
  }
  let health;
  try {
    health = await response.json();
  } catch {
    throw new Error("Public ML API health check returned invalid JSON.");
  }
  if (health?.status !== "healthy" || health?.models_loaded !== true) {
    throw new Error("Public ML API is not healthy with models loaded.");
  }
  return url;
}

async function publishMlApiUrl(
  value,
  {
    configRef,
    sendMessage,
    verifyHealth = verifyQuickTunnelHealth,
    now = Date.now,
    createVersion = randomUUID,
  },
) {
  const url = normalizeQuickTunnelUrl(value);
  // Do not read or mutate the published record until the public API confirms
  // that its models are loaded.
  await verifyHealth(url);

  const currentSnapshot = await configRef.once("value");
  const current = currentSnapshot.val();

  let config = current;
  let changed = false;
  if (!current || current.url !== url) {
    config = { url, version: createVersion(), updatedAt: now() };
    const transaction = await configRef.transaction(
      (latest) => (latest?.url === url ? undefined : config),
      undefined,
      false,
    );
    if (transaction.committed) {
      config = transaction.snapshot.val();
      changed = true;
    } else {
      config = transaction.snapshot.val();
    }
  }

  if (!config || config.url !== url) {
    throw new Error("Could not store the verified ML API URL.");
  }

  // A prior successful notification is recorded on the parent config node.
  // This avoids trying to claim a message that was already delivered.
  if (config.notificationSentAt) {
    return { changed, config, notificationSent: false, notificationPending: false };
  }

  const claimRef = configRef.child("notificationClaimedAt");
  const claimTime = now();
  const claim = await claimRef.transaction(
    (latestClaimTime) => {
      const claimedAt = Number(latestClaimTime) || 0;
      if (claimedAt && claimTime - claimedAt < 60_000) return;
      return claimTime;
    },
    undefined,
    false,
  );

  let notificationSent = false;
  if (claim.committed) {
    try {
      await sendMessage({
        topic: FCM_TOPIC,
        data: {
          type: "ml_api_update",
          url: config.url,
          version: String(config.version),
          updatedAt: String(config.updatedAt),
        },
        android: { priority: "high" },
        apns: {
          headers: { "apns-priority": "5" },
          payload: { aps: { contentAvailable: true } },
        },
      });

      await configRef.update({ notificationSentAt: now() });
      notificationSent = true;
    } catch (error) {
      await configRef.update({ notificationClaimedAt: null });
      throw error;
    }
  }

  return {
    changed,
    config,
    notificationSent,
    notificationPending: !claim.committed,
  };
}

module.exports = {
  FCM_TOPIC,
  extractQuickTunnelUrl,
  normalizeQuickTunnelUrl,
  publishMlApiUrl,
  verifyQuickTunnelHealth,
};
