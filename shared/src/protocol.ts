// shared/src/protocol.ts
export const PROTOCOL_VERSION = "2";

export type Mode = "raw" | "prompt";
export type Device = "mobile" | "mac";

export type ClientMessage =
  | { type: "hello"; protocolVersion: string; idToken: string; device: Device; sessionId?: string }
  | { type: "create_session"; protocolVersion: string }
  | { type: "join_session"; protocolVersion: string; sessionId: string }
  | { type: "transcript"; protocolVersion: string; text: string; mode: Mode; seq: number }
  | { type: "mode"; protocolVersion: string; mode: Mode }
  | { type: "ack"; protocolVersion: string; deliveryId: string }
  | { type: "ping"; protocolVersion: string; ts: number };

export type ServerErrorCode =
  | "unauthenticated"
  | "forbidden"
  | "protocol_version"
  | "rate_limit"
  | "not_found"
  | "bad_request"
  | "internal";

export type ServerMessage =
  | { type: "session_created"; protocolVersion: string; sessionId: string; joinUrl: string }
  | { type: "paired"; protocolVersion: string; sessionId: string; peerConnected: boolean }
  | { type: "final"; protocolVersion: string; text: string; mode: Mode; deliveryId: string; fallback?: boolean }
  | { type: "error"; protocolVersion: string; code: ServerErrorCode; message: string }
  | { type: "pong"; protocolVersion: string; ts: number };

export const isClientMessage = (value: unknown): value is ClientMessage => {
  if (!value || typeof value !== "object") return false;
  const obj = value as Record<string, unknown>;
  return typeof obj.type === "string" && typeof obj.protocolVersion === "string";
};
