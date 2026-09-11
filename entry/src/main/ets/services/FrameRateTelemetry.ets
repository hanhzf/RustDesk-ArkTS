// Read-only metadata. Never sends quality/FPS policy or participates in presentation.
export class FrameRateRecommendation {
  qualityScalePermille: number = 1000;
  sequence: number = 0;
}

export class FrameRateSnapshot {
  available: boolean = false;
  generation: string = '0';
  intentRevision: string = '0';
  desiredFps: number | null = null;
  safetyFpsCap: number | null = null;
  elapsedMs: number = 0;
  receivedPackets: number = 0;
  decodedFrames: number = 0;
  submittedFrames: number = 0;
  unavailableFrames: number = 0;
  noBufferFrames: number = 0;
  busyFrames: number = 0;
  decodeCalls: number = 0;
  decodeNs: number = 0;
  conversionCalls: number = 0;
  conversionNs: number = 0;
  targetCalls: number = 0;
  targetNs: number = 0;
  queueLen: number = 0;
  decodeCapacityFps: number | null = null;
  status: string = 'unavailable';
  recommendation: FrameRateRecommendation | null = null;
  qualityRecommendationApplied: boolean = false;
}

function cumulativeCounters(value: FrameRateSnapshot): number[] {
  return [value.receivedPackets, value.decodedFrames, value.submittedFrames,
    value.unavailableFrames, value.noBufferFrames, value.busyFrames, value.decodeCalls,
    value.decodeNs, value.conversionCalls, value.conversionNs, value.targetCalls, value.targetNs];
}

function safeCount(value: number): boolean {
  return Number.isSafeInteger(value) && value >= 0;
}

export function parseFrameRateSnapshot(raw: string): FrameRateSnapshot | undefined {
  try {
    const value = JSON.parse(raw) as FrameRateSnapshot;
    if (!value || typeof value.available !== 'boolean'
      || typeof value.generation !== 'string' || !/^(0|[1-9][0-9]{0,19})$/.test(value.generation)
      || typeof value.intentRevision !== 'string' || !/^(0|[1-9][0-9]{0,19})$/.test(value.intentRevision)
      || (value.desiredFps !== null
        && (!safeCount(value.desiredFps) || value.desiredFps === 0 || value.desiredFps > 120))
      || (value.safetyFpsCap !== null && (!safeCount(value.safetyFpsCap)
        || value.safetyFpsCap < 1 || value.safetyFpsCap > 120
        || value.desiredFps === null || value.safetyFpsCap > value.desiredFps))
      || !safeCount(value.elapsedMs) || !safeCount(value.queueLen)
      || (value.decodeCapacityFps !== null
        && (!Number.isFinite(value.decodeCapacityFps) || value.decodeCapacityFps < 0
          || value.decodeCapacityFps > Number.MAX_SAFE_INTEGER))
      || typeof value.status !== 'string' || value.status.length > 64
      || !/^[a-z]+(?:_[a-z0-9]+)*$/.test(value.status)
      || value.qualityRecommendationApplied !== false) {
      return undefined;
    }
    for (const count of cumulativeCounters(value)) {
      if (!safeCount(count)) {
        return undefined;
      }
    }
    const recommendation = value.recommendation;
    if (recommendation !== null && (!recommendation
      || !safeCount(recommendation.sequence) || !safeCount(recommendation.qualityScalePermille)
      || recommendation.qualityScalePermille < 1 || recommendation.qualityScalePermille > 1000)) {
      return undefined;
    }
    // Project known fields, never preserve unexpected metadata for later logging.
    const result = new FrameRateSnapshot();
    result.available = value.available;
    result.generation = value.generation;
    result.intentRevision = value.intentRevision;
    result.desiredFps = value.desiredFps;
    result.safetyFpsCap = value.safetyFpsCap;
    result.elapsedMs = value.elapsedMs;
    result.receivedPackets = value.receivedPackets;
    result.decodedFrames = value.decodedFrames;
    result.submittedFrames = value.submittedFrames;
    result.unavailableFrames = value.unavailableFrames;
    result.noBufferFrames = value.noBufferFrames;
    result.busyFrames = value.busyFrames;
    result.decodeCalls = value.decodeCalls;
    result.decodeNs = value.decodeNs;
    result.conversionCalls = value.conversionCalls;
    result.conversionNs = value.conversionNs;
    result.targetCalls = value.targetCalls;
    result.targetNs = value.targetNs;
    result.queueLen = value.queueLen;
    result.decodeCapacityFps = value.decodeCapacityFps;
    result.status = value.status;
    if (recommendation !== null) {
      result.recommendation = new FrameRateRecommendation();
      result.recommendation.qualityScalePermille = recommendation.qualityScalePermille;
      result.recommendation.sequence = recommendation.sequence;
    }
    return result;
  } catch (_) {
    return undefined;
  }
}

// Deliberately excludes identities, epochs, raw metadata, cumulative rates and policy actions.
export class FrameRateWindowLog {
  // Client intent and current safety limit, NOT observed or negotiated Mac FPS.
  desiredFps: number | null = null;
  safetyFpsCap: number | null = null;
  windowMs: number = 0;
  receivedPacketRate: number = 0;
  decodedFps: number = 0;
  submittedFps: number = 0;
  unavailableFps: number = 0;
  noBufferFps: number = 0;
  busyFps: number = 0;
  decodeAvgMs: number | null = null;
  conversionAvgMs: number | null = null;
  targetIncludingConversionAvgMs: number | null = null;
  // Amortized work per decoder output, not end-to-end latency. decodeAvgMs
  // above is per decode/flush call, which need not correspond to one output.
  decodeWorkMsPerOutput: number | null = null;
  targetWorkMsPerOutput: number | null = null;
  // Last accepted software submission, not mode/Surface size or every output
  // in this window. The caller clears its metadata on binding/route changes.
  lastSoftwareSubmittedWidth: number | null = null;
  lastSoftwareSubmittedHeight: number | null = null;
  queueLen: number = 0;
  status: string = 'unknown_status';
  recommendationQualityScalePermille: number | null = null;
  qualityRecommendationApplied: boolean = false;
}

