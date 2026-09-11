import { bundleManager, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  DecoderCandidateSnapshot, projectDecoderCandidateSnapshot, unavailableDecoderCandidateSnapshot
} from './DecoderCandidateSnapshot';
import {
  runtimeGetDecoderCapabilities,
  runtimeStartNativeBufferProbe, runtimePollNativeBufferProbe,
  runtimeStartGlesBufferProbe, runtimePollGlesBufferProbe,
  runtimeStartEncoderInputProbe, runtimePollEncoderInputProbe,
  runtimeStartCaptureInputProbe, runtimePollCaptureInputProbe, runtimeStopCaptureInputProbe
} from 'rustdesk-ohrs';

const DOMAIN = 0xFF00;
const TAG = 'RustDeskZeroCopyProbe';
const WANT_KEY = 'rustdesk.nativeBufferProbe';
const GLES_WANT_KEY = 'rustdesk.glesBufferProbe';
const ENCODER_WANT_KEY = 'rustdesk.encoderInputProbe';
const CAPTURE_WANT_KEY = 'rustdesk.captureInputProbe';
const POLL_INTERVAL_MS = 300;
const POLL_DEADLINE_MS = 12000;
const MAX_POLLS = 40;

interface NativeBufferProbeSnapshot {
  state: string;
  stage: string;
  terminal: boolean;
  workerMayStillBeRunning: boolean;
  elapsedMs: number;
  detail: string;
}

interface BufferProbeLogSnapshot extends NativeBufferProbeSnapshot {
  probeKind: string;
}

/** Explicit debug-only diagnostics; capture observation never starts or authorizes capture. */
export class NativeBufferDiagnosticService {
  // Never reset on Ability recreation, destruction, timeout or native exceptions.
  private static processAttempted: boolean = false;
  private destroyed: boolean = false;
  private checkingDebug: boolean = false;
  private probeKind: string = 'native_buffer';
  private timer: number | undefined = undefined;
  private startedAt: number = 0;
  private pollCount: number = 0;
  private lastState: string = '';
  private lastStage: string = '';
  private captureAttempted: boolean = false;
  private captureStopRequested: boolean = false;

  handleWant(want: Want): void {
    if (this.destroyed || this.checkingDebug || NativeBufferDiagnosticService.processAttempted) {
      return;
    }
    // Want.parameters is SDK Record<string, Object>; no coercion of numeric/bool values.
    const trigger: Object | undefined = want.parameters?.[WANT_KEY];
    const glesTrigger: Object | undefined = want.parameters?.[GLES_WANT_KEY];
    const encoderTrigger: Object | undefined = want.parameters?.[ENCODER_WANT_KEY];
    const captureTrigger: Object | undefined = want.parameters?.[CAPTURE_WANT_KEY];
    const nativeRequested: boolean = typeof trigger === 'string' && trigger === '1';
    const glesRequested: boolean = typeof glesTrigger === 'string' && glesTrigger === '1';
    const encoderRequested: boolean = typeof encoderTrigger === 'string' && encoderTrigger === '1';
    const captureRequested: boolean = typeof captureTrigger === 'string' && captureTrigger === '1';
    // Reject both absent/invalid and ambiguous requests without consuming the attempt.
    const requestedCount: number = (nativeRequested ? 1 : 0) + (glesRequested ? 1 : 0) +
      (encoderRequested ? 1 : 0) + (captureRequested ? 1 : 0);
    if (requestedCount !== 1) {
      return;
    }
    // Select before the await; checkingDebug and processAttempted prevent later Want switches.
    this.probeKind = captureRequested ? 'capture_input' :
      (encoderRequested ? 'encoder_input' : (glesRequested ? 'gles_buffer' : 'native_buffer'));
    this.checkingDebug = true;
    void this.startIfDebug();
  }

  destroy(): void {
    this.destroyed = true;
    this.requestCaptureStop();
    if (this.timer !== undefined) {
      this.stopWithSummary('ability_destroyed', 'Polling stopped; native worker exit and cleanup are not confirmed.');
    }
    this.clearTimer();
  }

  private async startIfDebug(): Promise<void> {
    try {
      // ApplicationInfo.debug is a readonly boolean since API 10, not appProvisionType.
      const info: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      if (this.destroyed || NativeBufferDiagnosticService.processAttempted || info.appInfo.debug !== true) {
        return;
      }
      NativeBufferDiagnosticService.processAttempted = true;
      this.logDecoderCandidateSnapshot();
      this.startedAt = Date.now();
      // HAR returns promptly; its worker owns the probe and the 10-second terminal deadline.
      this.queryNative(true);
    } catch (_) {
      if (!this.destroyed) {
        const attempted: boolean = NativeBufferDiagnosticService.processAttempted;
        this.stopWithSummary(attempted ? 'diagnostic_start_failed' : 'debug_query_failed',
          attempted ? 'Diagnostic setup failed after start was attempted; native cleanup is not confirmed.' :
            'Debug application information unavailable; probe not started.', attempted);
      }
    } finally {
      this.checkingDebug = false;
    }
  }

  private logDecoderCandidateSnapshot(): void {
    let snapshot: DecoderCandidateSnapshot = unavailableDecoderCandidateSnapshot();
    try {
      snapshot = projectDecoderCandidateSnapshot(runtimeGetDecoderCapabilities());
    } catch (_) {
      // Metadata failure must not change probe or capture state.
    }
    try {
      hilog.info(DOMAIN, 'RustDeskDecoderCandidate', 'decoder_candidate %{public}s', JSON.stringify(snapshot));
    } catch (_) {
      // Logging is independent of the diagnostic start and its deadline.
    }
  }

