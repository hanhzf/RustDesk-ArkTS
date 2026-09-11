import { describe, expect, it } from '@ohos/hypium';
import {
  findPeerResolutionIndex, getPeerDisplayModeSize, getPeerDisplayScale,
  RustDeskViewportModel, updatePeerDisplayGeometry,
} from '../../../main/ets/pages/rustdesk/RustDeskViewportModel';
import { PeerDisplayInfo, ResolutionInfo } from '../../../main/ets/pages/rustdesk/RustDeskTypes';

export default function viewportModelTest(): void {
  describe('RustDeskViewportModelTest', () => {
    it('matches HiDPI modes including width-only FlutterHandler payloads and sparse switches', 0, () => {
      // Production make_displays_msg has neither scaled_height nor raw scale.
      // original_* is also optional, so it cannot be a prerequisite for HiDPI.
      const first: PeerDisplayInfo = {
        width: 5120, height: 2880, x: 0, y: 0, scaled_width: 2560,
      };
      const second: PeerDisplayInfo = {
        width: 3000, height: 2000, x: 5120, y: 0, scaled_width: 2000,
      };
      expect(getPeerDisplayScale(first)).assertEqual(2);
      expect(getPeerDisplayScale(second)).assertEqual(1.5);
      const mode = getPeerDisplayModeSize(first);
      const fractionalMode = getPeerDisplayModeSize(second);
      expect(mode !== undefined && fractionalMode !== undefined).assertTrue();
      if (mode && fractionalMode) {
        expect(mode.width).assertEqual(2560);
        expect(mode.height).assertEqual(1440);
        expect(fractionalMode.height).assertEqual(1333);
      }
      expect(findPeerResolutionIndex(first, [{ width: 2560, height: 1440 }])).assertEqual(0);
      const same = updatePeerDisplayGeometry(first, 5120, 2880, 10, 20);
      expect(same.scaled_width).assertEqual(2560);
      expect(getPeerDisplayScale(same)).assertEqual(2);
      const resized = updatePeerDisplayGeometry(same, 3840, 2160, 10, 20);
      expect(resized.scaled_width).assertEqual(1920);
      expect(resized.scaled_height).assertEqual(1080);
      expect(getPeerDisplayScale(resized)).assertEqual(2);
      const fractionalResize = updatePeerDisplayGeometry(second, 2400, 1600, 5120, 0);
      expect(fractionalResize.scaled_width).assertEqual(1600);
      expect(fractionalResize.scaled_height).assertEqual(1067);
      const model = new RustDeskViewportModel();
      model.setPeerDisplays([same, second], 0);
      expect(model.getDisplayScaleFactor()).assertEqual(2);
      expect(model.selectDisplay(1)).assertTrue();
      expect(model.getDisplayScaleFactor()).assertEqual(1.5);
      model.setPeerDisplays([resized, fractionalResize], 1);
      expect(model.getDisplayScaleFactor()).assertEqual(1.5);
      expect(model.selectDisplay(0)).assertTrue();
      expect(model.getDisplayScaleFactor()).assertEqual(2);

      const display: PeerDisplayInfo = {
        width: 5120, height: 2880, x: 0, y: 0,
        original_width: 2560, original_height: 1440, scaled_width: 2560, scaled_height: 1440,
      };
      const modes: ResolutionInfo[] = [
        { width: 5120, height: 2880 }, { width: 2560, height: 1440 },
      ];
      expect(getPeerDisplayScale(display)).assertEqual(2);
      const size = getPeerDisplayModeSize(display);
      expect(size !== undefined).assertTrue();
      if (size) {
        expect(size.width).assertEqual(2560);
        expect(size.height).assertEqual(1440);
      }
      expect(findPeerResolutionIndex(display, modes)).assertEqual(1);
      expect(findPeerResolutionIndex(display, [modes[0]])).assertEqual(-1);
      expect(findPeerResolutionIndex(display, [])).assertEqual(-1);
      expect(findPeerResolutionIndex(undefined, modes)).assertEqual(-1);
      expect(findPeerResolutionIndex(display, modes, { width: 1280, height: 720 })).assertEqual(-1);
      expect(findPeerResolutionIndex(display, modes, modes[0])).assertEqual(0);
    });

    it('preserves known ratios for sparse same-size and resized switch confirmations', 0, () => {
      const display: PeerDisplayInfo = {
        width: 5120, height: 2880, x: 0, y: 0,
        original_width: 2560, original_height: 1440, scaled_width: 2560, scaled_height: 1440,
      };
      const same = updatePeerDisplayGeometry(display, 5120, 2880, -5120, 20);
      expect(same.scaled_width).assertEqual(2560);
      expect(same.scaled_height).assertEqual(1440);
      expect(same.x).assertEqual(-5120);
      const changed = updatePeerDisplayGeometry(same, 3840, 2160, 100, 20);
      expect(changed.scaled_width).assertEqual(1920);
      expect(changed.scaled_height).assertEqual(1080);
      expect(changed.original_width).assertEqual(2560);
      expect(getPeerDisplayScale(changed)).assertEqual(2);
      expect(display.width).assertEqual(5120);
      expect(display.x).assertEqual(0);
      const fractional: PeerDisplayInfo = {
        width: 3000, height: 2000, x: 0, y: 0, scaled_width: 2000, scaled_height: 1333,
      };
      expect(getPeerDisplayScale(fractional)).assertEqual(1.5);
      const resized = updatePeerDisplayGeometry(fractional, 2400, 1600, 0, 0);
      expect(resized.scaled_width).assertEqual(1600);
      expect(resized.scaled_height).assertEqual(1067);
    });

    it('does not invent scale from missing conflicting or invalid authoritative metadata', 0, () => {
      const missing: PeerDisplayInfo = {
        width: 5120, height: 2880, x: 0, y: 0, original_width: 2560, original_height: 1440,
      };
      const conflicting: PeerDisplayInfo = {
        width: 5120, height: 2880, x: 0, y: 0, scaled_width: 2560, scaled_height: 2880,
      };
      const invalid: PeerDisplayInfo = {
        width: 5120, height: 2880, x: 0, y: 0, scaled_width: Number.NaN, scaled_height: 1440,
      };
      const samples: PeerDisplayInfo[] = [missing, conflicting, invalid];
      for (let index = 0; index < samples.length; index += 1) {
        expect(getPeerDisplayScale(samples[index]) === undefined).assertTrue();
        expect(getPeerDisplayModeSize(samples[index]) === undefined).assertTrue();
        expect(findPeerResolutionIndex(samples[index], [{ width: 5120, height: 2880 }])).assertEqual(-1);
        const updated = updatePeerDisplayGeometry(samples[index], 3840, 2160, 0, 0);
        expect(updated.scaled_width === undefined).assertTrue();
        expect(updated.scaled_height === undefined).assertTrue();
      }
    });

    it('keeps submitted video dimensions separate from peer mode fit and normalized input', 0, () => {
      const model = new RustDeskViewportModel();
      const display: PeerDisplayInfo = {
        width: 5120, height: 2880, x: -5120, y: 100,
        original_width: 2560, original_height: 1440, scaled_width: 2560, scaled_height: 1440,
      };
      model.setViewportSize(1280, 800);
      model.setPeerDisplays([display], 0);
      model.setViewTransform(1.5, 30, 20, 0);
      const before = model.buildRenderPlan();
      const pointer = model.mapLocalToRemote(700, 450);
      // Deliberately different aspect: a video sample must not redefine the peer.
      expect(model.setSubmittedVideoSize(0, 1920, 1200)).assertTrue();
      const after = model.buildRenderPlan();
      const mapped = model.mapLocalToRemote(700, 450);
      expect(before !== undefined && after !== undefined && pointer !== undefined && mapped !== undefined).assertTrue();
      if (before && after && pointer && mapped) {
        expect(after.remoteRect.width).assertEqual(5120);
        expect(after.remoteRect.height).assertEqual(2880);
        expect(after.videoSize.width).assertEqual(before.videoSize.width);
        expect(after.contentRect.height).assertEqual(before.contentRect.height);
        expect(after.contentRect.top).assertEqual(before.contentRect.top);
        expect(after.scale).assertEqual(2);
        expect(mapped.x).assertEqual(pointer.x);
        expect(mapped.y).assertEqual(pointer.y);
        const local = model.mapRemoteToLocal(mapped.x, mapped.y);
        expect(local !== undefined).assertTrue();
        if (local) {
          expect(Math.abs(local.x - 700) <= 1).assertTrue();
          expect(Math.abs(local.y - 450) <= 1).assertTrue();
        }
      }
      expect(display.width).assertEqual(5120);
      expect(display.scaled_width).assertEqual(2560);
      const video = model.getSubmittedVideoSize();
      expect(video !== undefined).assertTrue();
      if (video) {
        expect(video.width).assertEqual(1920);
        expect(video.height).assertEqual(1200);
      }
      expect(model.setSubmittedVideoSize(1, 640, 480)).assertFalse();
      expect(model.setSubmittedVideoSize(0, 0, 480)).assertFalse();
      // Same-display Surface/route replacement must not expose the old submission.
      model.clearSubmittedVideoSize();
      expect(model.getSubmittedVideoSize() === undefined).assertTrue();
      expect(model.getCurrentDisplay()).assertEqual(display);
      expect(model.getDisplayScaleFactor()).assertEqual(2);
      expect(model.setSubmittedVideoSize(0, 1280, 720)).assertTrue();
      const fresh = model.getSubmittedVideoSize();
      expect(fresh !== undefined).assertTrue();
      if (fresh) {
        expect(fresh.width).assertEqual(1280);
        fresh.width = 1;
        const retained = model.getSubmittedVideoSize();
        expect(retained !== undefined).assertTrue();
        if (retained) {
          expect(retained.width).assertEqual(1280);
        }
      }
      model.setPeerDisplays([display], 0);
      expect(model.getSubmittedVideoSize() === undefined).assertTrue();
    });

    it('invalidates submission metadata on switch and reset without fabricating unknown geometry', 0, () => {
      const model = new RustDeskViewportModel();
      model.setViewportSize(1280, 800);
      expect(model.setSubmittedVideoSize(0, 1920, 1080)).assertFalse();
      expect(model.buildRenderPlan() === undefined).assertTrue();
      const displays: PeerDisplayInfo[] = [
        { width: 5120, height: 2880, x: 0, y: 0, scaled_width: 2560, scaled_height: 1440 },
        { width: 1920, height: 1080, x: 5120, y: 0, scaled_width: 1920, scaled_height: 1080 },
      ];
      model.setPeerDisplays(displays, 0);
      expect(model.setSubmittedVideoSize(0, 2560, 1440)).assertTrue();
      expect(model.selectDisplay(1)).assertTrue();
      expect(model.getSubmittedVideoSize() === undefined).assertTrue();
      expect(model.getDisplayScaleFactor()).assertEqual(1);
      expect(model.setSubmittedVideoSize(0, 2560, 1440)).assertFalse();
      expect(model.setSubmittedVideoSize(1, 1280, 720)).assertTrue();
      model.resetSessionGeometry();
      expect(model.getSubmittedVideoSize() === undefined).assertTrue();
      expect(model.getRemoteRect() === undefined).assertTrue();
      expect(model.mapLocalToRemote(100, 100) === undefined).assertTrue();
    });

    it('selectDisplay changes only to a valid display', 0, () => {
      const model = new RustDeskViewportModel();
      const displays: PeerDisplayInfo[] = [
        { width: 1920, height: 1080, x: 0, y: 0 },
        { width: 1280, height: 1024, x: 1920, y: 0 },
      ];
      model.setPeerDisplays(displays, 0);

      expect(model.selectDisplay(1)).assertTrue();
      expect(model.getCurrentDisplayIndex()).assertEqual(1);
      expect(model.selectDisplay(2)).assertFalse();
      expect(model.getCurrentDisplayIndex()).assertEqual(1);
    });

    it('centers a portrait remote display inside a landscape PC viewport', 0, () => {
      const model = new RustDeskViewportModel();
      const displays: PeerDisplayInfo[] = [
        { width: 1080, height: 1920, x: 0, y: 0 },
      ];
      model.setViewportSize(1920, 1080);
      model.setPeerDisplays(displays, 0);

      const plan = model.buildRenderPlan();
      expect(plan !== undefined).assertTrue();
      if (!plan) {
        return;
      }
      expect(plan.contentRect.left > 0).assertTrue();
      expect(plan.contentRect.top).assertEqual(0);
      expect(plan.contentRect.width < 1920).assertTrue();
      expect(plan.contentRect.height).assertEqual(1080);
    });

    it('preserves the measured viewport while resetting session geometry', 0, () => {
      const model = new RustDeskViewportModel();
      const firstDisplays: PeerDisplayInfo[] = [
        { width: 1920, height: 1080, x: 0, y: 0 },
      ];
      const nextDisplays: PeerDisplayInfo[] = [
        { width: 1280, height: 720, x: 0, y: 0 },
      ];
      model.setViewportSize(960, 540);
      model.setPeerDisplays(firstDisplays, 0);
      model.setSurfaceSize(1920, 1080);
      model.setViewTransform(1.5, 20, 10, 0);

      model.resetSessionGeometry();
      expect(model.getCoordinateSpace() === undefined).assertTrue();

      model.setPeerDisplays(nextDisplays, 0);
      expect(model.getCoordinateSpace() !== undefined).assertTrue();
      const plan = model.buildRenderPlan();
      expect(plan !== undefined).assertTrue();
      if (!plan) {
        return;
      }
      expect(plan.contentRect.width).assertEqual(960);
      expect(plan.contentRect.height).assertEqual(540);
      expect(plan.surfaceSize.width).assertEqual(0);
      expect(plan.surfaceSize.height).assertEqual(0);

      const mapped = model.mapLocalToRemote(480, 270);
      expect(mapped !== undefined).assertTrue();
      if (mapped) {
        expect(mapped.x).assertEqual(640);
        expect(mapped.y).assertEqual(360);
      }

      model.reset();
      model.setPeerDisplays(nextDisplays, 0);
      expect(model.getCoordinateSpace() === undefined).assertTrue();
    });
  });
}
