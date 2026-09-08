@Component
export struct ProxyPage {
  @Prop proxyNames: string[];
  @Prop selectedProxy: string;
  @Prop delayLabels: string[];
  @Prop testing: boolean;
  @Prop dark: boolean;
  @State private selectedCountry: string = '全部';
  @State private hideUnavailable: boolean = false;
  @State private sortByDelay: boolean = false;
  onTestAll: () => void = () => {};
  onTestOne: (name: string, index: number) => void = (_name: string, _index: number) => {};
  onSelect: (name: string) => void = (_name: string) => {};
  onOpenProfiles: () => void = () => {};

  private delay(name: string): string {
    const index: number = this.proxyNames.indexOf(name);
    return index >= 0 && index < this.delayLabels.length ? this.delayLabels[index] : '待测速';
  }

  private delayValue(name: string): number {
    const label: string = this.delay(name);
    return label.endsWith(' ms') ? Number(label.replace(' ms', '')) : 999999;
  }

  private delayColor(name: string): string {
    const label: string = this.delay(name);
    if (label === '不可用') return this.dark ? '#FF8A80' : '#C4320A';
    if (!label.endsWith(' ms')) return this.dark ? '#8FA5FF' : '#315CFF';
    const value: number = this.delayValue(name);
    if (value <= 300) return this.dark ? '#45C997' : '#087A55';
    if (value <= 600) return this.dark ? '#F5B942' : '#B54708';
    return this.dark ? '#FF8A80' : '#C4320A';
  }

  private delayBackground(name: string): string {
    const label: string = this.delay(name);
    if (label === '不可用') return this.dark ? '#40221D' : '#FFF1ED';
    if (!label.endsWith(' ms')) return this.dark ? '#1E2B57' : '#EEF2FF';
    const value: number = this.delayValue(name);
    if (value <= 300) return this.dark ? '#17372D' : '#E8F7F0';
    if (value <= 600) return this.dark ? '#3D321B' : '#FFF4E5';
    return this.dark ? '#40221D' : '#FFF1ED';
  }

  private matchesCountry(name: string, country: string): boolean {
    if (country === '全部') return true;
    const upper: string = name.toUpperCase();
    if (country === '香港') return name.includes('香港') || name.includes('🇭🇰') ||
      upper.includes('[HK]') || upper.includes('HONGKONG') || upper.includes('HONG KONG');
    if (country === '台湾') return name.includes('台湾') || name.includes('台灣') || name.includes('🇹🇼') ||
      upper.includes('[TW]') || upper.includes('TAIWAN');
    if (country === '日本') return name.includes('日本') || name.includes('东京') || name.includes('大阪') ||
      name.includes('🇯🇵') || upper.includes('[JP]') || upper.includes('JAPAN') || upper.includes('TOKYO');
    if (country === '新加坡') return name.includes('新加坡') || name.includes('狮城') || name.includes('🇸🇬') ||
      upper.includes('[SG]') || upper.includes('SINGAPORE');
    if (country === '美国') return name.includes('美国') || name.includes('洛杉矶') || name.includes('🇺🇸') ||
      upper.includes('[US]') || upper.includes('[USA]') || upper.includes('UNITED STATES') ||
      upper.includes('LOS ANGELES') || upper.includes('SAN JOSE');
    if (country === '韩国') return name.includes('韩国') || name.includes('韓國') || name.includes('首尔') ||
      name.includes('🇰🇷') || upper.includes('[KR]') || upper.includes('KOREA') || upper.includes('SEOUL');
    return !['香港', '台湾', '日本', '新加坡', '美国', '韩国'].some(
      (item: string) => this.matchesCountry(name, item));
  }

