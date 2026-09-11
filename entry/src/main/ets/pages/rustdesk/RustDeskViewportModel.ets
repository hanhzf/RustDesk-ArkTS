import {
  mapLocalToRemote,
  mapRemoteToLocal,
  resolveCoordinateSpace,
  LocalPointerPosition,
  RemotePointerPosition,
  RustDeskCoordinateSpace,
  RustDeskRect,
  RustDeskSize,
} from './RustDeskInputMapper';
import { PeerDisplayInfo, ResolutionInfo } from './RustDeskTypes';

function isPixelSize(width: number, height: number): boolean {
  return Number.isSafeInteger(width) && Number.isSafeInteger(height) && width > 0 && height > 0;
}

// FlutterHandler projects only scaled_width = round(width/scale), not height.
// An optional scaled_height is validated when present. original_* is the initial mode,
// not a scale source: it need not equal the current mode after a resolution change.
export function getPeerDisplayScale(display: PeerDisplayInfo): number | undefined {
  const width = display.scaled_width ?? 0;
  if (!isPixelSize(display.width, display.height) || !isPixelSize(width, 1)) {
    return undefined;
  }
  const widthRatio = display.width / width;
  if (display.scaled_height === undefined) {
    return widthRatio;
  }
  const height = display.scaled_height;
  if (!isPixelSize(width, height)) {
    return undefined;
  }
  const lower = Math.max(display.width / (width + 0.5), display.height / (height + 0.5));
  const upper = Math.min(display.width / (width - 0.5), display.height / (height - 0.5));
  if (lower >= upper) {
    return undefined;
  }
  const ratio = widthRatio > lower && widthRatio <= upper ? widthRatio : (lower + upper) / 2;
  return Math.round(display.width / ratio) === width && Math.round(display.height / ratio) === height
    ? ratio : undefined;
}

export function getPeerDisplayModeSize(display: PeerDisplayInfo): ResolutionInfo | undefined {
  const ratio = getPeerDisplayScale(display);
  if (ratio === undefined) {
    return undefined;
  }
  return {
    width: display.scaled_width ?? 0,
    height: display.scaled_height ?? Math.round(display.height / ratio),
  };
}

export function findPeerResolutionIndex(
  display: PeerDisplayInfo | undefined,
  resolutions: ResolutionInfo[],
  requested: ResolutionInfo | undefined = undefined,
): number {
  const size = requested ?? (display === undefined ? undefined : getPeerDisplayModeSize(display));
  if (size === undefined || !isPixelSize(size.width, size.height)) {
    return -1;
  }
  for (let index = 0; index < resolutions.length; index += 1) {
    if (resolutions[index].width === size.width && resolutions[index].height === size.height) {
      return index;
    }
  }
  return -1;
}

// A sparse switch event supplies new raw geometry, but no new scale. Retain only
// a consistent known ratio; never infer Retina from original_* or pixel maxima.
export function updatePeerDisplayGeometry(
  previous: PeerDisplayInfo, width: number, height: number, x: number, y: number,
): PeerDisplayInfo {
  const ratio = getPeerDisplayScale(previous);
  const unchanged = width === previous.width && height === previous.height;
  const updated: PeerDisplayInfo = {
    width, height, x, y,
    cursor_embedded: previous.cursor_embedded,
    original_width: previous.original_width,
    original_height: previous.original_height,
  };
  if (isPixelSize(width, height) && ratio !== undefined) {
    updated.scaled_width = unchanged ? previous.scaled_width : Math.round(width / ratio);
    updated.scaled_height = unchanged ? previous.scaled_height : Math.round(height / ratio);
  }
  return updated;
}

export interface RustDeskRenderPlan {
  display: number;
  remoteRect: RustDeskRect;
  contentRect: RustDeskRect;
  renderSize: RustDeskSize;
  videoSize: RustDeskSize;
  surfaceSize: RustDeskSize;
  scale: number;
}

