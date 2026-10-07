import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { audio } from '@kit.AudioKit';

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';
const MAX_PCM_CHUNK_BYTES: number = 32 * 1024;

export class RemoteVoiceInputController {
  private readonly permissionManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  private readonly context: common.UIAbilityContext;
  private readonly sendPcm: (sessionId: string, pcm: Uint8Array) => boolean;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private activeSessionId: string = '';
  private generation: number = 0;
  private running: boolean = false;

  constructor(
    context: common.UIAbilityContext,
    sendPcm: (sessionId: string, pcm: Uint8Array) => boolean,
  ) {
    this.context = context;
    this.sendPcm = sendPcm;
  }

  async start(sessionId: string): Promise<boolean> {
    await this.stop();
    if (sessionId.length === 0) {
      return false;
    }
    const generation = ++this.generation;
    this.activeSessionId = sessionId;
    try {
      const tokenId = this.context.applicationInfo.accessTokenId;
      let grant = await this.permissionManager.checkAccessToken(tokenId, MICROPHONE_PERMISSION);
      if (grant !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        await this.permissionManager.requestPermissionsFromUser(this.context, [MICROPHONE_PERMISSION]);
        grant = await this.permissionManager.checkAccessToken(tokenId, MICROPHONE_PERMISSION);
      }
      if (grant !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED || generation !== this.generation) {
        return false;
      }
      const options: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW,
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0,
        },
      };
      const capturer = await audio.createAudioCapturer(options);
      if (generation !== this.generation) {
        await capturer.release();
        return false;
      }
      this.capturer = capturer;
      this.running = true;
      capturer.on('readData', (buffer: ArrayBuffer): void => {
        if (!this.running || generation !== this.generation || this.activeSessionId !== sessionId) {
          return;
        }
        const pcm = new Uint8Array(buffer);
        for (let offset = 0; offset < pcm.length; offset += MAX_PCM_CHUNK_BYTES) {
          const chunk = pcm.subarray(offset, Math.min(offset + MAX_PCM_CHUNK_BYTES, pcm.length));
          let sent = false;
          try {
            sent = this.sendPcm(sessionId, chunk);
          } catch (_error) {
            sent = false;
          }
          if (!sent) {
            void this.stop();
            return;
          }
        }
      });
      await capturer.start();
      if (generation !== this.generation) {
        await this.stop();
        return false;
      }
      return true;
    } catch (_error) {
      await this.stop();
      return false;
    }
  }

  async stop(): Promise<void> {
    this.generation += 1;
    this.running = false;
    this.activeSessionId = '';
    const capturer = this.capturer;
    this.capturer = undefined;
    if (capturer !== undefined) {
      try {
        await capturer.stop();
      } catch (_error) {
        // The stream may already have stopped after an audio interruption.
      }
      try {
        await capturer.release();
      } catch (_error) {
        // The audio service may already have released an interrupted capturer.
      }
    }
  }
}