  private queryNative(start: boolean): void {
    let json: string;
    try {
      // GLES uses independent public GL resources, never a fallback for denied NativeBuffer ioctls.
      if (this.probeKind === 'capture_input') {
        // Native also checks that the normal authorized capture is already active.
        // A diagnostic Want never enables the host, requests permissions or starts recording.
        if (start) {
          this.captureAttempted = true;
        }
        json = start ? runtimeStartCaptureInputProbe() : runtimePollCaptureInputProbe();
      } else if (this.probeKind === 'encoder_input') {
        json = start ? runtimeStartEncoderInputProbe() : runtimePollEncoderInputProbe();
      } else if (this.probeKind === 'gles_buffer') {
        json = start ? runtimeStartGlesBufferProbe() : runtimePollGlesBufferProbe();
      } else {
        json = start ? runtimeStartNativeBufferProbe() : runtimePollNativeBufferProbe();
      }
    } catch (_) {
      this.stopWithSummary(start ? 'native_start_exception' : 'native_poll_exception',
        'Native diagnostic call threw; polling stopped, worker cleanup is not confirmed.');
      return;
    }
    try {
      const snapshot: NativeBufferProbeSnapshot | null = JSON.parse(json) as NativeBufferProbeSnapshot | null;
      if (snapshot === null || typeof snapshot.state !== 'string' || typeof snapshot.stage !== 'string' ||
        typeof snapshot.terminal !== 'boolean' || typeof snapshot.workerMayStillBeRunning !== 'boolean' ||
        typeof snapshot.elapsedMs !== 'number' || !Number.isFinite(snapshot.elapsedMs) || snapshot.elapsedMs < 0 ||
        typeof snapshot.detail !== 'string') {
        this.stopWithSummary('invalid_native_snapshot', 'Invalid diagnostic snapshot; polling stopped, cleanup is not confirmed.');
        return;
      }
      if (snapshot.state !== this.lastState || snapshot.stage !== this.lastStage || snapshot.terminal) {
        // Only safe diagnostic metadata; never raw JSON, pixels, Wants, bundle info or exceptions.
        const safe: NativeBufferProbeSnapshot = {
          state: snapshot.state,
          stage: snapshot.stage,
          terminal: snapshot.terminal,
          workerMayStillBeRunning: snapshot.workerMayStillBeRunning,
          elapsedMs: snapshot.elapsedMs,
          detail: this.probeKind === 'native_buffer' && snapshot.state === 'passed_cpu_probe' ?
            'Synthetic allocated-pixel CPU probe passed only; NOT GPU zero-copy evidence.' : snapshot.detail
        };
        this.logSnapshot(safe);
        this.lastState = snapshot.state;
        this.lastStage = snapshot.stage;
      }
      // Logical capture cancellation can be terminal while a native call still
      // owns leases. Continue bounded polling for actual worker-exit evidence.
      if (snapshot.terminal && (this.probeKind !== 'capture_input' || !snapshot.workerMayStillBeRunning)) {
        this.requestCaptureStop();
        this.clearTimer();
        return;
      }
    } catch (_) {
      this.stopWithSummary('invalid_native_json', 'Diagnostic JSON could not be decoded; polling stopped, cleanup is not confirmed.');
      return;
    }
    this.timer = setTimeout((): void => {
      this.timer = undefined;
      if (this.destroyed) {
        return;
      }
      this.pollCount += 1;
      // Count also bounds polling if wall time moves backwards.
      if (Date.now() - this.startedAt >= POLL_DEADLINE_MS || this.pollCount >= MAX_POLLS) {
        this.stopWithSummary('local_poll_deadline', 'Local polling deadline reached; native worker exit and cleanup are not confirmed.');
        return;
      }
      this.queryNative(false);
    }, POLL_INTERVAL_MS);
  }

  private stopWithSummary(stage: string, detail: string, workerMayStillBeRunning: boolean = true): void {
    this.requestCaptureStop();
    this.clearTimer();
    const summary: NativeBufferProbeSnapshot = {
      state: 'arkts_polling_stopped',
      stage: stage,
      // A local stop is NOT a native terminal result or proof of released native resources.
      terminal: false,
      workerMayStillBeRunning: workerMayStillBeRunning,
      elapsedMs: this.startedAt === 0 ? 0 : Math.max(0, Date.now() - this.startedAt),
      detail: detail + (this.captureStopRequested ? ' Diagnostic cancellation requested; capture itself is unchanged.' : '')
    };
    this.logSnapshot(summary);
  }

  private clearTimer(): void {
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private requestCaptureStop(): void {
    if (!this.captureAttempted || this.captureStopRequested) {
      return;
    }
    this.captureStopRequested = true;
    try {
      // Only requests diagnostic cancellation; worker alone releases its frame leases.
      // The result is not proof that codec calls have returned or cleanup finished.
      runtimeStopCaptureInputProbe();
    } catch (_) {
      // Never expose exception contents or pretend native cancellation succeeded.
    }
  }

  private logSnapshot(snapshot: NativeBufferProbeSnapshot): void {
    const safe: BufferProbeLogSnapshot = {
      state: snapshot.state,
      stage: snapshot.stage,
      terminal: snapshot.terminal,
      workerMayStillBeRunning: snapshot.workerMayStillBeRunning,
      elapsedMs: snapshot.elapsedMs,
      detail: snapshot.detail,
      probeKind: this.probeKind
    };
    hilog.info(DOMAIN, TAG, '%{public}s', JSON.stringify(safe));
  }
}
