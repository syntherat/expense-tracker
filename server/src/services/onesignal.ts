import { env } from "../config/env.js";

export async function sendPushNotifications({
  userIds,
  title,
  body,
  data,
  soundName
}: {
  userIds: string[];
  title: string;
  body: string;
  data?: Record<string, unknown>;
  soundName?: string;
}): Promise<void> {
  if (!env.ONESIGNAL_APP_ID || !env.ONESIGNAL_API_KEY || !userIds.length) {
    return;
  }

  if (!env.ONESIGNAL_ANDROID_CHANNEL_ID && soundName) {
    console.warn("[OneSignal] Custom sound requested but ONESIGNAL_ANDROID_CHANNEL_ID is not set. Android may play default sound.");
  }

  try {
    const payload: Record<string, unknown> = {
      app_id: env.ONESIGNAL_APP_ID,
      include_aliases: { external_id: userIds },
      target_channel: "push",
      headings: { en: title },
      contents: { en: body },
      data: data ?? {}
    };

    // Add custom notification sound if specified
    if (soundName) {
      payload.ios_sound = `${soundName}.wav`;
      payload.android_sound = soundName;
    }

    // Android 8+ notification sounds are controlled by channel configuration.
    if (env.ONESIGNAL_ANDROID_CHANNEL_ID) {
      payload.android_channel_id = env.ONESIGNAL_ANDROID_CHANNEL_ID;
    }

    const res = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Key ${env.ONESIGNAL_API_KEY}`
      },
      body: JSON.stringify(payload)
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
