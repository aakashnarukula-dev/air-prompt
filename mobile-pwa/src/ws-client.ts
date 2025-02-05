import { PROTOCOL_VERSION, type ClientMessage, type ServerMessage } from "../../shared/src/protocol.js";

export interface WsClientEvents {
  onPaired: (sessionId: string, peerConnected: boolean) => void;
  onFinal: (text: string, mode: "raw" | "prompt", deliveryId: string, fallback: boolean) => void;
  onError: (code: string, message: string) => void;
  onClose: () => void;
}

export class WsClient {
  private socket: WebSocket | null = null;
  private events: WsClientEvents | null = null;

  async connect(url: string, idToken: string, device: "mobile" | "mac", sessionId: string | undefined, events: WsClientEvents) {
    this.events = events;
    const socket = new WebSocket(url);
    this.socket = socket;
    socket.addEventListener("open", () => {
      this.send({
        type: "hello",
        protocolVersion: PROTOCOL_VERSION,
        idToken,
        device,
        sessionId,
      });
    });
    socket.addEventListener("message", (e) => {
      try {
        const msg = JSON.parse(e.data) as ServerMessage;
        this.handle(msg);
      } catch {
        // ignore
      }
    });
    socket.addEventListener("close", () => events.onClose());
  }

  joinSession(sessionId: string) {
    this.send({ type: "join_session", protocolVersion: PROTOCOL_VERSION, sessionId });
  }

  sendTranscript(text: string, mode: "raw" | "prompt", seq: number) {
    this.send({ type: "transcript", protocolVersion: PROTOCOL_VERSION, text, mode, seq });
  }

  sendMode(mode: "raw" | "prompt") {
    this.send({ type: "mode", protocolVersion: PROTOCOL_VERSION, mode });
  }

  ack(deliveryId: string) {
    this.send({ type: "ack", protocolVersion: PROTOCOL_VERSION, deliveryId });
  }

  close() {
    this.socket?.close();
  }

  private send(msg: ClientMessage) {
    if (this.socket?.readyState !== WebSocket.OPEN) return;
    this.socket.send(JSON.stringify(msg));
  }

  private handle(msg: ServerMessage) {
    if (!this.events) return;
    switch (msg.type) {
      case "paired":
        this.events.onPaired(msg.sessionId, msg.peerConnected);
        break;
      case "final":
        this.events.onFinal(msg.text, msg.mode, msg.deliveryId, msg.fallback ?? false);
        break;
      case "error":
        this.events.onError(msg.code, msg.message);
        break;
    }
  }
}
