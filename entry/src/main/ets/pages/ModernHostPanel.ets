import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { modernHost, ModernHostSnapshot, ModernHostIdentity } from '../services/ModernHostService';

@Component
export struct ModernHostPanel {
  @Prop @Watch('consentChanged') consent: boolean = false;
  @State private running: boolean = false;
  @State private closing: boolean = false;
  @State private closeFailed: boolean = false;
  @State private phase: string = 'idle';
  @State private request: string = '';
  @State private requestOrigin: string = '';
  @State private sent: number = 0;
  @State private geometry: string = '';
  @State private error: string = '';
  @State private identity: string = '';
  private timer: number = -1;
  private sourceWidth: number = 0;
  private sourceHeight: number = 0;
  private sourceDisplay: number = -1;
  private watchingDisplay: boolean = false;
  private displayChanged: (_id: number) => void = (_id: number): void => {
    if (!this.running) { return; }
    try {
      const screen: display.Display = display.getDefaultDisplaySync();
      if (screen.id === this.sourceDisplay && screen.width === this.sourceWidth && screen.height === this.sourceHeight) {
        return;
      }
    } catch { /* Cannot verify unchanged full-screen geometry: stop safely. */ }
    this.stop();
  };

  aboutToAppear(): void {
    this.running = modernHost.hasHost();
    this.timer = setInterval(() => this.poll(), 250);
  }

  private label(resource: Resource): string {
    try {
      const context: Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) { return context.resourceManager.getStringSync(resource.id); }
    } catch { /* Do not throw from an error path. */ }
    return 'resource_unavailable';
  }

  aboutToDisappear(): void {
    this.unwatchDisplay();
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    modernHost.requestClose();
    modernHost.close().catch(() => {});
  }

  private consentChanged(): void {
    if (!this.consent) { this.stop(); }
  }

  private start(): void {
    if (!this.consent || this.running || this.closing) { return; }
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const screen: display.Display = display.getDefaultDisplaySync();
      this.sourceWidth = screen.width;
      this.sourceHeight = screen.height;
      this.sourceDisplay = screen.id;
      display.on('change', this.displayChanged);
      this.watchingDisplay = true;
      // Actual full display pixels, not available window size or a lower preset.
      modernHost.start(context.filesDir, screen.width, screen.height);
      this.running = true;
      this.error = '';
      this.identity = '';
      this.phase = 'starting';
    } catch {
      this.unwatchDisplay();
      this.error = this.label($r('app.string.modern_host_start_failed'));
    }
  }

  private async stop(): Promise<void> {
    this.unwatchDisplay();
    modernHost.requestClose();
    if (this.closing || this.closeFailed) { return; }
    this.closing = true;
    this.request = '';
    this.requestOrigin = '';
    try {
      await modernHost.close();
      this.running = false;
      this.phase = 'closed';
    } catch {
      this.closeFailed = true;
      this.error = this.label($r('app.string.modern_host_close_failed'));
    } finally {
      this.closing = false;
    }
  }

  private unwatchDisplay(): void {
    if (!this.watchingDisplay) { return; }
    try { display.off('change', this.displayChanged); } catch { /* only this callback */ }
    this.watchingDisplay = false;
  }

  private decide(allow: boolean): void {
    if (!this.consent || this.request.length === 0 || this.closing) { return; }
    if (modernHost.approve(this.request, allow)) { this.request = ''; }
  }

  private revealIdentity(): void {
    if (!this.consent || !this.running) { return; }
    try {
      const value: ModernHostIdentity = modernHost.publicIdentity();
      this.identity = `${value.id}\n${value.peer_signing_key_base64}`;
    } catch { this.error = this.label($r('app.string.modern_host_identity_failed')); }
  }

  private poll(): void {
    if (!modernHost.hasHost()) { return; }
    try {
      const value: ModernHostSnapshot | undefined = modernHost.snapshot();
      if (value === undefined) { return; }
      this.phase = value.phase;
      this.request = value.approval_request;
      this.requestOrigin = value.approval_origin;
      this.sent = value.sent_units;
      this.geometry = `${value.width} × ${value.height} / ${value.codec} / ≤${value.fps}`;
      this.error = value.error === null ? '' : value.error;
      if (value.closed && !this.closing && !this.closeFailed) { this.stop(); }
    } catch {
      this.error = this.label($r('app.string.modern_host_state_failed'));
      modernHost.requestClose();
    }
  }

  build() {
    Column({ space: 6 }) {
      Text($r('app.string.modern_host_scope')).fontSize(12).width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        Button($r('app.string.modern_host_start')).enabled(this.consent && !this.running && !this.closing)
          .onClick(() => this.start()).id('modern_host_start')
        Button($r('app.string.modern_host_stop')).enabled(this.running && !this.closing && !this.closeFailed)
          .onClick(() => this.stop()).id('modern_host_stop')
        Button($r('app.string.modern_host_identity')).enabled(this.consent && this.running)
          .onClick(() => this.revealIdentity())
      }
      Text($r('app.string.modern_host_status', this.phase, this.geometry, this.sent))
        .fontSize(12).id('modern_host_status')
      if (this.request.length > 0 && !this.closing) {
        Text($r('app.string.modern_host_approval', this.requestOrigin)).fontSize(12)
        Row({ space: 8 }) {
          Button($r('app.string.modern_host_allow')).onClick(() => this.decide(true)).id('modern_host_allow')
          Button($r('app.string.modern_host_deny')).onClick(() => this.decide(false)).id('modern_host_deny')
        }
      }
      if (this.identity.length > 0) {
        Text(this.identity).fontSize(11).copyOption(CopyOptions.InApp)
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor($r('sys.color.ohos_id_color_warning')).id('modern_host_error')
      }
    }.width('100%')
  }
}
