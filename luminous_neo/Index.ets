export enum LuminousControlSize {
  Compact,
  Regular,
}

export enum LuminousTone {
  Neutral,
  Accent,
  Danger,
}

export class LuminousSelectionItem {
  value: string;
  label: ResourceStr;
  description: ResourceStr;
  isEnabled: boolean;

  constructor(value: string, label: ResourceStr, description: ResourceStr = '', isEnabled: boolean = true) {
    this.value = value;
    this.label = label;
    this.description = description;
    this.isEnabled = isEnabled;
  }
}

export class LuminousNeoTokens {
  static readonly BASE_SURFACE_SIZE: number = 44;
  static readonly COMPACT_HEIGHT: number = 36;
  static readonly REGULAR_HEIGHT: number = 44;
  static readonly SUBTLE_RAISED_DEPTH: number = 1;

  static controlHeight(size: LuminousControlSize): number {
    return size === LuminousControlSize.Compact ?
      LuminousNeoTokens.COMPACT_HEIGHT : LuminousNeoTokens.REGULAR_HEIGHT;
  }

  static shadowPaddingFor(size: number): number {
    return Math.max(6, Math.round(size * 0.18));
  }
}

export class LuminousMotionLight {
  static disableSensorSubscription(): void {}
  static enableSensorSubscription(): void {}
  static resume(): void {}
  static suspend(): void {}
}

@Builder
function EmptySurfaceContent() {}

@Component
export struct LuminousSurface {
  @Prop depth: number = 0;
  @Prop surfaceWidth: number = 44;
  @Prop surfaceHeight: number = 44;
  @Prop cornerRadius: number = 12;
  @Prop contentAlignment: Alignment = Alignment.Center;
  @Prop motionEnabled: boolean = false;
  @BuilderParam content: () => void = EmptySurfaceContent;

  build() {
    Stack({ alignContent: this.contentAlignment }) {
      Row() {}
      .width(this.surfaceWidth)
      .height(this.surfaceHeight)
      .backgroundColor(this.depth < 0 ? '#E4E8EE' : '#F5F7FA')
      .borderRadius(this.cornerRadius)
      .border({ width: this.depth < 0 ? 1 : 0, color: '#D5DAE2' })
      .shadow(this.depth > 0 ? {
        radius: Math.min(18, 4 + this.depth * 2),
        color: '#26000000',
        offsetX: 0,
        offsetY: Math.min(8, 2 + this.depth),
      } : undefined)

      this.content()
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
  }
}

@Component
export struct LuminousButton {
  @Prop label: ResourceStr = '';
  @Prop controlWidth: number = 160;
  @Prop controlSizeMode: LuminousControlSize = LuminousControlSize.Regular;
  @Prop tone: LuminousTone = LuminousTone.Neutral;
  @Prop isEnabled: boolean = true;
  @Prop motionEnabled: boolean = false;
  onAction: () => void = (): void => {};

  private buttonBackgroundColor(): ResourceColor {
    if (this.tone === LuminousTone.Accent) {
      return '#1677FF';
    }
    if (this.tone === LuminousTone.Danger) {
      return '#D92D20';
    }
    return '#E8ECF2';
  }

  private buttonTextColor(): ResourceColor {
    return this.tone === LuminousTone.Neutral ? '#182230' : Color.White;
  }

  build() {
    Button(this.label)
      .width(this.controlWidth)
      .height(LuminousNeoTokens.controlHeight(this.controlSizeMode))
      .borderRadius(LuminousNeoTokens.controlHeight(this.controlSizeMode) / 2)
      .backgroundColor(this.buttonBackgroundColor())
      .fontColor(this.buttonTextColor())
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? 1 : 0.45)
      .onClick((): void => this.onAction())
  }
}

@Component
export struct LuminousTextField {
  @Prop value: string = '';
  @Prop placeholder: ResourceStr = '';
  @Prop fieldWidth: number = 240;
  @Prop fieldHeight: number = 44;
  @Prop inputType: InputType = InputType.Normal;
  @Prop maxLength: number = 1000;
  @Prop isEnabled: boolean = true;
  @Prop motionEnabled: boolean = false;
  onChange: (value: string) => void = (_value: string): void => {};

  build() {
    TextInput({ text: this.value, placeholder: this.placeholder })
      .width(this.fieldWidth)
      .height(this.fieldHeight)
      .type(this.inputType)
      .maxLength(this.maxLength)
      .enabled(this.isEnabled)
      .backgroundColor('#F5F7FA')
      .borderRadius(this.fieldHeight / 2)
      .padding({ left: 16, right: 16 })
      .onChange((value: string): void => this.onChange(value))
  }
}

@Component
export struct LuminousSearchField {
  @Prop value: string = '';
  @Prop placeholder: ResourceStr = '';
  @Prop fieldWidth: number = 240;
  @Prop fieldHeight: number = 44;
  @Prop motionEnabled: boolean = false;
  onChange: (value: string) => void = (_value: string): void => {};

