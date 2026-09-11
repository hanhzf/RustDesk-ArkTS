import { common } from '@kit.AbilityKit';
import { modernSession, ModernSnapshot } from '../services/ModernSessionService';
import { modernHost } from '../services/ModernHostService';
import { ModernHostPanel } from './ModernHostPanel';

// API12 public Surface lifecycle, intentionally WITHOUT libraryname/unwrapping.
class ModernSurfaceController extends XComponentController {
  ready: (id: string) => void = (_id: string): void => {};
  gone: (id: string) => void = (_id: string): void => {};

  onSurfaceCreated(surfaceId: string): void {
    this.ready(surfaceId);
  }

  onSurfaceDestroyed(surfaceId: string): void {
    this.gone(surfaceId);
  }
}

@Entry
@Component
struct ModernDesk {
  @State private target: string = '';
  @State private password: string = '';
  @State private consent: boolean = false;
  @State private useRendezvous: boolean = true;
  @State private strictIdentity: boolean = true;
  @State private legacyConfirmed: boolean = false;
  @State private highFps: boolean = false;
  @State private expectedPeerId: string = '';
  @State private peerSigningKey: string = '';
  @State private encrypted: boolean = false;
  @State private peerVerified: boolean = false;
  @State private showHost: boolean = false;
  @State private active: boolean = false;
  @State private closing: boolean = false;
  @State private closeFailed: boolean = false;
  @State private surfaceReady: boolean = false;
  @State private phase: string = 'idle';
  @State private error: string = '';
  @State private sourceWidth: number = 0;
  @State private sourceHeight: number = 0;
  @State private codec: string = '';
  @State private route: string = '';
  @State private unitsReceived: number = 0;
  @State private unitsPushed: number = 0;
  @State private renders: number = 0;
  @State private renderRate: string = '0.0';
  @State private inputAllowed: boolean = false;
  @State private areaWidth: number = 1;
  @State private areaHeight: number = 1;
  @State private capabilities: string = '';
  @State private querying: boolean = false;
  private surfaceId: string = '';
  private controller: ModernSurfaceController = new ModernSurfaceController();
  private timer: number = -1;
  private previousRenders: number = 0;
  private previousTime: number = 0;
  private pageGeneration: number = 0;

  aboutToAppear(): void {
    this.pageGeneration++;
    this.querying = false;
    this.controller.ready = (id: string): void => {
      this.surfaceId = id;
      this.surfaceReady = id.length > 0;
    };
    this.controller.gone = (id: string): void => {
      if (id !== this.surfaceId) {
        return;
      }
      this.surfaceReady = false;
      this.surfaceId = '';
      modernSession.requestClose();
      this.disconnect();
    };
    // Status polling only: this timer never schedules/consumes a video frame.
    this.timer = setInterval(() => this.poll(), 250);
  }

  aboutToDisappear(): void {
    this.pageGeneration++;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
    modernSession.requestClose();
    modernSession.close().catch(() => {});
    modernHost.requestClose();
    modernHost.close().catch(() => {});
  }

  onBackPress(): boolean {
    if (this.showHost) {
      this.showHost = false;
      modernHost.requestClose();
      return true;
    }
    if (modernSession.hasSession()) {
      this.disconnect();
      return true;
    }
    return false;
  }

