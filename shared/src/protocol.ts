export type Mode = "raw" | "prompt";
export type Device = "mobile" | "mac";
export type WidgetState = "idle" | "receiving" | "ready" | "error";

export type ClientMessage =
  | { type: "pair"; sessionId: string; device: Device }
  | { type: "start"; mode: Mode; mimeType?: string; language?: string }
  | { type: "audio"; seq: number; chunk: string }
  | { type: "stop" }
  | { type: "ack"; deliveryId: string }
  | { type: "mode"; mode: Mode }
  | { type: "ping"; ts: number };

export type ServerMessage =
  | { type: "paired"; sessionId: string; peerConnected: boolean }
  | { type: "state"; value: WidgetState }
  | { type: "partial"; text: string }
  | { type: "final"; text: string; mode: Mode; deliveryId: string; replayed?: boolean }
  | { type: "session"; sessionId: string; joinUrl: string }
  | { type: "error"; message: string }
  | { type: "pong"; ts: number };

export const isClientMessage = (value: unknown): value is ClientMessage => {
  if (!value || typeof value !== "object") return false;
  const type = (value as { type?: unknown }).type;
  return typeof type === "string";
};
