import { PROTOCOL_VERSION, isClientMessage, type ClientMessage, type ServerErrorCode } from "../../../shared/src/protocol.js";

export type ParseResult =
  | { ok: true; msg: ClientMessage }
  | { ok: false; code: ServerErrorCode; message: string };

export function parseClientMessage(raw: string | Buffer): ParseResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw.toString());
  } catch {
    return { ok: false, code: "bad_request", message: "malformed JSON" };
  }
  if (!isClientMessage(parsed)) {
    return { ok: false, code: "bad_request", message: "invalid message shape" };
  }
  if (parsed.protocolVersion !== PROTOCOL_VERSION) {
    return { ok: false, code: "protocol_version", message: `unsupported protocol: ${parsed.protocolVersion}` };
  }
  return { ok: true, msg: parsed };
}