  private connect(): void {
    if (!this.consent || !this.surfaceReady || this.active || this.closing ||
      (!this.useRendezvous && !this.strictIdentity && !this.legacyConfirmed)) {
      return;
    }
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.encrypted = false;
      this.peerVerified = false;
      this.route = '';
      const requestedFps: number = this.highFps ? 120 : 60;
      if (this.useRendezvous) {
        modernSession.connectId(context.filesDir, this.surfaceId, this.target, this.password, requestedFps);
      } else if (this.strictIdentity) {
        modernSession.connectVerified(context.filesDir, this.surfaceId, this.target, this.password,
          requestedFps, this.expectedPeerId, this.peerSigningKey);
      } else {
        modernSession.connect(context.filesDir, this.surfaceId, this.target, this.password, requestedFps);
      }
      this.active = true;
      this.closeFailed = false;
      this.error = '';
      this.phase = 'connecting';
      this.previousTime = Date.now();
      this.previousRenders = 0;
    } catch {
      this.error = this.label($r('app.string.modern_connect_failed'));
    } finally {
      this.password = '';
    }
  }

  private async disconnect(): Promise<void> {
    if (this.closing || this.closeFailed || !modernSession.hasSession()) {
      return;
    }
    this.closing = true;
    this.inputAllowed = false;
    try {
      await modernSession.close();
      this.active = false;
      this.phase = 'closed';
    } catch {
      this.closeFailed = true;
      this.error = this.label($r('app.string.modern_close_failed'));
    } finally {
      this.closing = false;
    }
  }

  private poll(): void {
    if (!modernSession.hasSession()) {
      return;
    }
    try {
      const state: ModernSnapshot | undefined = modernSession.snapshot();
      if (state === undefined) {
        return;
      }
      this.phase = state.phase;
      this.error = state.error === null ? '' : state.error;
      this.sourceWidth = Math.max(0, state.width);
      this.sourceHeight = Math.max(0, state.height);
      this.codec = state.codec;
      this.route = state.route;
      this.encrypted = state.encrypted;
      this.peerVerified = state.peer_verified;
      this.unitsReceived = state.received_units;
      this.unitsPushed = state.pushed_units;
      this.renders = state.render_submissions;
      this.inputAllowed = state.keyboard_allowed && state.render_submissions > 0 && !state.closed && !this.closing;
      const now: number = Date.now();
      const elapsed: number = now - this.previousTime;
      if (elapsed >= 1000) {
        this.renderRate = (Math.max(0, state.render_submissions - this.previousRenders) * 1000 / elapsed).toFixed(1);
        this.previousTime = now;
        this.previousRenders = state.render_submissions;
      }
      if (state.closed && !this.closing && !this.closeFailed) {
        this.disconnect();
      }
    } catch {
      this.error = this.label($r('app.string.modern_state_failed'));
      modernSession.requestClose();
    }
  }

  private ratio(): number {
    return this.sourceWidth > 0 && this.sourceHeight > 0 ? this.sourceWidth / this.sourceHeight : 16 / 9;
  }

  private label(resource: Resource): string {
    try {
      const context: Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) {
        return context.resourceManager.getStringSync(resource.id);
      }
    } catch {
      // Do not throw another exception from an error-reporting path.
    }
    return 'resource_unavailable';
  }

  private videoWidth(): number {
    return Math.max(1, Math.min(this.areaWidth, this.areaHeight * this.ratio()));
  }

  private videoHeight(): number {
    return this.videoWidth() / this.ratio();
  }

  private touch(event: TouchEvent): void {
    if (!this.inputAllowed || event.changedTouches.length === 0 || this.sourceWidth <= 0) {
      return;
    }
    const point: TouchObject = event.changedTouches[0];
    const x: number = Math.max(0, Math.min(this.sourceWidth - 1,
      Math.floor(point.x * this.sourceWidth / this.videoWidth())));
    const y: number = Math.max(0, Math.min(this.sourceHeight - 1,
      Math.floor(point.y * this.sourceHeight / this.videoHeight())));
    let kind: number = 0;
    let button: number = 0;
    if (event.type === TouchType.Down) {
      kind = 1;
      button = 1;
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      kind = 2;
      button = 1;
    }
    if (kind !== 0 && !modernSession.mouse(0, 0, x, y)) {
      modernSession.requestClose();
      return;
    }
    if (!modernSession.mouse(kind, button, x, y)) {
      // A lost button edge is not silently reported as successful input.
      modernSession.requestClose();
    }
  }

  private async queryCapabilities(): Promise<void> {
    if (!this.consent || this.querying) {
      return;
    }
    this.querying = true;
    const generation: number = this.pageGeneration;
    try {
      const capabilities: string = await modernSession.capabilities();
      if (generation !== this.pageGeneration) {
        return;
      }
      this.capabilities = capabilities;
    } catch {
      if (generation === this.pageGeneration) {
        this.capabilities = this.label($r('app.string.modern_caps_failed'));
      }
    } finally {
      if (generation === this.pageGeneration) {
        this.querying = false;
      }
    }
  }

  build() {
    Column({ space: 8 }) {
      Text($r('app.string.modern_title')).fontSize(22).fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
      Text($r('app.string.modern_scope')).fontSize(12)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      Row({ space: 8 }) {
        Checkbox({ name: 'consent' }).select(this.consent).enabled(!this.closing)
          .onChange((value: boolean) => {
            this.consent = value;
            if (!value) {
              modernSession.requestClose();
              this.disconnect();
              modernHost.requestClose();
              modernHost.close().catch(() => {});
            }
          }).id('modern_consent')
        Text($r('app.string.modern_consent')).fontSize(12).layoutWeight(1)
      }
      Row({ space: 8 }) {
        Checkbox({ name: 'rendezvousMode' }).select(this.useRendezvous).enabled(!this.active)
          .onChange((value: boolean) => {
            this.useRendezvous = value;
            this.legacyConfirmed = false;
          }).id('modern_rendezvous_mode')
        Text($r('app.string.modern_rendezvous_mode')).fontSize(12).layoutWeight(1)
        Button($r('app.string.modern_host_panel')).onClick(() => this.showHost = !this.showHost)
          .id('modern_host_panel')
      }
      Row({ space: 8 }) {
        Checkbox({ name: 'highFps' }).select(this.highFps).enabled(!this.active)
          .onChange((value: boolean) => this.highFps = value).id('modern_high_fps')
        Text($r('app.string.modern_high_fps')).fontSize(12).layoutWeight(1)
      }
      if (!this.useRendezvous) {
        Row({ space: 8 }) {
          Checkbox({ name: 'strictIdentity' }).select(this.strictIdentity).enabled(!this.active)
            .onChange((value: boolean) => {
              this.strictIdentity = value;
              this.legacyConfirmed = false;
            }).id('modern_strict_identity')
          Text($r('app.string.modern_strict_identity')).fontSize(12).layoutWeight(1)
        }
      }
      if (!this.useRendezvous && this.strictIdentity) {
        Row({ space: 8 }) {
          TextInput({ text: this.expectedPeerId, placeholder: $r('app.string.modern_peer_id') })
            .layoutWeight(1).enabled(!this.active).onChange((v: string) => this.expectedPeerId = v)
            .id('modern_peer_id')
          TextInput({ text: this.peerSigningKey, placeholder: $r('app.string.modern_peer_key') })
            .layoutWeight(2).enabled(!this.active).onChange((v: string) => this.peerSigningKey = v)
            .id('modern_peer_key')
        }
      } else if (!this.useRendezvous) {
        Text($r('app.string.modern_legacy_warning')).fontSize(12)
          .fontColor($r('sys.color.ohos_id_color_warning'))
        Row({ space: 8 }) {
          Checkbox({ name: 'legacyConfirmed' }).select(this.legacyConfirmed).enabled(!this.active)
            .onChange((value: boolean) => this.legacyConfirmed = value).id('modern_legacy_confirmed')
          Text($r('app.string.modern_legacy_confirm')).fontSize(12).layoutWeight(1)
            .fontColor($r('sys.color.ohos_id_color_warning'))
        }
      }
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        TextInput({ text: this.target, placeholder: this.useRendezvous ?
          $r('app.string.modern_peer_target_id') : $r('app.string.modern_address') })
          .width('48%').enabled(!this.active).onChange((value: string) => this.target = value)
          .id('modern_address')
        TextInput({ text: this.password, placeholder: $r('app.string.modern_password') })
          .type(InputType.Password).width('48%').enabled(!this.active)
          .onChange((value: string) => this.password = value).id('modern_password')
        Button($r('app.string.modern_connect')).enabled(this.consent && this.surfaceReady && !this.active && !this.closing &&
          this.target.trim().length > 0 && (this.useRendezvous || (!this.strictIdentity && this.legacyConfirmed) ||
          (this.expectedPeerId.trim().length > 0 && this.peerSigningKey.trim().length > 0)))
          .onClick(() => this.connect()).id('modern_connect')
        Button($r('app.string.modern_disconnect')).enabled(this.active && !this.closing && !this.closeFailed)
          .onClick(() => this.disconnect()).id('modern_disconnect')
        Button($r('app.string.modern_capabilities')).enabled(this.consent && !this.querying)
          .onClick(() => this.queryCapabilities()).id('modern_capabilities')
      }
      Text(`${this.phase}  ${this.route}  ${this.codec}  ${this.sourceWidth} × ${this.sourceHeight}  ` +
        `${this.highFps ? 120 : 60} FPS`)
        .fontSize(12).id('modern_state')
      Text(!this.active ? $r('app.string.modern_security_none') :
        (this.peerVerified && this.encrypted ? $r('app.string.modern_security_verified') :
          $r('app.string.modern_security_unverified'))).fontSize(12).id('modern_security')
      Text($r('app.string.modern_counters', this.unitsReceived, this.unitsPushed, this.renders, this.renderRate))
        .fontSize(12).id('modern_counters')
      if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor($r('sys.color.ohos_id_color_warning')).id('modern_error')
      }
      if (this.showHost) {
        Scroll() { ModernHostPanel({ consent: this.consent }) }.height(220).width('100%')
      }
      Stack({ alignContent: Alignment.Center }) {
        // Always mounted. Disconnection/state updates do not replace this node.
        XComponent({ id: 'modernSurface', type: XComponentType.SURFACE, controller: this.controller })
          .width(this.videoWidth()).height(this.videoHeight())
          .onTouch((event: TouchEvent) => this.touch(event)).id('modern_video')
      }.width('100%').layoutWeight(1).backgroundColor(Color.Black)
      .onAreaChange((_old: Area, area: Area) => {
        this.areaWidth = Number(area.width);
        this.areaHeight = Number(area.height);
      })
      if (this.capabilities.length > 0) {
        Scroll() {
          Text(this.capabilities).fontSize(11).width('100%').id('modern_capability_result')
        }.height(120).width('100%')
      }
    }.width('100%').height('100%').padding(12)
    .backgroundColor($r('sys.color.ohos_id_color_background'))
  }
}