export class RustDeskViewportModel {
  private displays: PeerDisplayInfo[] = [];
  private currentDisplay: number = 0;
  private viewportWidth: number = 0;
  private viewportHeight: number = 0;
  private surfaceWidth: number = 0;
  private surfaceHeight: number = 0;
  private rotation: number = 0;
  private viewScale: number = 1;
  private viewOffsetX: number = 0;
  private viewOffsetY: number = 0;
  private viewRotation: number = 0;
  private submittedVideoSize: RustDeskSize | undefined = undefined;

  reset(): void {
    this.resetSessionGeometry();
    this.viewportWidth = 0;
    this.viewportHeight = 0;
  }

  resetSessionGeometry(): void {
    this.displays = [];
    this.submittedVideoSize = undefined;
    this.currentDisplay = 0;
    this.surfaceWidth = 0;
    this.surfaceHeight = 0;
    this.rotation = 0;
    this.viewScale = 1;
    this.viewOffsetX = 0;
    this.viewOffsetY = 0;
    this.viewRotation = 0;
  }

  setPeerDisplays(displays: PeerDisplayInfo[], currentDisplay: number): void {
    // A fresh authoritative mode report invalidates the previous submission sample.
    this.submittedVideoSize = undefined;
    this.displays = displays;
    this.currentDisplay = this.clampDisplayIndex(currentDisplay);
  }

  setViewportSize(width: number, height: number): void {
    if (width > 0) {
      this.viewportWidth = width;
    }
    if (height > 0) {
      this.viewportHeight = height;
    }
  }

  setSurfaceSize(width: number, height: number): void {
    this.surfaceWidth = Math.max(Math.round(width), 0);
    this.surfaceHeight = Math.max(Math.round(height), 0);
  }

  setRotation(rotation: number): void {
    this.rotation = rotation;
  }

  setViewTransform(scale: number, offsetX: number, offsetY: number, rotation: number): void {
    this.viewScale = Number.isFinite(scale) && scale > 0 ? scale : 1;
    this.viewOffsetX = Number.isFinite(offsetX) ? offsetX : 0;
    this.viewOffsetY = Number.isFinite(offsetY) ? offsetY : 0;
    this.viewRotation = Number.isFinite(rotation) ? rotation : 0;
  }

  selectDisplay(index: number): boolean {
    if (!Number.isFinite(index)) return false;
    const normalized = Math.floor(index);
    if (normalized < 0 || normalized >= this.displays.length) return false;
    this.submittedVideoSize = undefined;
    this.currentDisplay = normalized;
    return true;
  }

  getCurrentDisplayIndex(): number {
    return this.clampDisplayIndex(this.currentDisplay);
  }

  getCurrentDisplay(): PeerDisplayInfo | undefined {
    if (this.displays.length === 0) {
      return undefined;
    }
    return this.displays[this.getCurrentDisplayIndex()];
  }

  getRemoteRect(): RustDeskRect | undefined {
    const displayInfo = this.getCurrentDisplay();
    if (!displayInfo || !isPixelSize(displayInfo.width, displayInfo.height)) {
      return undefined;
    }
    return new RustDeskRect(displayInfo.x, displayInfo.y, displayInfo.width, displayInfo.height);
  }

  getDisplayScaleFactor(): number {
    const displayInfo = this.getCurrentDisplay();
    return displayInfo === undefined ? 1 : getPeerDisplayScale(displayInfo) ?? 1;
  }

  // Observed video dimensions are metadata, never a peer mode or input rectangle.
  // Keep buildRenderPlan.videoSize as renderer configuration, not this sample.
  setSubmittedVideoSize(display: number, width: number, height: number): boolean {
    if (!Number.isInteger(display) || display !== this.getCurrentDisplayIndex()
      || this.getCurrentDisplay() === undefined || !isPixelSize(width, height)) {
      return false;
    }
    this.submittedVideoSize = new RustDeskSize(width, height);
    return true;
  }