  private visibleNames(): string[] {
    const names: string[] = this.proxyNames.filter((name: string) =>
      this.matchesCountry(name, this.selectedCountry) &&
      (!this.hideUnavailable || this.delay(name) !== '不可用'));
    if (!this.sortByDelay) return names;
    return names.sort((left: string, right: string) => {
      const difference: number = this.delayValue(left) - this.delayValue(right);
      return difference === 0 ? this.proxyNames.indexOf(left) - this.proxyNames.indexOf(right) : difference;
    });
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`${this.visibleNames().length}/${this.proxyNames.length} 个节点`).fontSize(12)
          .fontColor(this.dark ? '#A6ADBB' : '#667085')
        Blank()
        this.toolButton($r('app.media.node_hide'), this.hideUnavailable,
          this.hideUnavailable ? '显示不可用节点' : '隐藏不可用节点', () => {
            this.hideUnavailable = !this.hideUnavailable;
          })
        this.toolButton($r('app.media.node_sort'), this.sortByDelay,
          this.sortByDelay ? '恢复默认排序' : '按延迟排序', () => {
            this.sortByDelay = !this.sortByDelay;
          })
        Button() {
          if (this.testing) {
            LoadingProgress().width(18).height(18).color(this.dark ? '#8FA5FF' : '#315CFF')
          } else {
            Image($r('app.media.node_speed')).width(19).height(19)
              .fillColor(this.dark ? '#D0D5DD' : '#475467')
          }
        }.width(36).height(36).borderRadius(18)
          .backgroundColor(this.dark ? '#252A33' : Color.White)
          .enabled(!this.testing && this.proxyNames.length > 0)
          .accessibilityText(this.testing ? '正在测速' : '全部测速')
          .onClick(() => this.onTestAll())
      }.width('100%')

      Scroll() {
        Row({ space: 7 }) {
          ForEach(['全部', '香港', '台湾', '日本', '新加坡', '美国', '韩国', '其他'],
            (country: string) => {
              Button(country).height(32).fontSize(11)
                .fontColor(this.selectedCountry === country ? Color.White :
                  (this.dark ? '#D0D5DD' : '#475467'))
                .backgroundColor(this.selectedCountry === country ? '#315CFF' :
                  (this.dark ? '#252A33' : Color.White))
                .onClick(() => this.selectedCountry = country)
            })
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)

      if (this.proxyNames.length === 0) {
        Column({ space: 12 }) {
          Text('还没有可用节点').fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F3F4F6' : '#172033')
          Text('先导入一份兼容配置，节点会自动显示在这里。').fontSize(13)
            .fontColor(this.dark ? '#A6ADBB' : '#667085')
          Button('添加配置').backgroundColor('#315CFF').onClick(() => this.onOpenProfiles())
        }.width('100%').padding(32).borderRadius(20)
          .backgroundColor(this.dark ? '#1B1E24' : Color.White)
      } else if (this.visibleNames().length === 0) {
        Text('当前筛选条件下没有节点').width('100%').textAlign(TextAlign.Center).fontSize(13)
          .fontColor(this.dark ? '#A6ADBB' : '#667085').padding({ top: 40, bottom: 40 })
      } else {
        ForEach(this.visibleNames(), (name: string) => {
          Row({ space: 10 }) {
            Column() {
              Text(name === this.selectedProxy ? '✓' : '').fontSize(14)
                .fontColor(name === this.selectedProxy ? Color.White : (this.dark ? '#A6ADBB' : '#667085'))
            }.width(26).height(26).justifyContent(FlexAlign.Center).borderRadius(13)
              .backgroundColor(name === this.selectedProxy ? '#315CFF' : (this.dark ? '#252A33' : '#F2F4F7'))
            Column({ space: 2 }) {
              Text(name).fontSize(12).fontWeight(FontWeight.Medium)
                .fontColor(this.dark ? '#F3F4F6' : '#172033')
                .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(name === this.selectedProxy ? '当前使用' : '点击切换').fontSize(11)
                .fontColor(this.dark ? '#7F8794' : '#98A2B3')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1).onClick(() => this.onSelect(name))
            Button(this.delay(name)).height(30).fontSize(10).fontColor(this.delayColor(name))
              .backgroundColor(this.delayBackground(name))
              .onClick(() => this.onTestOne(name, this.proxyNames.indexOf(name)))
          }.width('100%').padding({ left: 11, right: 11, top: 7, bottom: 7 }).borderRadius(14)
            .backgroundColor(name === this.selectedProxy ? (this.dark ? '#1B2540' : '#F3F5FF') :
              (this.dark ? '#1B1E24' : Color.White))
        }, (name: string) => `${name}-${name === this.selectedProxy}-${this.delay(name)}`)
      }
    }.width('100%')
  }

  @Builder
  private toolButton(icon: Resource, active: boolean, label: string, action: () => void) {
    Button() {
      Image(icon).width(18).height(18)
        .fillColor(active ? (this.dark ? '#8FA5FF' : '#315CFF') :
          (this.dark ? '#D0D5DD' : '#475467'))
    }.width(36).height(36).borderRadius(18)
      .backgroundColor(active ? (this.dark ? '#1E2B57' : '#E9EEFF') :
        (this.dark ? '#252A33' : Color.White))
      .accessibilityText(label).onClick(action)
  }
}