function rounded(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function averageMs(nanoseconds: number, calls: number): number | null {
  return calls > 0 ? rounded(nanoseconds / calls / 1000000) : null;
}

function safeStatus(status: string): string {
  // Unknown future statuses are not echoed, even if they look like snake_case.
  const known: string[] = ['disabled', 'observing', 'stable', 'congested',
    'decode_limited', 'presentation_limited', 'missing_samples'];
  return known.includes(status) ? status : 'unknown_status';
}

export class FrameRateTelemetry {
  private binding: string = '';
  private lastReadAt: number = -1;
  private baseline: FrameRateSnapshot | undefined = undefined;
  private lastObserved: FrameRateSnapshot | undefined = undefined;

  reset(): void {
    this.binding = '';
    this.baseline = undefined;
    this.lastObserved = undefined;
  }

  shouldRead(binding: string, now: number): boolean {
    if (binding.length === 0 || !Number.isFinite(now) || now < 0) {
      this.reset();
      return false;
    }
    if (binding !== this.binding) {
      this.reset();
      this.binding = binding;
    }
    if (this.lastReadAt >= 0 && now < this.lastReadAt) {
      this.baseline = undefined;
      this.lastObserved = undefined;
      this.lastReadAt = now;
      return false;
    }
    if (this.lastReadAt >= 0 && now - this.lastReadAt < 1000) {
      return false;
    }
    this.lastReadAt = now;
    return true;
  }

  sample(raw: string, submittedWidth: number = 0, submittedHeight: number = 0): string | undefined {
    const current = parseFrameRateSnapshot(raw);
    if (this.binding.length === 0 || current === undefined || !current.available || current.desiredFps === null) {
      this.baseline = undefined;
      this.lastObserved = undefined;
      return undefined;
    }
    const previous = this.baseline;
    const lastObserved = this.lastObserved;
    this.lastObserved = current;
    if (previous === undefined || current.generation !== previous.generation
      || current.intentRevision !== previous.intentRevision || current.desiredFps !== previous.desiredFps
      || current.elapsedMs <= previous.elapsedMs
      || (lastObserved !== undefined && current.elapsedMs <= lastObserved.elapsedMs)) {
      this.baseline = current;
      return undefined;
    }
    const currentCounters = cumulativeCounters(current);
    const previousCounters = cumulativeCounters(lastObserved ?? previous);
    for (let index = 0; index < currentCounters.length; index += 1) {
      if (currentCounters[index] < previousCounters[index]) {
        this.baseline = current;
        return undefined;
      }
    }
    const windowMs = current.elapsedMs - previous.elapsedMs;
    if (windowMs > 2500) {
      // A suspended/missing observation interval is not a one-second FPS sample.
      this.baseline = current;
      return undefined;
    }
    if (windowMs < 1000) {
      return undefined;
    }
    this.baseline = current;
    const result = new FrameRateWindowLog();
    result.desiredFps = current.desiredFps;
    result.safetyFpsCap = current.safetyFpsCap;
    result.windowMs = windowMs;
    result.receivedPacketRate = rounded((current.receivedPackets - previous.receivedPackets) * 1000 / windowMs);
    result.decodedFps = rounded((current.decodedFrames - previous.decodedFrames) * 1000 / windowMs);
    result.submittedFps = rounded((current.submittedFrames - previous.submittedFrames) * 1000 / windowMs);
    result.unavailableFps = rounded((current.unavailableFrames - previous.unavailableFrames) * 1000 / windowMs);
    result.noBufferFps = rounded((current.noBufferFrames - previous.noBufferFrames) * 1000 / windowMs);
    result.busyFps = rounded((current.busyFrames - previous.busyFrames) * 1000 / windowMs);
    result.decodeAvgMs = averageMs(current.decodeNs - previous.decodeNs, current.decodeCalls - previous.decodeCalls);
    result.conversionAvgMs = averageMs(current.conversionNs - previous.conversionNs,
      current.conversionCalls - previous.conversionCalls);
    result.targetIncludingConversionAvgMs = averageMs(current.targetNs - previous.targetNs,
      current.targetCalls - previous.targetCalls);
    result.decodeWorkMsPerOutput = averageMs(current.decodeNs - previous.decodeNs,
      current.decodedFrames - previous.decodedFrames);
    result.targetWorkMsPerOutput = averageMs(current.targetNs - previous.targetNs,
      current.decodedFrames - previous.decodedFrames);
    if (safeCount(submittedWidth) && submittedWidth > 0 && submittedWidth <= 65536
      && safeCount(submittedHeight) && submittedHeight > 0 && submittedHeight <= 65536) {
      result.lastSoftwareSubmittedWidth = submittedWidth;
      result.lastSoftwareSubmittedHeight = submittedHeight;
    }
    result.queueLen = current.queueLen;
    result.status = safeStatus(current.status);
    result.recommendationQualityScalePermille = current.recommendation?.qualityScalePermille ?? null;
    return JSON.stringify(result);
  }
}
