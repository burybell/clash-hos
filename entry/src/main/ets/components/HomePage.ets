import { TunnelState } from '../core/CoreTypes';

@Component
export struct HomePage {
  @Prop tunnelState: TunnelState;
  @Prop statusMessage: string;
  @Prop selectedProxy: string;
  @Prop routingMode: string;
  @Prop uploadRate: string;
  @Prop downloadRate: string;
  @Prop sessionDuration: string;
  @Prop activeConnections: number;
  @Prop connectivityMessage: string;
  @Prop connectivityVerified: boolean;
  @Prop profileName: string;
  @Prop nodeCount: number;
  @Prop busy: boolean;
  @Prop dark: boolean;
  onToggle: () => void = () => {};
  onRecheck: () => void = () => {};
  onMode: (mode: string) => void = (_mode: string) => {};
  onOpenNodes: () => void = () => {};
  onOpenProfiles: () => void = () => {};

  private stateLabel(): string {
    if (this.tunnelState === TunnelState.CONNECTED) {
      return this.connectivityVerified ? '连接安全' : '连接待验证';
    }
    if (this.tunnelState === TunnelState.STARTING) return '正在连接';
    if (this.tunnelState === TunnelState.STOPPING) return '正在断开';
    if (this.tunnelState === TunnelState.FAILED) return '连接异常';
    return '尚未连接';
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 14 }) {
        Column({ space: 5 }) {
          Row() {
            Text(this.stateLabel()).fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor(this.tunnelState === TunnelState.CONNECTED ?
                (this.dark ? '#45C997' : '#087A55') : (this.dark ? '#A6ADBB' : '#667085'))
            Blank()
            if (this.tunnelState === TunnelState.CONNECTED) {
              Text(this.sessionDuration).fontSize(12).fontColor(this.dark ? '#7F8794' : '#98A2B3')
            }
          }.width('100%')
          Text(this.selectedProxy).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F3F4F6' : '#172033')
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => this.onOpenNodes())
        }.alignItems(HorizontalAlign.Start).width('100%')

        Button() {
          if (this.busy) {
            Row({ space: 8 }) {
              LoadingProgress().width(18).height(18).color(Color.White)
              Text(this.statusMessage).fontSize(14).fontColor(Color.White).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          } else {
            Text(this.tunnelState === TunnelState.CONNECTED ? '断开连接' : '开始连接')
              .fontSize(16).fontWeight(FontWeight.Medium).fontColor(Color.White)
          }
        }.width('100%').height(48)
          .enabled(!this.busy)
          .backgroundColor(this.tunnelState === TunnelState.CONNECTED ?
            (this.dark ? '#343A46' : '#172033') : '#315CFF')
          .onClick(() => this.onToggle())

        if (!this.busy && this.tunnelState === TunnelState.FAILED) {
          Text(this.statusMessage).width('100%').fontSize(12)
            .fontColor(this.dark ? '#FF8A80' : '#C4320A').maxLines(2)
        }
        if (!this.busy && this.tunnelState === TunnelState.CONNECTED) {
          Row({ space: 7 }) {
            Circle({ width: 7, height: 7 }).fill(this.connectivityVerified ?
              (this.dark ? '#45C997' : '#087A55') : (this.dark ? '#FFB74D' : '#B54708'))
            Text(this.connectivityMessage).fontSize(12)
              .fontColor(this.connectivityVerified ? (this.dark ? '#A6ADBB' : '#667085') :
                (this.dark ? '#FFB74D' : '#B54708'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (!this.connectivityVerified) {
              Blank()
              Text('重新检测').fontSize(12).fontWeight(FontWeight.Medium)
                .fontColor(this.dark ? '#8FA5FF' : '#315CFF')
            }
          }.width('100%')
            .onClick(() => {
              if (!this.connectivityVerified) this.onRecheck();
            })
        }
      }.width('100%').padding(18).borderRadius(18).backgroundColor(this.dark ? '#1B1E24' : Color.White)

      Row({ space: 10 }) {
        this.metric('下载', this.downloadRate)
        this.metric('上传', this.uploadRate)
        this.metric('连接', `${this.activeConnections}`)
      }.width('100%')

      Column({ space: 12 }) {
        Row() {
          Text('代理模式').fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F3F4F6' : '#172033')
          Blank()
          Text('切换后自动重连').fontSize(12).fontColor(this.dark ? '#7F8794' : '#98A2B3')
        }.width('100%')
        Row({ space: 8 }) {
          this.modeButton('规则')
          this.modeButton('全局')
          this.modeButton('直连')
        }.width('100%')
      }.width('100%').padding(16).borderRadius(18).backgroundColor(this.dark ? '#1B1E24' : Color.White)

      Row({ space: 10 }) {
        Button(`选择节点 · ${this.nodeCount}`).layoutWeight(1).height(42).fontSize(13)
          .fontColor(this.dark ? '#D0D5DD' : '#172033')
          .backgroundColor(this.dark ? '#252A33' : Color.White)
          .onClick(() => this.onOpenNodes())
        Button('管理配置').layoutWeight(1).height(42).fontSize(13)
          .fontColor(this.dark ? '#D0D5DD' : '#172033')
          .backgroundColor(this.dark ? '#252A33' : Color.White)
          .onClick(() => this.onOpenProfiles())
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private metric(label: string, value: string) {
    Column({ space: 6 }) {
      Text(label).fontSize(12).fontColor(this.dark ? '#A6ADBB' : '#667085')
      Text(value).fontSize(16).fontWeight(FontWeight.Medium)
        .fontColor(this.dark ? '#F3F4F6' : '#172033').maxLines(1)
    }.alignItems(HorizontalAlign.Start).layoutWeight(1).padding(12)
      .borderRadius(14).backgroundColor(this.dark ? '#1B1E24' : Color.White)
  }

  @Builder
  private modeButton(mode: string) {
    Button(mode).layoutWeight(1).height(40).fontSize(13)
      .fontColor(this.routingMode === mode ? Color.White : (this.dark ? '#D0D5DD' : '#475467'))
      .backgroundColor(this.routingMode === mode ? '#315CFF' : (this.dark ? '#252A33' : '#F2F4F7'))
      .onClick(() => this.onMode(mode))
  }
}
