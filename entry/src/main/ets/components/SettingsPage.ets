@Component
export struct SettingsPage {
  @Prop routingMode: string;
  @Prop autoUpdateHours: number;
  @Prop autoSelectNode: boolean;
  @Prop preferredCountries: string[];
  @Prop version: string;
  @Prop dark: boolean;
  onAutoUpdate: (hours: number) => void = (_hours: number) => {};
  onAutoSelect: (enabled: boolean) => void = (_enabled: boolean) => {};
  onCountry: (country: string) => void = (_country: string) => {};

  build() {
    Column({ space: 12 }) {
      Column({ space: 0 }) {
        this.sectionHeader('网络')
        this.row('当前模式', this.routingMode)
        Divider().color(this.dark ? '#303641' : '#EAECF0')
        this.row('DNS', 'Fake-IP · IPv4')
        Divider().color(this.dark ? '#303641' : '#EAECF0')
        this.row('局域网', '规则模式下直连')
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .borderRadius(18).backgroundColor(this.dark ? '#1B1E24' : Color.White)

      Column({ space: 12 }) {
        Row() {
          Column({ space: 3 }) {
            Text('自动选择最佳节点').fontSize(15).fontWeight(FontWeight.Medium)
              .fontColor(this.dark ? '#F3F4F6' : '#172033')
            Text('连接时自动测速并选择最低延迟节点').fontSize(11)
              .fontColor(this.dark ? '#A6ADBB' : '#667085')
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.autoSelectNode })
            .selectedColor('#315CFF').onChange((enabled: boolean) => this.onAutoSelect(enabled))
        }.width('100%')
        if (this.autoSelectNode) {
          Divider().color(this.dark ? '#303641' : '#EAECF0')
          Text('优先地区').fontSize(12).fontColor(this.dark ? '#A6ADBB' : '#667085')
          Row({ space: 7 }) {
            this.countryButton('香港')
            this.countryButton('台湾')
            this.countryButton('日本')
          }.width('100%')
          Row({ space: 7 }) {
            this.countryButton('新加坡')
            this.countryButton('美国')
            this.countryButton('韩国')
          }.width('100%')
          Text('优先地区均不可用时，会自动从其他地区选择。').fontSize(11)
            .fontColor(this.dark ? '#7F8794' : '#98A2B3')
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
        .borderRadius(18).backgroundColor(this.dark ? '#1B1E24' : Color.White)

      Column({ space: 12 }) {
        this.sectionHeader('订阅自动更新')
        Row({ space: 8 }) {
          this.updateButton('关闭', 0)
          this.updateButton('12 小时', 12)
          this.updateButton('24 小时', 24)
        }.width('100%')
        Text('应用启动时会检查启用配置是否到达更新周期。').fontSize(12)
          .fontColor(this.dark ? '#A6ADBB' : '#667085')
      }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
        .borderRadius(18).backgroundColor(this.dark ? '#1B1E24' : Color.White)

      Column({ space: 0 }) {
        this.sectionHeader('关于')
        this.row('支持系统', 'HarmonyOS 6.0 及以上')
        Divider().color(this.dark ? '#303641' : '#EAECF0')
        this.row('支持设备', '手机 · PC/二合一设备')
        Divider().color(this.dark ? '#303641' : '#EAECF0')
        this.row('版本', this.version)
        Divider().color(this.dark ? '#303641' : '#EAECF0')
        this.row('隐私', '本地优先 · 无广告 · 无遥测')
        Divider().color(this.dark ? '#303641' : '#EAECF0')
        this.row('开源许可', 'MPL-2.0 / Apache-2.0')
      }.width('100%').padding({ left: 16, right: 16, top: 4, bottom: 4 })
        .borderRadius(18).backgroundColor(this.dark ? '#1B1E24' : Color.White)
    }.width('100%')
  }

  @Builder
  private sectionHeader(title: string) {
    Text(title).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
      .fontColor(this.dark ? '#A6ADBB' : '#667085').padding({ top: 12, bottom: 10 })
  }

  @Builder
  private row(label: string, value: string) {
    Row() {
      Text(label).fontSize(15).fontColor(this.dark ? '#F3F4F6' : '#172033')
      Blank()
      Text(value).fontSize(13).fontColor(this.dark ? '#A6ADBB' : '#667085')
        .textAlign(TextAlign.End).maxLines(1)
    }.width('100%').height(46)
  }

  @Builder
  private updateButton(label: string, value: number) {
    Button(label).layoutWeight(1).height(42).fontSize(13)
      .fontColor(this.autoUpdateHours === value ? Color.White : (this.dark ? '#D0D5DD' : '#475467'))
      .backgroundColor(this.autoUpdateHours === value ? '#315CFF' : (this.dark ? '#252A33' : '#F2F4F7'))
      .onClick(() => this.onAutoUpdate(value))
  }

  @Builder
  private countryButton(country: string) {
    Button(country).layoutWeight(1).height(34).fontSize(11)
      .fontColor(this.preferredCountries.includes(country) ? Color.White :
        (this.dark ? '#D0D5DD' : '#475467'))
      .backgroundColor(this.preferredCountries.includes(country) ? '#315CFF' :
        (this.dark ? '#252A33' : '#F2F4F7'))
      .onClick(() => this.onCountry(country))
  }
}
