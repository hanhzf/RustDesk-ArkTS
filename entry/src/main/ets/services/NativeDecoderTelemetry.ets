import { FrameRateSnapshot } from './FrameRateTelemetry';

// Read-only counters: callbacks and render acceptance do not prove physical presentation.
export class NativeDecoderSnapshot {
  available: boolean = false;
  active: boolean = false;
  state: string = 'unavailable';
  generation: string = '';
  elapsedMs: number = 0;
  codec: string = 'unknown';
  width: number | null = null;
  height: number | null = null;
  acceptedPackets: number = 0;
  acceptedBytes: number = 0;
  inputRejected: number = 0;
  inputWaits: number = 0;
  inputTimeouts: number = 0;
  outputBuffers: number = 0;
  outputMetadataErrors: number = 0;
  outputEosBuffers: number = 0;
  outputCodecConfigBuffers: number = 0;
  outputOtherBuffers: number = 0;
  mediaOutputBuffers: number = 0;
  renderSubmittedBuffers: number = 0;
  renderFailedBuffers: number = 0;
  outputQueueDepth: number = 0;
  outputQueueHighWater: number = 0;
  formatChanges: number = 0;
  decoderErrors: number = 0;
  inputWaitCalls: number = 0;
  inputWaitNs: number = 0;
  inputWaitMaxNs: number = 0;
  pushCalls: number = 0;
  pushNs: number = 0;
  pushMaxNs: number = 0;
  renderCalls: number = 0;
  renderNs: number = 0;
  renderMaxNs: number = 0;
  renderInFlight: number = 0;
}

function counts(value: NativeDecoderSnapshot): number[] {
  // Generation high-water marks must also be monotonic. renderInFlight and
  // outputQueueDepth are gauges and deliberately excluded from this list.
  return [value.acceptedPackets, value.acceptedBytes, value.inputRejected, value.inputWaits,
    value.inputTimeouts, value.outputBuffers, value.outputMetadataErrors, value.outputEosBuffers,
    value.outputCodecConfigBuffers, value.outputOtherBuffers, value.mediaOutputBuffers,
    value.renderSubmittedBuffers, value.renderFailedBuffers, value.outputQueueHighWater,
    value.formatChanges, value.decoderErrors,
    value.inputWaitCalls, value.inputWaitNs, value.inputWaitMaxNs,
    value.pushCalls, value.pushNs, value.pushMaxNs,
    value.renderCalls, value.renderNs, value.renderMaxNs];
}