  build() {
    TextInput({ text: this.value, placeholder: this.placeholder })
      .width(this.fieldWidth)
      .height(this.fieldHeight)
      .type(InputType.Normal)
      .backgroundColor('#F5F7FA')
      .borderRadius(this.fieldHeight / 2)
      .padding({ left: 16, right: 16 })
      .onChange((value: string): void => this.onChange(value))
  }
}

@Component
export struct LuminousSwitch {
  @Prop label: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop isOn: boolean = false;
  @Prop rowWidth: number = 320;
  @Prop isEnabled: boolean = true;
  @Prop motionEnabled: boolean = false;
  onChange: (value: boolean) => void = (_value: boolean): void => {};

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.label)
          .fontSize(15)
          .fontColor('#182230')
        if (this.description !== '') {
          Text(this.description)
            .fontSize(12)
            .fontColor('#667085')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .enabled(this.isEnabled)
        .onChange((value: boolean): void => this.onChange(value))
    }
    .width(this.rowWidth)
    .height(44)
    .opacity(this.isEnabled ? 1 : 0.45)
  }
}

@Component
export struct LuminousSegmentedControl {
  @Prop items: LuminousSelectionItem[] = [];
  @Prop selectedIndex: number = 0;
  @Prop controlWidth: number = 300;
  @Prop controlHeight: number = 44;
  @Prop motionEnabled: boolean = false;
  onChange: (index: number) => void = (_index: number): void => {};

  build() {
    Row({ space: 4 }) {
      ForEach(this.items, (item: LuminousSelectionItem, index: number) => {
        Button(item.label)
          .layoutWeight(1)
          .height(this.controlHeight - 4)
          .borderRadius((this.controlHeight - 4) / 2)
          .backgroundColor(index === this.selectedIndex ? '#1677FF' : Color.Transparent)
          .fontColor(index === this.selectedIndex ? Color.White : '#344054')
          .enabled(item.isEnabled)
          .opacity(item.isEnabled ? 1 : 0.45)
          .onClick((): void => this.onChange(index))
      }, (item: LuminousSelectionItem): string => item.value)
    }
    .width(this.controlWidth)
    .height(this.controlHeight)
    .padding(2)
    .backgroundColor('#E8ECF2')
    .borderRadius(this.controlHeight / 2)
  }
}

@Component
export struct LuminousSlider {
  @Prop label: ResourceStr = '';
  @Prop value: number = 0;
  @Prop minimum: number = 0;
  @Prop maximum: number = 100;
  @Prop step: number = 1;
  @Prop sliderWidth: number = 300;
  @Prop motionEnabled: boolean = false;
  onChange: (value: number, mode: SliderChangeMode) => void =
    (_value: number, _mode: SliderChangeMode): void => {};

  build() {
    Column({ space: 6 }) {
      if (this.label !== '') {
        Text(this.label)
          .width('100%')
          .fontSize(14)
          .fontColor('#344054')
      }
      Slider({ value: this.value, min: this.minimum, max: this.maximum, step: this.step })
        .width(this.sliderWidth)
        .selectedColor('#1677FF')
        .onChange((value: number, mode: SliderChangeMode): void => this.onChange(value, mode))
    }
    .width(this.sliderWidth)
  }
}

@Component
export struct LuminousSecondaryMenu {
  @Prop items: LuminousSelectionItem[] = [];
  @Prop selectedIndex: number = 0;
  @Prop controlWidth: number = 300;
  @Prop mainHeight: number = 44;
  @Prop itemHeight: number = 40;
  @Prop accessibilityLabel: ResourceStr = '';
  @Prop handleAccessibilityLabel: ResourceStr = '';
  @Prop isEnabled: boolean = true;
  @Prop motionEnabled: boolean = false;
  onChange: (index: number) => void = (_index: number): void => {};

  build() {
    Row({ space: 4 }) {
      ForEach(this.items, (item: LuminousSelectionItem, index: number) => {
        Button(item.label)
          .layoutWeight(1)
          .height(this.itemHeight)
          .borderRadius(this.itemHeight / 2)
          .backgroundColor(index === this.selectedIndex ? '#1677FF' : Color.Transparent)
          .fontColor(index === this.selectedIndex ? Color.White : '#344054')
          .enabled(this.isEnabled && item.isEnabled)
          .onClick((): void => this.onChange(index))
      }, (item: LuminousSelectionItem): string => item.value)
    }
    .width(this.controlWidth)
    .height(this.mainHeight)
    .padding(2)
    .backgroundColor('#E8ECF2')
    .borderRadius(this.mainHeight / 2)
    .opacity(this.isEnabled ? 1 : 0.45)
  }
}
