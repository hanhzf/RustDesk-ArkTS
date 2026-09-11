import {
  engineInitialize, engineConnect, engineConnectVerified, engineConnectId, engineSnapshot, engineMouse,
  engineClose, engineRequestClose, engineCapabilities
} from 'rustdesk-ohrs';

export interface ModernSnapshot {
  phase: string;
  error: string | null;
  width: number;
  height: number;
  codec: string;
  route: string;
  received_units: number;
  pushed_units: number;
  render_submissions: number;
  keyboard_allowed: boolean;
  encrypted: boolean;
  peer_verified: boolean;
  closed: boolean;
}

// UI adapter only. Auth, protocol, media scheduling and Surface ownership live
// in Core/HAR. No legacy runtime initialization or software pixel path.
class ModernSessionService {
  private id: string = '';
  private closePromise: Promise<void> | undefined = undefined;

  private normalizedFps(requestedFps: number): number {
    if (!Number.isFinite(requestedFps)) {
      return 60;
    }
    return Math.max(1, Math.min(120, Math.round(requestedFps)));
  }

  connect(filesDir: string, surfaceId: string, address: string, password: string,
    requestedFps: number): void {
    if (this.id.length > 0 || this.closePromise !== undefined) {
      throw new Error('A session still owns the Surface');
    }
    const localId: string = engineInitialize(filesDir);
    this.id = engineConnect(surfaceId, address.trim(), '', localId, 'RustDesk', password,
      this.normalizedFps(requestedFps));
  }

  connectVerified(filesDir: string, surfaceId: string, address: string, password: string,
    requestedFps: number, expectedPeerId: string, peerSigningKeyBase64: string): void {
    if (this.id.length > 0 || this.closePromise !== undefined) {
      throw new Error('A session still owns the Surface');
    }
    const localId: string = engineInitialize(filesDir);
    this.id = engineConnectVerified(surfaceId, address.trim(), '', localId, 'RustDesk', password,
      this.normalizedFps(requestedFps),
      expectedPeerId.trim(), peerSigningKeyBase64.trim());
  }

  connectId(filesDir: string, surfaceId: string, peerId: string, password: string,
    requestedFps: number): void {
    if (this.id.length > 0 || this.closePromise !== undefined) {
      throw new Error('A session still owns the Surface');
    }
    const localId: string = engineInitialize(filesDir);
    this.id = engineConnectId(surfaceId, peerId.trim(), localId, 'RustDesk', password,
      this.normalizedFps(requestedFps));
  }

  hasSession(): boolean {
    return this.id.length > 0;
  }

  snapshot(): ModernSnapshot | undefined {
    if (this.id.length === 0) {
      return undefined;
    }
    const snapshot: ModernSnapshot = JSON.parse(engineSnapshot(this.id)) as ModernSnapshot;
    if (!Number.isFinite(snapshot.width) || !Number.isFinite(snapshot.height) ||
      !Number.isFinite(snapshot.render_submissions) || !Number.isFinite(snapshot.pushed_units) ||
      !Number.isFinite(snapshot.received_units)) {
      throw new Error('Invalid native session snapshot');
    }
    return snapshot;
  }

  mouse(kind: number, button: number, x: number, y: number): boolean {
    return this.id.length > 0 && engineMouse(this.id, kind, button, x, y);
  }

  requestClose(): void {
    if (this.id.length > 0) {
      try {
        engineRequestClose(this.id);
      } catch {
        // May already be removed while the successful close Promise is settling.
        // Do not free/clear anything here: engineClose remains the confirmation.
      }
    }
  }

  close(): Promise<void> {
    if (this.closePromise !== undefined) {
      return this.closePromise;
    }
    if (this.id.length === 0) {
      return Promise.resolve();
    }
    const id: string = this.id;
    this.requestClose();
    this.closePromise = this.finishClose(id);
    return this.closePromise;
  }

  private async finishClose(id: string): Promise<void> {
    // Establish closePromise before a synchronous native exception can settle it.
    await Promise.resolve();
    try {
      await engineClose(id);
      // Never release the UI lease on failed/unconfirmed destruction.
      this.id = '';
    } finally {
      this.closePromise = undefined;
    }
  }

  capabilities(): Promise<string> {
    return engineCapabilities();
  }
}

export const modernSession: ModernSessionService = new ModernSessionService();
