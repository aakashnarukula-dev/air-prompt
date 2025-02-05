import { initializeApp } from "firebase/app";
import {
  getAuth,
  onAuthStateChanged,
  signInWithPopup,
  GoogleAuthProvider,
  OAuthProvider,
  GithubAuthProvider,
  signOut,
  type User,
} from "firebase/auth";
import { firebaseConfig } from "./firebase-config.js";

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);

export type AuthProvider = "google" | "apple" | "github";

export function onUser(cb: (user: User | null) => void) {
  return onAuthStateChanged(auth, cb);
}

export async function signIn(provider: AuthProvider): Promise<User> {
  const p = providerFor(provider);
  const result = await signInWithPopup(auth, p);
  return result.user;
}

export async function logOut(): Promise<void> {
  await signOut(auth);
}

export async function getIdToken(): Promise<string | null> {
  const user = auth.currentUser;
  if (!user) return null;
  return user.getIdToken();
}

function providerFor(p: AuthProvider) {
  switch (p) {
    case "google":
      return new GoogleAuthProvider();
    case "apple":
      return new OAuthProvider("apple.com");
    case "github":
      return new GithubAuthProvider();
  }
}
