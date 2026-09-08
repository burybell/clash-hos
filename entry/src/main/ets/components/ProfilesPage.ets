import { SubscriptionInfo } from '../subscription/SubscriptionService';

@CustomDialog
struct AddProfileDialog {
  controller: CustomDialogController;
  @Prop dark: boolean;
  @Prop showScanner: boolean;
  @State private url: string = '';
  onScan: () => Promise<string> = async () => '';
  onAdd: (url: string) => void = (_url: string) => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 5 }) {
        Text('添加配置').fontSize(21).fontWeight(FontWeight.Bold)
          .fontColor(this.dark ? '#F3F4F6' : '#172033')
        Text('粘贴订阅链接，名称会从订阅信息中自动获取。')
          .fontSize(13).fontColor(this.dark ? '#A6ADBB' : '#667085')
      }.width('100%').alignItems(HorizontalAlign.Start)
      TextInput({ placeholder: 'HTTPS 订阅链接', text: this.url })
        .height(50).width('100%').fontColor(this.dark ? '#F3F4F6' : '#172033')
        .placeholderColor(this.dark ? '#7F8794' : '#98A2B3')
        .backgroundColor(this.dark ? '#252A33' : '#F2F4F7')
        .onChange((value: string) => this.url = value)
      if (this.showScanner) {
        Button('扫描二维码').width('100%').height(44).fontSize(14)
          .fontColor(this.dark ? '#8FA5FF' : '#315CFF')
          .backgroundColor(this.dark ? '#1E2B57' : '#EEF2FF')
          .onClick(async () => this.url = await this.onScan())
      }
      Row({ space: 10 }) {
        Button('取消').layoutWeight(1).height(46).fontSize(14)
          .fontColor(this.dark ? '#D0D5DD' : '#475467')
          .backgroundColor(this.dark ? '#252A33' : '#EAECF0')
          .onClick(() => this.controller.close())
        Button('导入').layoutWeight(1).height(46).fontSize(14)
          .enabled(this.url.trim().length > 0).backgroundColor('#315CFF')
          .onClick(() => {
            this.onAdd(this.url.trim());
            this.url = '';
            this.controller.close();
          })
      }.width('100%')
      Text('链接仅保存在应用私有目录，界面与诊断信息会隐藏敏感参数。')
        .fontSize(11).fontColor(this.dark ? '#7F8794' : '#98A2B3')
    }.width('92%').constraintSize({ maxWidth: 520 }).padding(22).borderRadius(24)
      .backgroundColor(this.dark ? '#1B1E24' : Color.White)
  }
}

@Component
export struct ProfilesPage {
  @Prop subscriptions: SubscriptionInfo[];
  @Prop importing: boolean;
  @Prop updatingId: string;
  @Prop showScanner: boolean;
  @Prop dark: boolean;
  onScan: () => Promise<string> = async () => '';
  onAdd: (url: string) => void = (_url: string) => {};
  onUpdate: (id: string) => void = (_id: string) => {};
  onActivate: (id: string) => void = (_id: string) => {};
  onDelete: (id: string) => void = (_id: string) => {};

  private addDialog: CustomDialogController = new CustomDialogController({
    builder: AddProfileDialog({ dark: this.dark, showScanner: this.showScanner,
      onScan: () => this.onScan(), onAdd: (url: string) => this.onAdd(url) }),
    autoCancel: true,
    customStyle: true,
    alignment: this.showScanner ? DialogAlignment.Bottom : DialogAlignment.Center
  });

  aboutToDisappear(): void {
    this.addDialog.close();
  }

  private updatedAt(value: number): string {
    return value > 0 ? new Date(value).toLocaleString() : '尚未更新';
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text(`${this.subscriptions.length} 份订阅配置`).fontSize(12)
          .fontColor(this.dark ? '#A6ADBB' : '#667085')
        Blank()
        Button('添加配置').height(34).fontSize(11).fontColor(Color.White)
          .backgroundColor('#315CFF').onClick(() => this.addDialog.open())
      }.width('100%')

      if (this.subscriptions.length === 0) {
        Column({ space: 12 }) {
          Text('还没有配置').fontSize(18).fontWeight(FontWeight.Medium)
            .fontColor(this.dark ? '#F3F4F6' : '#172033')
          Text('添加订阅链接后即可选择节点并建立连接。').fontSize(13)
            .fontColor(this.dark ? '#A6ADBB' : '#667085')
          Button('添加第一份配置').height(44).backgroundColor('#315CFF')
            .onClick(() => this.addDialog.open())
        }.width('100%').padding(28).borderRadius(20)
          .backgroundColor(this.dark ? '#1B1E24' : Color.White)
      }

      ForEach(this.subscriptions, (item: SubscriptionInfo) => {
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Column() {
              Text(item.active ? '✓' : '').fontSize(13).fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
            }.width(28).height(28).justifyContent(FlexAlign.Center).borderRadius(14)
              .backgroundColor(item.active ? '#315CFF' : (this.dark ? '#343A46' : '#EAECF0'))
            Row({ space: 6 }) {
              Text(item.name).fontSize(15).fontWeight(FontWeight.Medium)
                .fontColor(this.dark ? '#F3F4F6' : '#172033')
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              if (item.active) {
                Text('正在使用').fontSize(10).fontColor(this.dark ? '#8FA5FF' : '#315CFF')
                  .padding({ left: 7, right: 7, top: 3, bottom: 3 }).borderRadius(10)
                  .backgroundColor(this.dark ? '#1E2B57' : '#E9EEFF')
              }
            }.layoutWeight(1)
            Text(`${item.proxyNames.length} 节点`).fontSize(12)
              .fontColor(this.dark ? '#8FA5FF' : '#315CFF')
          }.width('100%').onClick(() => {
            if (!item.active) this.onActivate(item.id);
          })

          Row() {
            Text(`更新于 ${this.updatedAt(item.updatedAt)}`).fontSize(12)
              .fontColor(this.dark ? '#7F8794' : '#98A2B3')
            Blank()
            Text(this.formatSize(item.byteLength)).fontSize(12)
              .fontColor(this.dark ? '#7F8794' : '#98A2B3')
          }.width('100%')
          Divider().color(this.dark ? '#303641' : '#EAECF0')
          Row() {
            Button(this.updatingId === item.id ? '更新中…' : '更新').layoutWeight(1).height(32).fontSize(11)
              .enabled(this.updatingId.length === 0 && item.url.length > 0)
              .fontColor(this.dark ? '#D0D5DD' : '#475467')
              .backgroundColor(Color.Transparent).onClick(() => this.onUpdate(item.id))
            Button('删除').layoutWeight(1).height(32).fontSize(11)
              .fontColor(this.dark ? '#FF8A80' : '#C4320A')
              .backgroundColor(Color.Transparent).onClick(() => this.onDelete(item.id))
          }.width('100%')
        }.alignItems(HorizontalAlign.Start).width('100%').padding(14).borderRadius(16)
          .backgroundColor(item.active ? (this.dark ? '#202634' : '#E1E8F8') :
            (this.dark ? '#1B1E24' : Color.White))
      }, (item: SubscriptionInfo) => `${item.id}-${item.active}-${item.name}-${item.updatedAt}`)
    }.width('100%')
  }

  private formatSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    return `${(bytes / 1024).toFixed(1)} KB`;
  }
}
