import { UIAbility, Want, AbilityConstant } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { modernSession } from '../services/ModernSessionService';
import { modernHost } from '../services/ModernHostService';

// New runtime entry. Do not initialize the former Core/controlled-host services
// or subscribe to sensors before consent. Existing user storage is untouched.
export default class ModernEntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    try {
      stage.loadContent('pages/ModernDesk').catch(() => {
        hilog.error(0xFF00, 'RustDeskModern', 'Modern page loading failed');
      });
    } catch {
      hilog.error(0xFF00, 'RustDeskModern', 'Modern page loading failed');
    }
  }

  onWindowStageDestroy(): void {
    modernHost.requestClose();
    modernHost.close().catch(() => {});
    modernSession.requestClose();
    modernSession.close().catch(() => {});
  }

  onBackground(): void {
    // First host slice has no background-visible local approval surface. Stop
    // sharing rather than silently continuing capture after the UI disappears.
    modernHost.requestClose();
    modernHost.close().catch(() => {});
  }

  onDestroy(): void {
    modernHost.requestClose();
    modernHost.close().catch(() => {});
    modernSession.requestClose();
    modernSession.close().catch(() => {});
  }
}
