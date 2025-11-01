import https from "https";

const TELEGRAM_BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

// Known benign messages that should be ignored to avoid noise
const IGNORE_PATTERNS = [
  "Scaling activity initiated by",
  "deployment controller",
  "has reached a steady state",
  "service reached a steady state",
  "has started successfully",
  "steady state",
  "transitioned from PENDING to RUNNING"
];

export const handler = async (event) => {
  console.log("Received event:", JSON.stringify(event, null, 2));

  try {
    // ================================================
    // Case 1: SNS Event (CloudWatch Alarm)
    // ================================================
    if (event.Records?.[0]?.Sns) {
      for (const record of event.Records) {
        const msg = JSON.parse(record.Sns.Message);

        if (msg.NewStateValue !== "ALARM") continue;

        const service = msg.Trigger?.Dimensions?.find(d => d.name === "ServiceName")?.value || "unknown";
        const cluster = msg.Trigger?.Dimensions?.find(d => d.name === "ClusterName")?.value || "unknown";
        const reason = msg.NewStateReason || "No detailed reason provided";

        // Ignore benign scaling or deployment activities
        if (IGNORE_PATTERNS.some(p => reason.toLowerCase().includes(p.toLowerCase()))) {
          console.log(`Ignoring benign alarm: ${reason}`);
          continue;
        }

        const text = `🚨 *ECS Failure Detected (via CloudWatch)*\n\n` +
                     `*Service:* ${service}\n` +
                     `*Cluster:* ${cluster}\n` +
                     `*Reason:* ${reason}\n` +
                     `*Alarm:* ${msg.AlarmName}\n` +
                     `⏰ *Timestamp:* ${new Date().toISOString()}`;

        await sendTelegramMessage(text);
      }
    }

    // ================================================
    // Case 2: EventBridge Event (ECS Task STOPPED)
    // ================================================
    else if (event["detail-type"] === "ECS Task State Change") {
      const detail = event.detail;
      const containers = detail.containers || [];
      const stoppedReason = detail.stoppedReason || "No reason provided";
      const exitCode = containers[0]?.exitCode ?? "N/A";
      const containerName = containers[0]?.name ?? "unknown";
      const taskArn = detail.taskArn;
      const service = detail.group?.replace("service:", "") ?? "N/A";

      // Ignore benign ECS transitions
      if (IGNORE_PATTERNS.some(p => stoppedReason.toLowerCase().includes(p.toLowerCase()))) {
        console.log(`Ignoring benign event: ${stoppedReason}`);
        return;
      }

      // Skip successful exits (exitCode == 0)
      if (exitCode === 0) {
        console.log(`Ignoring container exited successfully: ${containerName}`);
        return;
      }

      const text = `⚙️ *ECS Task Failure*\n\n` +
                   `*Service:* ${service}\n` +
                   `*Container:* ${containerName}\n` +
                   `*Exit Code:* ${exitCode}\n` +
                   `*Reason:* ${stoppedReason}\n` +
                   `*Task ARN:* ${taskArn}\n` +
                   `⏰ *Timestamp:* ${new Date().toISOString()}`;

      await sendTelegramMessage(text);
    }

    else {
      console.log("Unrecognized event type. Ignoring.");
    }
  } catch (err) {
    console.error("Error processing event:", err);
    await sendTelegramMessage(`❌ *Internal error in ECS Notifier Lambda:*\n\n${err.message}`);
  }
};

// ================================================
// Helper: Send Telegram Message
// ================================================
function sendTelegramMessage(text) {
  const data = JSON.stringify({
    chat_id: TELEGRAM_CHAT_ID,
    text,
    parse_mode: "Markdown",
  });

  const options = {
    hostname: "api.telegram.org",
    path: `/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(data),
    },
  };

  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      res.on("data", () => {});
      res.on("end", resolve);
    });
    req.on("error", reject);
    req.write(data);
    req.end();
  });
}
