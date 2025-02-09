import { signIn, getIdToken, type AuthProvider } from "./auth.js";

const params = new URLSearchParams(location.search);
const state = params.get("state");
const widgetMode = params.get("widget") === "1";

const statusEl = document.getElementById("status") as HTMLElement;

function showStatus(msg: string, isError = false) {
  statusEl.textContent = msg;
  statusEl.classList.toggle("error", isError);
  statusEl.classList.add("show");
}

document.querySelectorAll<HTMLButtonElement>("button[data-provider]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    try {
      await signIn(btn.dataset.provider as AuthProvider);
      const token = await getIdToken();
      if (!token) return;

      if (widgetMode && state) {
        const res = await fetch("/auth/deposit", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ state, idToken: token }),
        });
        if (res.ok) {
          showStatus("Signed in. Return to Air Prompt — you can close this tab.");
        } else {
          showStatus("Failed to hand off token. Try again.", true);
        }
        return;
      }

      const anyWindow = window as any;
      if (anyWindow.webkit?.messageHandlers?.airprompt) {
        anyWindow.webkit.messageHandlers.airprompt.postMessage({ idToken: token });
      } else {
        localStorage.setItem("airprompt-id-token", token);
        showStatus("Signed in. You can close this tab.");
      }
    } catch (e) {
      console.error(e);
      showStatus("Login failed: " + (e as Error).message, true);
    }
  });
});
