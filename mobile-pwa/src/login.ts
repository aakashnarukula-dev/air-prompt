import { signIn, getIdToken, type AuthProvider } from "./auth.js";

const params = new URLSearchParams(location.search);
const state = params.get("state");
const widgetMode = params.get("widget") === "1";

document.querySelectorAll<HTMLButtonElement>("button[data-provider]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    try {
      await signIn(btn.dataset.provider as AuthProvider);
      const token = await getIdToken();
      if (!token) return;

      // Widget (external browser) flow: deposit to backend keyed by state.
      if (widgetMode && state) {
        const res = await fetch("/auth/deposit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ state, idToken: token }),
        });
        if (res.ok) {
          document.body.innerHTML = "<div style='padding:24px;font-family:system-ui'>Signed in. Return to Air Prompt — you can close this tab.</div>";
        } else {
          document.body.innerHTML = "<div style='padding:24px;color:red'>Failed to hand off token. Try again.</div>";
        }
        return;
      }

      // Legacy embedded-webview flow (kept as fallback).
      const anyWindow = window as any;
      if (anyWindow.webkit?.messageHandlers?.airprompt) {
        anyWindow.webkit.messageHandlers.airprompt.postMessage({ idToken: token });
      } else {
        localStorage.setItem("airprompt-id-token", token);
        document.body.textContent = "Signed in. You can close this tab.";
      }
    } catch (e) {
      console.error(e);
      alert("Login failed: " + (e as Error).message);
    }
  });
});