function safeCount(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

function safeDimension(value: number | null): boolean {
  return value === null || (safeCount(value) && value > 0 && value <= 65536);
}

export function parseNativeDecoderSnapshot(raw: string): NativeDecoderSnapshot | undefined {
  try {
    const value = JSON.parse(raw) as NativeDecoderSnapshot;
    if (!value || typeof value.available !== 'boolean' || typeof value.active !== 'boolean'
      || !safeCount(value.elapsedMs)) {
      return undefined;
    }
    // Unavailable is intentionally sparse; do not read counters that are absent.
    if (!value.available) {
      if (value.active || value.state !== 'unavailable' || value.codec !== 'unknown'
        || value.generation !== '' || value.width !== null || value.height !== null) {
        return undefined;
      }
      const unavailable = new NativeDecoderSnapshot();
      unavailable.elapsedMs = value.elapsedMs;
      return unavailable;
    }
    if (!['running', 'failed'].includes(value.state) || !['h264', 'h265'].includes(value.codec)
      || typeof value.generation !== 'string'
      || !(value.generation === '' || /^(0|[1-9][0-9]*)$/.test(value.generation))
      || !safeDimension(value.width) || !safeDimension(value.height)
      || (value.width === null) !== (value.height === null)
      || !safeCount(value.outputQueueDepth) || !safeCount(value.outputQueueHighWater)
      || !safeCount(value.renderInFlight) || value.renderInFlight > 1) {
      return undefined;
    }
    for (const count of counts(value)) {
      // JSON.parse does not initialize class defaults: missing timing keys in
      // an older/incomplete available schema fail closed instead of becoming 0.
      if (!safeCount(count)) {
        return undefined;
      }
    }
    // Explicit whitelist; reason, identities and extra JSON fields are never retained.
    const result = new NativeDecoderSnapshot();
    result.available = value.available;
    result.active = value.active;
    result.state = value.state;
    result.generation = value.generation;
    result.elapsedMs = value.elapsedMs;
    result.codec = value.codec;
    result.width = value.width;
    result.height = value.height;
    result.acceptedPackets = value.acceptedPackets;
    result.acceptedBytes = value.acceptedBytes;
    result.inputRejected = value.inputRejected;
    result.inputWaits = value.inputWaits;
    result.inputTimeouts = value.inputTimeouts;
    result.outputBuffers = value.outputBuffers;
    result.outputMetadataErrors = value.outputMetadataErrors;
    result.outputEosBuffers = value.outputEosBuffers;
    result.outputCodecConfigBuffers = value.outputCodecConfigBuffers;
    result.outputOtherBuffers = value.outputOtherBuffers;
    result.mediaOutputBuffers = value.mediaOutputBuffers;
    result.renderSubmittedBuffers = value.renderSubmittedBuffers;
    result.renderFailedBuffers = value.renderFailedBuffers;
    result.outputQueueDepth = value.outputQueueDepth;
    result.outputQueueHighWater = value.outputQueueHighWater;
    result.formatChanges = value.formatChanges;
    result.decoderErrors = value.decoderErrors;
    result.inputWaitCalls = value.inputWaitCalls;
    result.inputWaitNs = value.inputWaitNs;
    result.inputWaitMaxNs = value.inputWaitMaxNs;
    result.pushCalls = value.pushCalls;
    result.pushNs = value.pushNs;
    result.pushMaxNs = value.pushMaxNs;
    result.renderCalls = value.renderCalls;
    result.renderNs = value.renderNs;
    result.renderMaxNs = value.renderMaxNs;
    result.renderInFlight = value.renderInFlight;
    return result;
  } catch (_) {
    return undefined;
  }
}

export class NativeDecoderWindowLog {
  route: string = 'native_surface';
  status: string = 'invalid';
  codec: string = '';
  // Core intent only, never inferred from native enqueue rate.
  desiredFps: number | null = null;
  windowMs: number | null = null;
  inputAcceptedPerSec: number | null = null;
  inputBytesPerSec: number | null = null;
  outputCallbacksPerSec: number | null = null;
  mediaOutputsPerSec: number | null = null;
  renderAcceptedPerSec: number | null = null;
  renderFailuresPerSec: number | null = null;
  metadataErrorsPerSec: number | null = null;
  eosPerSec: number | null = null;
  configPerSec: number | null = null;
  otherPerSec: number | null = null;
  inputWaitsPerSec: number | null = null;
  inputRejectedPerSec: number | null = null;
  inputTimeoutsPerSec: number | null = null;
  formatChangesPerSec: number | null = null;
  decoderErrorsPerSec: number | null = null;
  outputQueueDepth: number | null = null;
  outputQueueHighWater: number | null = null;
  // Last post-handle compressed-message ArrayQueue snapshot; excludes the current
  // group, mpsc, driver and Surface queues. Sample age is unknown, not proven live.
  lastPostHandleQueueLen: number | null = null;
  actualOutputWidth: number | null = null;
  actualOutputHeight: number | null = null;
  // Completion-accounted durations, including failed calls. A call crossing a
  // window contributes its full duration on completion, not window occupancy,
  // busy percentage or frame age. HighWaterMs is lifetime within this decoder
  // generation, NOT a window maximum. Missing/invalid/warmup stays null.
  completedInputWaitMs: number | null = null;
  inputWaitAvgMs: number | null = null;
  inputWaitHighWaterMs: number | null = null;
  completedPushMs: number | null = null;
  pushAvgMs: number | null = null;
  pushHighWaterMs: number | null = null;
  completedRenderMs: number | null = null;
  renderAvgMs: number | null = null;
  renderHighWaterMs: number | null = null;
  renderInFlight: number | null = null;
}

function rate(current: number, previous: number, windowMs: number): number {
  return Math.round((current - previous) / windowMs * 1000000) / 1000;
}

export class NativeDecoderTelemetry {
  private binding: string = '';
  private intentRevision: string = '';
  private intentGeneration: string = '';
  private desiredFps: number | null = null;
  private baseline: NativeDecoderSnapshot | undefined = undefined;
  private lastObserved: NativeDecoderSnapshot | undefined = undefined;

  reset(): void {
    this.binding = '';
    this.intentRevision = '';
    this.intentGeneration = '';
    this.desiredFps = null;
    this.baseline = undefined;
    this.lastObserved = undefined;
  }

  sample(raw: string, binding: string, intent: FrameRateSnapshot | undefined): string {
    const result = new NativeDecoderWindowLog();
    const current = parseNativeDecoderSnapshot(raw);
    result.desiredFps = intent?.desiredFps ?? null;
    result.codec = current?.codec ?? '';
    if (current === undefined || binding.length === 0) {
      this.reset();
      return JSON.stringify(result);
    }
    if (current.state === 'failed' || current.state === 'unavailable'
      || !current.available || !current.active) {
      result.status = current.state === 'failed' ? 'failed'
        : (current.state === 'unavailable' || !current.available ? 'unavailable' : 'inactive');
      this.reset();
      return JSON.stringify(result);
    }
    if (intent === undefined || !intent.available || intent.desiredFps === null
      || current.generation.length === 0) {
      this.reset();
      result.status = intent !== undefined && intent.desiredFps === null ? 'paused' : 'invalid';
      return JSON.stringify(result);
    }
    if (binding !== this.binding || intent.intentRevision !== this.intentRevision
      || intent.generation !== this.intentGeneration || intent.desiredFps !== this.desiredFps) {
      this.reset();
      this.binding = binding;
      this.intentRevision = intent.intentRevision;
      this.intentGeneration = intent.generation;
      this.desiredFps = intent.desiredFps;
    }
    const previous = this.baseline;
    const lastObserved = this.lastObserved;
    this.lastObserved = current;
    result.status = 'warming_up';
    if (previous === undefined || current.generation !== previous.generation
      || current.codec !== previous.codec || current.elapsedMs <= previous.elapsedMs
      || (lastObserved !== undefined && current.elapsedMs <= lastObserved.elapsedMs)) {
      this.baseline = current;
      return JSON.stringify(result);
    }
    const currentCounts = counts(current);
    const lastCounts = counts(lastObserved ?? previous);
    for (let index = 0; index < currentCounts.length; index += 1) {
      if (currentCounts[index] < lastCounts[index]) {
        this.baseline = current;
        return JSON.stringify(result);
      }
    }
    const windowMs = current.elapsedMs - previous.elapsedMs;
    if (windowMs > 2500) {
      this.baseline = current;
      return JSON.stringify(result);
    }
    if (windowMs < 1000) {
      return JSON.stringify(result);
    }
    this.baseline = current;
    result.status = 'running';
    result.windowMs = windowMs;
    result.inputAcceptedPerSec = rate(current.acceptedPackets, previous.acceptedPackets, windowMs);
    result.inputBytesPerSec = rate(current.acceptedBytes, previous.acceptedBytes, windowMs);
    result.outputCallbacksPerSec = rate(current.outputBuffers, previous.outputBuffers, windowMs);
    result.mediaOutputsPerSec = rate(current.mediaOutputBuffers, previous.mediaOutputBuffers, windowMs);
    result.renderAcceptedPerSec = rate(current.renderSubmittedBuffers, previous.renderSubmittedBuffers, windowMs);
    result.renderFailuresPerSec = rate(current.renderFailedBuffers, previous.renderFailedBuffers, windowMs);
    result.metadataErrorsPerSec = rate(current.outputMetadataErrors, previous.outputMetadataErrors, windowMs);
    // EOS/config may overlap: do not assume a classification sum or physical frames.
    result.eosPerSec = rate(current.outputEosBuffers, previous.outputEosBuffers, windowMs);
    result.configPerSec = rate(current.outputCodecConfigBuffers, previous.outputCodecConfigBuffers, windowMs);
    result.otherPerSec = rate(current.outputOtherBuffers, previous.outputOtherBuffers, windowMs);
    result.inputWaitsPerSec = rate(current.inputWaits, previous.inputWaits, windowMs);
    result.inputRejectedPerSec = rate(current.inputRejected, previous.inputRejected, windowMs);
    result.inputTimeoutsPerSec = rate(current.inputTimeouts, previous.inputTimeouts, windowMs);
    result.formatChangesPerSec = rate(current.formatChanges, previous.formatChanges, windowMs);
    result.decoderErrorsPerSec = rate(current.decoderErrors, previous.decoderErrors, windowMs);
    result.outputQueueDepth = current.outputQueueDepth;
    result.outputQueueHighWater = current.outputQueueHighWater;
    result.lastPostHandleQueueLen = safeCount(intent.queueLen) ? intent.queueLen : null;
    result.actualOutputWidth = current.width;
    result.actualOutputHeight = current.height;
    result.completedInputWaitMs = (current.inputWaitNs - previous.inputWaitNs) / 1000000;
    const inputWaitCalls = current.inputWaitCalls - previous.inputWaitCalls;
    result.inputWaitAvgMs = inputWaitCalls === 0 ? null
      : (current.inputWaitNs - previous.inputWaitNs) / inputWaitCalls / 1000000;
    result.inputWaitHighWaterMs = current.inputWaitMaxNs / 1000000;
    result.completedPushMs = (current.pushNs - previous.pushNs) / 1000000;
    const pushCalls = current.pushCalls - previous.pushCalls;
    result.pushAvgMs = pushCalls === 0 ? null
      : (current.pushNs - previous.pushNs) / pushCalls / 1000000;
    result.pushHighWaterMs = current.pushMaxNs / 1000000;
    result.completedRenderMs = (current.renderNs - previous.renderNs) / 1000000;
    const renderCalls = current.renderCalls - previous.renderCalls;
    result.renderAvgMs = renderCalls === 0 ? null
      : (current.renderNs - previous.renderNs) / renderCalls / 1000000;
    result.renderHighWaterMs = current.renderMaxNs / 1000000;
    result.renderInFlight = current.renderInFlight;
    return JSON.stringify(result);
  }
}
