import type { HostMessage, RendererMessage } from './types';

type MessageHandler = (message: HostMessage) => void;

const PORT_READY_TOKEN = '__GALAXY_PORT__';

export class GalaxyBridge {
  private port: MessagePort | null = null;
  private pendingMessages: string[] = [];
  private handlers = new Set<MessageHandler>();

  constructor() {
    window.addEventListener('message', (event: MessageEvent) => {
      const candidatePort = event.ports?.[0];
      if (event.data === PORT_READY_TOKEN && candidatePort) {
        this.attach(candidatePort);
        return;
      }
      const message = parseHostMessage(event.data);
      if (message) this.emit(message);
    });
  }

  onMessage(handler: MessageHandler): void {
    this.handlers.add(handler);
  }

  post(type: string, payload: RendererMessage['payload']): void {
    const serialized = JSON.stringify({ version: 1, type, payload });
    if (this.port) {
      this.port.postMessage(serialized);
      return;
    }
    this.pendingMessages.push(serialized);
    window.parent?.postMessage(serialized, '*');
  }

  private attach(port: MessagePort): void {
    this.port = port;
    port.onmessage = (event: MessageEvent) => {
      const message = parseHostMessage(event.data);
      if (message) this.emit(message);
    };
    port.start();
    for (const message of this.pendingMessages) {
      port.postMessage(message);
    }
    this.pendingMessages = [];
  }

  private emit(message: HostMessage): void {
    for (const handler of this.handlers) handler(message);
  }
}

function parseHostMessage(value: unknown): HostMessage | null {
  let candidate: unknown = value;
  if (typeof value === 'string') {
    try {
      candidate = JSON.parse(value) as unknown;
    } catch {
      return null;
    }
  }
  if (!candidate || typeof candidate !== 'object') return null;
  const envelope = candidate as Partial<HostMessage>;
  if (envelope.version !== 1 || typeof envelope.type !== 'string' || !envelope.payload) return null;
  return envelope as HostMessage;
}
