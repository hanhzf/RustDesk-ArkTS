import { describe, expect, it } from '@ohos/hypium';
import {
  FrameRateRecommendation,
  FrameRateSnapshot,
  FrameRateTelemetry,
  FrameRateWindowLog,
  parseFrameRateSnapshot,
} from '../../../main/ets/services/FrameRateTelemetry';
import {
  NativeDecoderSnapshot,
  NativeDecoderTelemetry,
  NativeDecoderWindowLog,
  parseNativeDecoderSnapshot,
} from '../../../main/ets/services/NativeDecoderTelemetry';

function snapshot(elapsedMs: number, frames: number): FrameRateSnapshot {
  const result = new FrameRateSnapshot();
  result.available = true;
  result.generation = '7';
  result.intentRevision = '2';
  result.desiredFps = 90;
  result.elapsedMs = elapsedMs;
  result.receivedPackets = frames;
  result.decodedFrames = frames;
  result.submittedFrames = frames;
  result.decodeCalls = frames;
  result.decodeNs = frames * 2000000;
  result.conversionCalls = frames;
  result.conversionNs = frames * 1000000;
  result.targetCalls = frames;
  result.targetNs = frames * 3000000;
  result.status = 'stable';
  return result;
}

export default function frameRateTelemetryTest(): void {
  describe('FrameRateTelemetry', () => {
    it('separates native callback media and render deltas with strict private scope and invalid boundaries', 0, () => {
      const telemetry = new NativeDecoderTelemetry();
      const intent = snapshot(0, 0);
      intent.queueLen = 7;
      const value = new NativeDecoderSnapshot();
      value.available = true;
      value.active = true;
      value.state = 'running';
      value.codec = 'h265';
      value.generation = '12345678901234567890';
      value.inputWaitCalls = 2;
      value.inputWaitNs = 10000000;
      value.inputWaitMaxNs = 8000000;
      value.pushCalls = 1;
      value.pushNs = 1000000;
      value.pushMaxNs = 1000000;
      value.renderCalls = 2;
      value.renderNs = 30000000;
      value.renderMaxNs = 20000000;
      value.renderInFlight = 1;
      const sample = (): NativeDecoderWindowLog => {
        return JSON.parse(telemetry.sample(JSON.stringify(value), 'private_binding', intent)) as NativeDecoderWindowLog;
      };
      const warming = sample();
      expect(warming.status).assertEqual('warming_up');
      expect(warming.lastPostHandleQueueLen === null).assertTrue();
      expect(warming.completedInputWaitMs === null).assertTrue();
      expect(warming.inputWaitAvgMs === null).assertTrue();
      expect(warming.inputWaitHighWaterMs === null).assertTrue();
      expect(warming.completedPushMs === null).assertTrue();
      expect(warming.pushAvgMs === null).assertTrue();
      expect(warming.pushHighWaterMs === null).assertTrue();
      expect(warming.completedRenderMs === null).assertTrue();
      expect(warming.renderAvgMs === null).assertTrue();
      expect(warming.renderHighWaterMs === null).assertTrue();
      expect(warming.renderInFlight === null).assertTrue();
      value.elapsedMs = 1000;
      value.acceptedPackets = 1;
      value.acceptedBytes = 100;
      value.outputBuffers = 7;
      value.mediaOutputBuffers = 2;
      value.renderSubmittedBuffers = 5;
      value.renderFailedBuffers = 2;
      value.outputMetadataErrors = 1;
      value.outputEosBuffers = 3;
      value.outputCodecConfigBuffers = 3;
      value.outputOtherBuffers = 1;
      value.inputWaits = 4;
      value.inputRejected = 1;
      value.inputTimeouts = 2;
      value.outputQueueDepth = 2;
      value.outputQueueHighWater = 5;
      value.formatChanges = 2;
      value.decoderErrors = 1;
      value.inputWaitCalls = 6;
      value.inputWaitNs = 34000000;
      value.inputWaitMaxNs = 9000000;
      value.pushCalls = 4;
      value.pushNs = 7000000;
      value.pushMaxNs = 3000000;
      value.renderCalls = 8;
      // Full elapsed time belongs to the completion window even when a call
      // crossed its boundary. Completed duration may exceed windowMs.
      value.renderNs = 2430000000;
      value.renderMaxNs = 2200000000;
      value.renderInFlight = 0; // gauge rollback must not reset the window
      const privateRaw = JSON.stringify(value).slice(0, -1)
        + ',"sessionId":"private_session","surfaceID":"private_surface","reason":"private_error",'
        + '"extra":{"password":"private_password"}}';
      const rawLog = telemetry.sample(privateRaw, 'private_binding', intent);
      const window = JSON.parse(rawLog) as NativeDecoderWindowLog;
      expect(window.route).assertEqual('native_surface');
      expect(window.codec).assertEqual('h265');
      expect(window.desiredFps).assertEqual(90);
      expect(window.windowMs).assertEqual(1000);
      expect(window.inputAcceptedPerSec).assertEqual(1);
      expect(window.inputBytesPerSec).assertEqual(100);
      expect(window.outputCallbacksPerSec).assertEqual(7);
      expect(window.mediaOutputsPerSec).assertEqual(2);
      expect(window.renderAcceptedPerSec).assertEqual(5);
      expect(window.renderFailuresPerSec).assertEqual(2);
      expect(window.metadataErrorsPerSec).assertEqual(1);
      expect(window.eosPerSec).assertEqual(3);
      expect(window.configPerSec).assertEqual(3);
      expect(window.otherPerSec).assertEqual(1);
      expect(window.inputWaitsPerSec).assertEqual(4);
      expect(window.inputRejectedPerSec).assertEqual(1);
      expect(window.inputTimeoutsPerSec).assertEqual(2);
      expect(window.outputQueueDepth).assertEqual(2);
      expect(window.outputQueueHighWater).assertEqual(5);
      expect(window.lastPostHandleQueueLen).assertEqual(7);
      expect(window.formatChangesPerSec).assertEqual(2);
      expect(window.decoderErrorsPerSec).assertEqual(1);
      expect(window.actualOutputWidth === null).assertTrue();
      expect(window.actualOutputHeight === null).assertTrue();
      expect(window.completedInputWaitMs).assertEqual(24);
      expect(window.inputWaitAvgMs).assertEqual(6);
      expect(window.inputWaitHighWaterMs).assertEqual(9);
      expect(window.completedPushMs).assertEqual(6);
      expect(window.pushAvgMs).assertEqual(2);
      expect(window.pushHighWaterMs).assertEqual(3);
      expect(window.completedRenderMs).assertEqual(2400);
      expect(window.renderAvgMs).assertEqual(400);
      expect(window.renderHighWaterMs).assertEqual(2200);
      expect(window.renderInFlight).assertEqual(0);
      for (const forbidden of ['private_', 'sessionId', 'surfaceID', 'generation', 'intentRevision',
        'reason', 'password', 'extra', 'presentedFps', 'decodedFps', 'Frames']) {
        expect(rawLog.includes(forbidden)).assertFalse();
        expect(JSON.stringify(parseNativeDecoderSnapshot(privateRaw)).includes('private_')).assertFalse();
      }
      const valid = JSON.stringify(value);
      for (const invalid of ['', '{}', 'null', '[]', 'broken',
        valid.replace('"active":true', '"active":1'),
        valid.replace('"state":"running"', '"state":"private_state"'),
        valid.replace('"codec":"h265"', '"codec":"private_codec"'),
        valid.replace('"acceptedPackets":1', '"acceptedPackets":1.5'),
        valid.replace('"acceptedPackets":1', '"acceptedPackets":9007199254740992'),
        valid.replace('"acceptedPackets":1,', ''),
        valid.replace('"width":null', '"width":0'),
        valid.replace('"width":null', '"width":65537'),
        valid.replace('"height":null,', ''),
        valid.replace('"outputQueueDepth":2', '"outputQueueDepth":-1'),
        valid.replace('"formatChanges":2,', ''),
        valid.replace('"decoderErrors":1', '"decoderErrors":-1'),
        valid.replace('"renderInFlight":0', '"renderInFlight":2'),
        valid.replace('"renderInFlight":0', '"renderInFlight":-1'),
        valid.replace('"renderInFlight":0', '"renderInFlight":0.5'),
        valid.replace('"renderInFlight":0', '"renderInFlight":"0"'),
        valid.replace('"renderInFlight":0', '"renderInFlight":null'),
        valid.replace(',"renderInFlight":0', ''),
        valid.replace('"codec":"h265"', '"codec":"unknown"')]) {
        expect(parseNativeDecoderSnapshot(invalid) === undefined).assertTrue();
        const invalidLog = JSON.parse(telemetry.sample(invalid, 'private_binding', intent)) as NativeDecoderWindowLog;
        expect(invalidLog.status).assertEqual('invalid');
        expect(invalidLog.lastPostHandleQueueLen === null).assertTrue();
        expect(invalidLog.renderAcceptedPerSec === null).assertTrue();
        expect(invalidLog.actualOutputWidth === null).assertTrue();
        expect(invalidLog.completedInputWaitMs === null).assertTrue();
        expect(invalidLog.completedPushMs === null).assertTrue();
        expect(invalidLog.completedRenderMs === null).assertTrue();
        expect(invalidLog.renderInFlight === null).assertTrue();
      }
      const timingNames: string[] = ['inputWaitCalls', 'inputWaitNs', 'inputWaitMaxNs',
        'pushCalls', 'pushNs', 'pushMaxNs', 'renderCalls', 'renderNs', 'renderMaxNs'];
      const timingValues: number[] = [6, 34000000, 9000000, 4, 7000000, 3000000,
        8, 2430000000, 2200000000];
      for (let index = 0; index < timingNames.length; index += 1) {
        const field = '"' + timingNames[index] + '":' + timingValues[index];
        for (const invalidTiming of [valid.replace(field + ',', ''),
          valid.replace(field, '"' + timingNames[index] + '":null'),
          valid.replace(field, '"' + timingNames[index] + '":-1'),
          valid.replace(field, '"' + timingNames[index] + '":1.5'),
          valid.replace(field, '"' + timingNames[index] + '":9007199254740992')]) {
          expect(parseNativeDecoderSnapshot(invalidTiming) === undefined).assertTrue();
          const missing = JSON.parse(telemetry.sample(invalidTiming, 'private_binding', intent)) as NativeDecoderWindowLog;
          expect(missing.completedInputWaitMs === null).assertTrue();
          expect(missing.completedPushMs === null).assertTrue();
          expect(missing.completedRenderMs === null).assertTrue();
          expect(missing.renderInFlight === null).assertTrue();
        }
        telemetry.reset();
        telemetry.sample(valid, 'private_binding', intent);
        const rollbackRaw = valid.replace('"elapsedMs":1000', '"elapsedMs":1500')
          .replace(field, '"' + timingNames[index] + '":' + (timingValues[index] - 1));
        const rollback = JSON.parse(telemetry.sample(rollbackRaw, 'private_binding', intent)) as NativeDecoderWindowLog;
        expect(rollback.status).assertEqual('warming_up');
        expect(rollback.completedRenderMs === null).assertTrue();
        const recovered = JSON.parse(telemetry.sample(
          valid.replace('"elapsedMs":1000', '"elapsedMs":2500'), 'private_binding', intent)) as NativeDecoderWindowLog;
        expect(recovered.windowMs).assertEqual(1000); // rollback became a new baseline
      }
      telemetry.reset();
      expect(sample().status).assertEqual('warming_up');
      value.elapsedMs = 2000;
      value.width = 1920;
      value.height = 1080;
      value.renderInFlight = 1;
      const idle = sample();
      expect(idle.actualOutputWidth).assertEqual(1920);
      expect(idle.completedInputWaitMs).assertEqual(0);
      expect(idle.inputWaitAvgMs === null).assertTrue();
      expect(idle.inputWaitHighWaterMs).assertEqual(9);
      expect(idle.completedPushMs).assertEqual(0);
      expect(idle.pushAvgMs === null).assertTrue();
      expect(idle.pushHighWaterMs).assertEqual(3);
      expect(idle.completedRenderMs).assertEqual(0);
      expect(idle.renderAvgMs === null).assertTrue();
      expect(idle.renderHighWaterMs).assertEqual(2200); // not reset by an idle window
      expect(idle.renderInFlight).assertEqual(1);
      value.elapsedMs = 3000;
      value.width = null;
      value.height = null;
      value.renderInFlight = 0;
      const idleFinished = sample();
      expect(idleFinished.actualOutputWidth === null).assertTrue();
      expect(idleFinished.renderInFlight).assertEqual(0);
      expect(idleFinished.windowMs).assertEqual(1000);
      value.generation = '2';
      value.inputWaitCalls = 0;
      value.inputWaitNs = 0;
      value.inputWaitMaxNs = 0;
      value.pushCalls = 0;
      value.pushNs = 0;
      value.pushMaxNs = 0;
      value.renderCalls = 0;
      value.renderNs = 0;
      value.renderMaxNs = 0;
      value.elapsedMs = 4000;
      const newGeneration = sample();
      expect(newGeneration.windowMs === null).assertTrue();
      expect(newGeneration.lastPostHandleQueueLen === null).assertTrue();
      expect(newGeneration.completedInputWaitMs === null).assertTrue();
      expect(newGeneration.inputWaitHighWaterMs === null).assertTrue();
      expect(newGeneration.completedPushMs === null).assertTrue();
      expect(newGeneration.pushHighWaterMs === null).assertTrue();
      expect(newGeneration.completedRenderMs === null).assertTrue();
      expect(newGeneration.renderHighWaterMs === null).assertTrue();
      expect(newGeneration.renderInFlight === null).assertTrue();
      value.elapsedMs = 5000;
      intent.intentRevision = '3';
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 6000;
      const rebound = JSON.parse(telemetry.sample(JSON.stringify(value), 'other_binding', intent)) as NativeDecoderWindowLog;
      expect(rebound.windowMs === null).assertTrue();
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 7000;
      intent.generation = '8';
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 8000;
      const generationWindow = sample();
      expect(generationWindow.windowMs).assertEqual(1000);
      expect(generationWindow.inputWaitHighWaterMs).assertEqual(0);
      expect(generationWindow.pushHighWaterMs).assertEqual(0);
      expect(generationWindow.renderHighWaterMs).assertEqual(0);
      value.elapsedMs = 8300;
      value.outputBuffers = 10;
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 8500;
      value.outputBuffers = 9;
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 9500;
      value.outputBuffers = 11;
      expect(sample().outputCallbacksPerSec).assertEqual(2);
      value.elapsedMs = 9000;
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 12000;
      expect(sample().windowMs === null).assertTrue();
      value.elapsedMs = 13000;
      intent.desiredFps = null;
      expect(sample().status).assertEqual('paused');
      intent.desiredFps = 90;
      expect(sample().status).assertEqual('warming_up');
      value.active = false;
      expect(sample().status).assertEqual('inactive');
      value.active = true;
      expect(sample().status).assertEqual('warming_up');
      value.state = 'failed';
      const failed = sample();
      expect(failed.status).assertEqual('failed');
      expect(failed.mediaOutputsPerSec === null).assertTrue();
      expect(failed.actualOutputWidth === null).assertTrue();
      value.state = 'unavailable';
      value.available = false;
      value.active = false;
      value.generation = '';
      value.codec = 'unknown';
      expect(sample().status).assertEqual('unavailable');
      const sparse = '{"available":false,"active":false,"state":"unavailable",'
        + '"reason":"private_reason","generation":"","elapsedMs":0,"codec":"unknown",'
        + '"width":null,"height":null}';
      const unavailable = JSON.parse(telemetry.sample(sparse, 'private_binding', intent)) as NativeDecoderWindowLog;
      expect(unavailable.status).assertEqual('unavailable');
      expect(unavailable.lastPostHandleQueueLen === null).assertTrue();
      expect(unavailable.codec).assertEqual('unknown');
      expect(unavailable.renderAcceptedPerSec === null).assertTrue();
      expect(unavailable.actualOutputWidth === null).assertTrue();
      expect(unavailable.completedInputWaitMs === null).assertTrue();
      expect(unavailable.inputWaitAvgMs === null).assertTrue();
      expect(unavailable.inputWaitHighWaterMs === null).assertTrue();
      expect(unavailable.completedPushMs === null).assertTrue();
      expect(unavailable.pushAvgMs === null).assertTrue();
      expect(unavailable.pushHighWaterMs === null).assertTrue();
      expect(unavailable.completedRenderMs === null).assertTrue();
      expect(unavailable.renderAvgMs === null).assertTrue();
      expect(unavailable.renderHighWaterMs === null).assertTrue();
      expect(unavailable.renderInFlight === null).assertTrue();
      expect(JSON.stringify(unavailable).includes('private_reason')).assertFalse();
      expect(parseNativeDecoderSnapshot(sparse.replace('"width":null', '"width":1920')) === undefined).assertTrue();
      expect(parseNativeDecoderSnapshot(sparse.replace('"codec":"unknown"', '"codec":"h265"')) === undefined).assertTrue();
      value.state = 'running';
      value.available = true;
      value.active = true;
      value.codec = 'h264';
      expect(sample().status).assertEqual('invalid');
      value.generation = '3';
      expect(sample().status).assertEqual('warming_up');
      telemetry.reset();
      value.elapsedMs = 14000;
      expect(sample().status).assertEqual('warming_up');
      value.elapsedMs = 15000;
      intent.queueLen = 0;
      expect(sample().lastPostHandleQueueLen).assertEqual(0);
      value.elapsedMs = 16000;
      intent.available = false;
      const unavailableIntent = sample();
      expect(unavailableIntent.status).assertEqual('invalid');
      expect(unavailableIntent.lastPostHandleQueueLen === null).assertTrue();
      intent.available = true;
      expect(sample().lastPostHandleQueueLen === null).assertTrue();
      value.elapsedMs = 17000;
      const missingIntent = JSON.parse(
        telemetry.sample(JSON.stringify(value), 'private_binding', undefined)) as NativeDecoderWindowLog;
      expect(missingIntent.status).assertEqual('invalid');
      expect(missingIntent.lastPostHandleQueueLen === null).assertTrue();
    });
    it('logs only safe intent-scoped interval deltas and resets missing epoch counter or time boundaries', 0, () => {
      expect(parseFrameRateSnapshot('{}') === undefined).assertTrue();
      expect(parseFrameRateSnapshot('broken') === undefined).assertTrue();
      expect(parseFrameRateSnapshot('{"available":false,"reason":"secret_session"}') === undefined).assertTrue();
      const valid = JSON.stringify(snapshot(10000, 200));
      expect(parseFrameRateSnapshot(valid.replace('"queueLen":0,', '')) === undefined).assertTrue();
      expect(parseFrameRateSnapshot(valid.replace('"desiredFps":90', '"desiredFps":"90"')) === undefined).assertTrue();
      expect(parseFrameRateSnapshot(valid.replace('"safetyFpsCap":null,', '')) === undefined).assertTrue();
      expect(parseFrameRateSnapshot(valid.replace('"safetyFpsCap":null',
        '"safetyFpsCap":"secret_cap"')) === undefined).assertTrue();
      const invalid = snapshot(10000, 200);
      invalid.safetyFpsCap = 60;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid))?.safetyFpsCap).assertEqual(60);
      invalid.safetyFpsCap = 91;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.safetyFpsCap = 0;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.safetyFpsCap = 60.5;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.safetyFpsCap = 60;
      invalid.desiredFps = null;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.safetyFpsCap = null;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) !== undefined).assertTrue();
      invalid.desiredFps = 120;
      invalid.safetyFpsCap = 120;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) !== undefined).assertTrue();
      invalid.safetyFpsCap = 121;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.safetyFpsCap = null;
      invalid.desiredFps = 121;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.desiredFps = 90;
      invalid.decodedFrames = Number.MAX_SAFE_INTEGER + 1;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.decodedFrames = 200;
      invalid.qualityRecommendationApplied = true;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.qualityRecommendationApplied = false;
      invalid.status = 'private session/value';
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();
      invalid.status = 'stable';
      invalid.recommendation = new FrameRateRecommendation();
      invalid.recommendation.qualityScalePermille = 1001;
      expect(parseFrameRateSnapshot(JSON.stringify(invalid)) === undefined).assertTrue();

      const telemetry = new FrameRateTelemetry();
      expect(telemetry.shouldRead('', 0)).assertFalse();
      expect(telemetry.shouldRead('private_binding_a', 0)).assertTrue();
      expect(telemetry.sample(valid) === undefined).assertTrue();
      expect(telemetry.shouldRead('private_binding_a', 999)).assertFalse();
      expect(telemetry.shouldRead('private_binding_a', 1000)).assertTrue();
      const next = snapshot(11000, 290);
      next.safetyFpsCap = 60;
      next.recommendation = new FrameRateRecommendation();
      next.recommendation.qualityScalePermille = 950;
      next.recommendation.sequence = 4;
      next.status = 'credential_private_value';
      const raw = JSON.stringify(next).slice(0, -1)
        + ',"sessionId":"secret_session","peer":"secret_peer","surfaceId":"secret_surface",'
        + '"pixels":"secret_pixels","password":"secret_password"}';
      const log = telemetry.sample(raw) ?? '';
      expect(log.length > 0).assertTrue();
      const window = JSON.parse(log) as FrameRateWindowLog;
      expect(window.windowMs).assertEqual(1000);
      expect(window.desiredFps).assertEqual(90);
      expect(window.safetyFpsCap).assertEqual(60);
      expect(window.decodedFps).assertEqual(90);
      expect(window.receivedPacketRate).assertEqual(90);
      expect(window.submittedFps).assertEqual(90);
      expect(window.decodeAvgMs).assertEqual(2);
      expect(window.conversionAvgMs).assertEqual(1);
      expect(window.targetIncludingConversionAvgMs).assertEqual(3);
      expect(window.decodeWorkMsPerOutput).assertEqual(2);
      expect(window.targetWorkMsPerOutput).assertEqual(3);
      expect(window.lastSoftwareSubmittedWidth === null).assertTrue();
      expect(window.lastSoftwareSubmittedHeight === null).assertTrue();
      expect(window.status).assertEqual('unknown_status');
      expect(window.recommendationQualityScalePermille).assertEqual(950);
      expect(window.qualityRecommendationApplied).assertFalse();
      for (const privateField of ['secret_', 'private_', 'sessionId', 'peer', 'surfaceId', 'pixels',
        'password', 'generation', 'intentRevision', 'sequence', 'fence', 'kbps']) {
        expect(log.includes(privateField)).assertFalse();
      }
      expect(telemetry.sample('') === undefined).assertTrue();
      expect(telemetry.sample(JSON.stringify(snapshot(12000, 380))) === undefined).assertTrue();
      expect(telemetry.sample(JSON.stringify(snapshot(12500, 425))) === undefined).assertTrue();
      const combined = JSON.parse(telemetry.sample(JSON.stringify(snapshot(13000, 470))) ?? '{}') as FrameRateWindowLog;
      expect(combined.decodedFps).assertEqual(90);
      expect(combined.status).assertEqual('stable');
      expect(combined.safetyFpsCap === null).assertTrue();
      expect(telemetry.sample(JSON.stringify(snapshot(13300, 497))) === undefined).assertTrue();
      expect(telemetry.sample(JSON.stringify(snapshot(13500, 490))) === undefined).assertTrue();
      const afterRollback = JSON.parse(telemetry.sample(JSON.stringify(snapshot(14500, 580))) ?? '{}') as FrameRateWindowLog;
      expect(afterRollback.decodedFps).assertEqual(90);
      expect(telemetry.sample(JSON.stringify(snapshot(14000, 460))) === undefined).assertTrue();
      expect(telemetry.sample(JSON.stringify(snapshot(14000, 460))) === undefined).assertTrue();
      expect(telemetry.sample(JSON.stringify(snapshot(13999, 460))) === undefined).assertTrue();
      const epoch = snapshot(15000, 500);
      epoch.generation = '8';
      expect(telemetry.sample(JSON.stringify(epoch)) === undefined).assertTrue();
      epoch.elapsedMs = 16000;
      epoch.intentRevision = '3';
      expect(telemetry.sample(JSON.stringify(epoch)) === undefined).assertTrue();
      epoch.elapsedMs = 17000;
      const idleLog = JSON.parse(telemetry.sample(JSON.stringify(epoch)) ?? '{}') as FrameRateWindowLog;
      expect(idleLog.decodedFps).assertEqual(0);
      expect(idleLog.decodeAvgMs === null).assertTrue();
      expect(idleLog.targetIncludingConversionAvgMs === null).assertTrue();
      expect(idleLog.decodeWorkMsPerOutput === null).assertTrue();
      expect(idleLog.targetWorkMsPerOutput === null).assertTrue();
      epoch.elapsedMs = 27000;
      expect(telemetry.sample(JSON.stringify(epoch)) === undefined).assertTrue();
      epoch.elapsedMs = 18000;
      epoch.desiredFps = null;
      expect(telemetry.sample(JSON.stringify(epoch)) === undefined).assertTrue();
      epoch.desiredFps = 90;
      expect(telemetry.sample(JSON.stringify(epoch)) === undefined).assertTrue();
      epoch.available = false;
      expect(telemetry.sample(JSON.stringify(epoch)) === undefined).assertTrue();
      telemetry.reset();
      expect(telemetry.shouldRead('private_binding_b', 1500)).assertFalse();
      expect(telemetry.shouldRead('private_binding_b', 2000)).assertTrue();
      expect(telemetry.sample(valid) === undefined).assertTrue();
      expect(telemetry.shouldRead('private_binding_b', 1999)).assertFalse();
      expect(telemetry.sample(valid) === undefined).assertTrue();

      const multiOutput = new FrameRateTelemetry();
      expect(multiOutput.shouldRead('size_binding', 0)).assertTrue();
      expect(multiOutput.sample(JSON.stringify(snapshot(0, 0))) === undefined).assertTrue();
      const twoOutputs = snapshot(1000, 2);
      twoOutputs.decodeCalls = 1;
      twoOutputs.decodeNs = 6000000;
      twoOutputs.submittedFrames = 1;
      twoOutputs.conversionCalls = 1;
      twoOutputs.conversionNs = 1000000;
      twoOutputs.targetCalls = 1;
      twoOutputs.targetNs = 8000000;
      const sizeLog = JSON.parse(multiOutput.sample(JSON.stringify(twoOutputs), 5120, 2880) ?? '{}') as FrameRateWindowLog;
      expect(sizeLog.decodedFps).assertEqual(2);
      expect(sizeLog.submittedFps).assertEqual(1);
      expect(sizeLog.decodeAvgMs).assertEqual(6);
      expect(sizeLog.decodeWorkMsPerOutput).assertEqual(3);
      expect(sizeLog.targetIncludingConversionAvgMs).assertEqual(8);
      expect(sizeLog.targetWorkMsPerOutput).assertEqual(4);
      expect(sizeLog.lastSoftwareSubmittedWidth).assertEqual(5120);
      expect(sizeLog.lastSoftwareSubmittedHeight).assertEqual(2880);
      twoOutputs.elapsedMs = 2000;
      const invalidSize = JSON.parse(multiOutput.sample(JSON.stringify(twoOutputs), Number.NaN, 720) ?? '{}') as FrameRateWindowLog;
      expect(invalidSize.lastSoftwareSubmittedWidth === null).assertTrue();
      expect(invalidSize.lastSoftwareSubmittedHeight === null).assertTrue();
      twoOutputs.elapsedMs = 3000;
      const missingSize = JSON.parse(multiOutput.sample(JSON.stringify(twoOutputs)) ?? '{}') as FrameRateWindowLog;
      expect(missingSize.lastSoftwareSubmittedWidth === null).assertTrue();
    });
  });
}
