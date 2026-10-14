import { describe, expect, it } from '@ohos/hypium';
import {
  mapHarmonyKeyCode,
  mapHarmonyKeyCodeToUsbHid,
  mapHarmonyPhysicalKeyCode,
} from '../../../main/ets/pages/rustdesk/RustDeskInputMapper';

export default function rustDeskPhysicalKeyMappingTest(): void {
  describe('RustDeskPhysicalKeyMappingTest', () => {
    it('swaps both Control and Meta sides for a Mac peer', 0, () => {
      const leftControl = mapHarmonyPhysicalKeyCode(2072, true);
      const rightControl = mapHarmonyPhysicalKeyCode(2073, true);
      const leftMeta = mapHarmonyPhysicalKeyCode(2076, true);
      const rightMeta = mapHarmonyPhysicalKeyCode(2077, true);

      expect(mapHarmonyKeyCode(leftControl)?.name).assertEqual('Meta');
      expect(mapHarmonyKeyCode(rightControl)?.name).assertEqual('RWin');
      expect(mapHarmonyKeyCode(leftMeta)?.name).assertEqual('VK_CONTROL');
      expect(mapHarmonyKeyCode(rightMeta)?.name).assertEqual('RControl');
      expect(mapHarmonyKeyCode(leftControl)?.modifier).assertEqual('command');
      expect(mapHarmonyKeyCode(rightControl)?.modifier).assertEqual('command');
      expect(mapHarmonyKeyCode(leftMeta)?.modifier).assertEqual('ctrl');
      expect(mapHarmonyKeyCode(rightMeta)?.modifier).assertEqual('ctrl');
      expect(mapHarmonyKeyCodeToUsbHid(leftControl)).assertEqual(0xE3);
      expect(mapHarmonyKeyCodeToUsbHid(rightControl)).assertEqual(0xE7);
      expect(mapHarmonyKeyCodeToUsbHid(leftMeta)).assertEqual(0xE0);
      expect(mapHarmonyKeyCodeToUsbHid(rightMeta)).assertEqual(0xE4);
    });

    it('keeps modifiers unchanged for non-Mac peers', 0, () => {
      expect(mapHarmonyPhysicalKeyCode(2072, false)).assertEqual(2072);
      expect(mapHarmonyPhysicalKeyCode(2073, false)).assertEqual(2073);
      expect(mapHarmonyPhysicalKeyCode(2076, false)).assertEqual(2076);
      expect(mapHarmonyPhysicalKeyCode(2077, false)).assertEqual(2077);
      expect(mapHarmonyPhysicalKeyCode(2019, true)).assertEqual(2019);
    });
  });
}