  getSubmittedVideoSize(): RustDeskSize | undefined {
    const size = this.submittedVideoSize;
    return size === undefined ? undefined : new RustDeskSize(size.width, size.height);
  }

  clearSubmittedVideoSize(): void {
    this.submittedVideoSize = undefined;
  }

  getCoordinateSpace(): RustDeskCoordinateSpace | undefined {
    const remoteRect = this.getRemoteRect();
    if (!remoteRect || this.viewportWidth <= 0 || this.viewportHeight <= 0) {
      return undefined;
    }
    const space = resolveCoordinateSpace(
      this.viewportWidth,
      this.viewportHeight,
      remoteRect,
      this.rotation,
    );
    space.viewScale = this.viewScale;
    space.viewOffsetX = this.viewOffsetX;
    space.viewOffsetY = this.viewOffsetY;
    space.viewRotation = this.viewRotation;
    return space;
  }

  getRenderSize(): RustDeskSize {
    const space = this.getCoordinateSpace();
    if (space) {
      return new RustDeskSize(
        Math.max(Math.round(space.renderSize.width), 1),
        Math.max(Math.round(space.renderSize.height), 1),
      );
    }
    const remoteRect = this.getRemoteRect();
    if (remoteRect) {
      return new RustDeskSize(Math.max(Math.round(remoteRect.width), 1), Math.max(Math.round(remoteRect.height), 1));
    }
    return new RustDeskSize(1, 1);
  }

  getSurfaceRenderSize(): RustDeskSize {
    if (this.surfaceWidth > 0 && this.surfaceHeight > 0) {
      return new RustDeskSize(this.surfaceWidth, this.surfaceHeight);
    }
    return this.getRenderSize();
  }

  getSurfaceSize(): RustDeskSize {
    return new RustDeskSize(this.surfaceWidth, this.surfaceHeight);
  }

  buildRenderPlan(): RustDeskRenderPlan | undefined {
    const space = this.getCoordinateSpace();
    const remoteRect = this.getRemoteRect();
    if (!space || !remoteRect) {
      return undefined;
    }
    const renderSize = this.getRenderSize();
    return {
      display: this.getCurrentDisplayIndex(),
      remoteRect,
      contentRect: space.paintRect,
      renderSize,
      videoSize: new RustDeskSize(
        Math.max(Math.round(remoteRect.width), 1),
        Math.max(Math.round(remoteRect.height), 1),
      ),
      surfaceSize: this.getSurfaceSize(),
      scale: this.getDisplayScaleFactor(),
    };
  }

  mapLocalToRemote(localX: number, localY: number): RemotePointerPosition | undefined {
    const space = this.getCoordinateSpace();
    if (!space) {
      return undefined;
    }
    return mapLocalToRemote(space, localX, localY);
  }

  mapRemoteToLocal(remoteX: number, remoteY: number): LocalPointerPosition | undefined {
    const space = this.getCoordinateSpace();
    if (!space) {
      return undefined;
    }
    return mapRemoteToLocal(space, remoteX, remoteY);
  }

  describeRenderPlan(): string {
    const plan = this.buildRenderPlan();
    if (!plan) {
      return 'Display not ready';
    }
    const surfaceWidth = plan.surfaceSize.width > 0 ? plan.surfaceSize.width : plan.renderSize.width;
    const surfaceHeight = plan.surfaceSize.height > 0 ? plan.surfaceSize.height : plan.renderSize.height;
    return `Remote ${plan.videoSize.width}x${plan.videoSize.height} -> surface ${surfaceWidth}x${surfaceHeight}`;
  }

  private clampDisplayIndex(index: number): number {
    if (this.displays.length === 0) {
      return 0;
    }
    const normalized = Number.isFinite(index) ? Math.floor(index) : 0;
    return Math.min(Math.max(normalized, 0), this.displays.length - 1);
  }
}
