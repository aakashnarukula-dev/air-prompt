import { signIn, getIdToken, type AuthProvider } from "./auth.js";

document.querySelectorAll<HTMLButtonElement>("button[data-provider]").forEach((btn) => {
  btn.addEventListener("click", async () => {
    try {
      await signIn(btn.dataset.provider as AuthProvider);
      const token = await getIdToken();
      if (!token) return;
      const anyWindow = window as any;
      if (anyWindow.webkit?.messageHandlers?.airprompt) {
        anyWindow.webkit.messageHandlers.airprompt.postMessage({ idToken: token });
      } else {
        localStorage.setItem("airprompt-id-token", token);
        document.body.textContent = "Signed in. You can close this tab.";
      }
    } catch (e) {
      console.error(e);
      alert("Login failed");
    }
  });
});
