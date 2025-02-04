import admin from "firebase-admin";
import type { AppConfig } from "./config.js";

export interface VerifiedUser {
  uid: string;
  email: string;
  provider: string;
}

export interface AdminLike {
  verifyIdToken: (token: string) => Promise<admin.auth.DecodedIdToken>;
}

export function initFirebase(config: AppConfig): AdminLike {
  if (admin.apps.length === 0) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: config.firebaseProjectId,
        clientEmail: config.firebaseClientEmail,
        privateKey: config.firebasePrivateKey,
      }),
    });
  }
  return admin.auth();
}

export function createVerifier(adminAuth: AdminLike) {
  return async function verify(idToken: string): Promise<VerifiedUser> {
    const decoded = await adminAuth.verifyIdToken(idToken);
    const email = decoded.email ?? "";
    if (!email) throw new Error("token has no email");
    return {
      uid: decoded.uid,
      email,
      provider: mapProvider(decoded.firebase?.sign_in_provider),
    };
  };
}

function mapProvider(raw: string | undefined): string {
  if (!raw) return "unknown";
  if (raw.startsWith("google")) return "google";
  if (raw.startsWith("apple")) return "apple";
  if (raw.startsWith("github")) return "github";
  return raw;
}
