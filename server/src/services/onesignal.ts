import { env } from "../config/env.js";

export async function sendPushNotifications({
  userIds,
  title,
  body,
  data
}: {
  userIds: string[];
  title: string;
  body: string;
  data?: Record<string, unknown>;
}): Promise<void> {
  if (!env.ONESIGNAL_APP_ID || !env.ONESIGNAL_API_KEY || !userIds.length) {
    return;
  }

  try {
    const res = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Key ${env.ONESIGNAL_API_KEY}`
      },
      body: JSON.stringify({
        app_id: env.ONESIGNAL_APP_ID,
        include_aliases: { external_id: userIds },
        target_channel: "push",
        headings: { en: title },
        contents: { en: body },
        data: data ?? {}
      })
    });

    if (!res.ok) {
      const text = await res.text();
      console.error("[OneSignal] push failed:", res.status, text);
    }
  } catch (err) {
    // Never let a push failure crash the main request.
    console.error("[OneSignal] push error:", err);
  }
}
