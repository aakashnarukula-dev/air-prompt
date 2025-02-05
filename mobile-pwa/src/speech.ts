interface SpeechRecognitionLike {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((e: any) => void) | null;
  onerror: ((e: any) => void) | null;
  onend: (() => void) | null;
}

export interface SpeechEvents {
  onInterim: (text: string) => void;
  onFinal: (text: string) => void;
  onError: (error: string) => void;
  onEnd: () => void;
}

export class SpeechRecognizer {
  private rec: SpeechRecognitionLike | null = null;
  private running = false;

  static isSupported(): boolean {
    const w = window as any;
    return Boolean(w.SpeechRecognition || w.webkitSpeechRecognition);
  }

  start(events: SpeechEvents, lang = "en-US") {
    if (this.running) return;
    const w = window as any;
    const Ctor = w.SpeechRecognition || w.webkitSpeechRecognition;
    if (!Ctor) {
      events.onError("Web Speech API not supported");
      return;
    }
    const rec: SpeechRecognitionLike = new Ctor();
    rec.continuous = true;
    rec.interimResults = true;
    rec.lang = lang;
    rec.onresult = (e: any) => {
      let interim = "";
      for (let i = e.resultIndex; i < e.results.length; i++) {
        const result = e.results[i];
        const text = result[0].transcript;
        if (result.isFinal) {
          events.onFinal(text.trim());
        } else {
          interim += text;
        }
      }
      if (interim) events.onInterim(interim.trim());
    };
    rec.onerror = (e: any) => events.onError(e.error ?? "speech error");
    rec.onend = () => {
      this.running = false;
      events.onEnd();
    };
    this.rec = rec;
    this.running = true;
    rec.start();
  }

  stop() {
    if (!this.running) return;
    this.rec?.stop();
    this.running = false;
  }
}
