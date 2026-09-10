import {
  engineInitialize, engineHostStart, engineHostSnapshot, engineHostApprove,
  engineHostRequestClose, engineHostClose, engineHostIdentity
} from 'rustdesk-ohrs';

export interface ModernHostSnapshot {
  phase: string;
  error: string | null;
  approval_request: string;
  approval_origin: string;
  width: number;
  height: number;
  fps: number;
  codec: string;
  connected: boolean;
  encrypted: boolean;
  sent_units: number;
  sent_bytes: number;
  closed: boolean;
}

export interface ModernHostIdentity {
  id: string;
  peer_signing_key_base64: string;
}

// Native lifecycle adapter, not a second implementation of the host protocol.
class ModernHostService {
  private id: string = '';
  private closePromise: Promise<void> | undefined = undefined;

  start(filesDir: string, width: number, height: number): void {
    if (this.id.length > 0 || this.closePromise !== undefined) {
      throw new Error('A host still owns native resources');
    }
    engineInitialize(filesDir);
    this.id = engineHostStart(width, height, 60);
  }

  hasHost(): boolean { return this.id.length > 0; }

  snapshot(): ModernHostSnapshot | undefined {
    if (this.id.length === 0) { return undefined; }
    const state: ModernHostSnapshot = JSON.parse(engineHostSnapshot(this.id)) as ModernHostSnapshot;
    if (!Number.isFinite(state.sent_units) || !Number.isFinite(state.width) || !Number.isFinite(state.height)) {
      throw new Error('Invalid native host snapshot');
    }
    return state;
  }

  publicIdentity(): ModernHostIdentity {
    return JSON.parse(engineHostIdentity()) as ModernHostIdentity;
  }

  approve(requestId: string, allow: boolean): boolean {
    return this.id.length > 0 && engineHostApprove(this.id, requestId, allow);
  }

  requestClose(): void {
    if (this.id.length > 0) {
      try { engineHostRequestClose(this.id); } catch { /* close is the ownership barrier */ }
    }
  }

  close(): Promise<void> {
    if (this.closePromise !== undefined) { return this.closePromise; }
    if (this.id.length === 0) { return Promise.resolve(); }
    this.requestClose();
    this.closePromise = this.finishClose(this.id);
    return this.closePromise;
  }

  private async finishClose(id: string): Promise<void> {
    await Promise.resolve();
    try {
      await engineHostClose(id);
      this.id = '';
    } finally {
      this.closePromise = undefined;
    }
  }
}

export const modernHost: ModernHostService = new ModernHostService();
