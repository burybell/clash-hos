import { common } from '@kit.AbilityKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { HomePage } from '../components/HomePage';
import { ProfilesPage } from '../components/ProfilesPage';
import { ProxyPage } from '../components/ProxyPage';
import { SettingsPage } from '../components/SettingsPage';
import { appPreferencesService, RoutingMode } from '../core/AppPreferencesService';
import { coreControllerService, NodeDelayResult } from '../core/CoreControllerService';
import { coreService } from '../core/CoreService';
import { CoreStatus, TrafficStats, TunnelState } from '../core/CoreTypes';
import { NativeCoreBridge } from '../core/NativeCoreBridge';
import { runtimeStateService } from '../core/RuntimeStateService';
import {
  SubscriptionImportResult,
  SubscriptionInfo,
  subscriptionService
} from '../subscription/SubscriptionService';

@Entry
@Component
struct Index {
  @StorageLink('isDarkMode') private dark: boolean = false;
  @State private currentSection: number = 0;
  @State private isWide: boolean = false;
  @State private tunnelState: TunnelState = TunnelState.DISCONNECTED;
  @State private statusMessage: string = '准备就绪';
  @State private busy: boolean = false;
  @State private importing: boolean = false;
  @State private updatingId: string = '';
  @State private subscriptions: SubscriptionInfo[] = [];
  @State private profileName: string = '尚未添加配置';
  @State private proxyNames: string[] = [];
  @State private selectedProxy: string = '自动选择';
  @State private delayLabels: string[] = [];
  @State private testingNodes: boolean = false;
  @State private routingMode: RoutingMode = 'rule';
  @State private uploadRate: string = '0 B/s';
  @State private downloadRate: string = '0 B/s';
  @State private activeConnections: number = 0;
  @State private sessionDuration: string = '00:00';
  @State private autoUpdateHours: number = 24;
  @State private autoSelectNode: boolean = false;
  @State private preferredCountries: string[] = [];
  @State private activeEngine: 'xray' | 'clashrs' = 'xray';
  @State private selectorGroupName: string = '';
  private pollTimer: number = -1;
  private lastStats: TrafficStats = { uploadBytes: 0, downloadBytes: 0, activeConnections: 0 };
  private lastStatsAt: number = 0;
  private metricsRefreshing: boolean = false;
  private pageScroller: Scroller = new Scroller();

  private navigate(section: number): void {
    this.currentSection = section;
    setTimeout((): void => {
      this.pageScroller.scrollEdge(Edge.Top);
    }, 0);
  }

  aboutToAppear(): void {
    const filesDir: string = this.filesDir();
    const status: CoreStatus = coreService.hydrate(filesDir);
    this.tunnelState = status.state;
    this.routingMode = appPreferencesService.getRoutingMode(filesDir);
    this.statusMessage = status.state === TunnelState.CONNECTED ?
      `${this.modeLabel()}模式正在运行` : status.message;
    this.autoUpdateHours = appPreferencesService.getAutoUpdateHours(filesDir);
    this.autoSelectNode = appPreferencesService.getAutoSelectNode(filesDir);
    this.preferredCountries = appPreferencesService.getPreferredCountries(filesDir);
    this.reloadSubscriptions();
    this.pollTimer = setInterval(() => this.refreshRuntimeMetrics(), 1000);
    this.updateIfDue();
  }

  aboutToDisappear(): void {
    if (this.pollTimer >= 0) {
      clearInterval(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  private filesDir(): string {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return context.filesDir;
  }

  private reloadSubscriptions(): void {
    this.subscriptions = subscriptionService.listSubscriptions(this.filesDir());
    const active: SubscriptionInfo | undefined = this.subscriptions.find(
      (item: SubscriptionInfo) => item.active);
    if (!active) {
      this.profileName = '尚未添加配置';
      this.proxyNames = [];
      this.selectedProxy = '自动选择';
      this.delayLabels = [];
      this.selectorGroupName = '';
      return;
    }
    this.profileName = active.name;
    this.activeEngine = active.engine;
    this.selectorGroupName = active.selectorGroupName;
    this.proxyNames = active.proxyNames;
    const saved: string = subscriptionService.getSelectedProxy(this.filesDir());
    this.selectedProxy = saved.length > 0 && active.proxyNames.includes(saved) ? saved :
      (active.proxyNames.length > 0 ? active.proxyNames[0] : '自动选择');
    this.delayLabels = active.proxyNames.map((_name: string) => '待测速');
  }

  private async toggleConnection(): Promise<void> {
    if (this.busy) return;
    if (this.proxyNames.length === 0 && this.tunnelState !== TunnelState.CONNECTED) {
      this.navigate(2);
      this.statusMessage = '请先添加一份有效配置';
      return;
    }
    this.busy = true;
    if (this.tunnelState === TunnelState.CONNECTED) {
      this.tunnelState = TunnelState.STOPPING;
      this.statusMessage = '正在停止连接';
      const stopped: CoreStatus = await coreService.disconnect(this.filesDir());
      this.tunnelState = stopped.state;
      this.statusMessage = stopped.message;
    } else {
      this.tunnelState = TunnelState.STARTING;
      this.statusMessage = '正在启动代理内核';
      const started: CoreStatus = await coreService.connect(this.filesDir());
      if (started.state === TunnelState.CONNECTED) {
        this.statusMessage = '正在等待代理内核就绪';
        const ready: boolean = await coreControllerService.waitUntilReady();
        if (this.autoSelectNode) {
          const selected: boolean = ready && await this.autoSelectBestNode();
          this.statusMessage = selected ? `已连接 · 自动选择 ${this.selectedProxy}` :
            '已连接，未找到可用节点';
        } else {
          this.statusMessage = '正在应用节点选择';
          await this.applyClashSelection();
          this.statusMessage = started.message;
        }
      } else {
        this.statusMessage = started.message;
      }
      this.tunnelState = started.state;
    }
    this.resetTrafficBaseline();
    this.busy = false;
  }

  private async autoSelectBestNode(): Promise<boolean> {
    const preferred: string[] = this.proxyNames.filter((name: string) =>
      this.preferredCountries.length === 0 || this.preferredCountries.some(
        (country: string) => this.matchesCountry(name, country)));
    let results: NodeDelayResult[] = await this.testCandidates(preferred,
      '正在测试偏好地区节点');
    let available: NodeDelayResult[] = results.filter((item: NodeDelayResult) => item.available);
    if (available.length === 0) {
      const fallback: string[] = this.proxyNames.filter((name: string) => !preferred.includes(name));
      if (fallback.length > 0) {
        this.statusMessage = `偏好地区不可用，正在测试其他节点 0/${fallback.length}`;
        results = await this.testCandidates(fallback, '正在测试其他节点');
        available = results.filter((item: NodeDelayResult) => item.available);
      }
    }
    if (available.length === 0) return false;
    available.sort((left: NodeDelayResult, right: NodeDelayResult) => left.delay - right.delay);
    const best: NodeDelayResult = available[0];
    this.statusMessage = `正在切换到最佳节点 · ${best.delay} ms`;
    subscriptionService.saveSelectedProxy(this.filesDir(), best.name);
    const changed: boolean = best.name !== this.selectedProxy;
    this.selectedProxy = best.name;
    if (this.activeEngine === 'clashrs') {
      return coreControllerService.selectNode(this.selectorGroupName, best.name);
    }
    if (changed) {
      const restarted: CoreStatus = await coreService.restart(this.filesDir());
      return restarted.state === TunnelState.CONNECTED;
    }
    return true;
  }

  private async testCandidates(names: string[], progressLabel: string): Promise<NodeDelayResult[]> {
    const results: NodeDelayResult[] = [];
    const concurrency: number = 8;
    for (let offset: number = 0; offset < names.length; offset += concurrency) {
      const batchNames: string[] = names.slice(offset, offset + concurrency);
      const tasks: Promise<NodeDelayResult>[] = batchNames.map((name: string) => {
        const index: number = this.proxyNames.indexOf(name);
        return coreControllerService.testNode(name, this.activeEngine === 'xray' ? index : -1);
      });
      const batch: NodeDelayResult[] = await Promise.all(tasks);
      results.push(...batch);
      const labels: string[] = this.delayLabels.slice();
      batch.forEach((result: NodeDelayResult) => {
        const index: number = this.proxyNames.indexOf(result.name);
        if (index >= 0) labels[index] = result.available ? `${result.delay} ms` : '不可用';
      });
      this.delayLabels = labels;
      this.statusMessage = `${progressLabel} ${Math.min(offset + concurrency, names.length)}/${names.length}`;
    }
    return results;
  }

  private matchesCountry(name: string, country: string): boolean {
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
    return name.includes('韩国') || name.includes('韓國') || name.includes('首尔') || name.includes('🇰🇷') ||
      upper.includes('[KR]') || upper.includes('KOREA') || upper.includes('SEOUL');
  }

  private async changeMode(label: string): Promise<void> {
    const mode: RoutingMode = label === '全局' ? 'global' : (label === '直连' ? 'direct' : 'rule');
    if (mode === this.routingMode || this.busy) return;
    this.routingMode = mode;
    appPreferencesService.setRoutingMode(this.filesDir(), mode);
    if (this.tunnelState === TunnelState.CONNECTED) {
      this.busy = true;
      this.tunnelState = TunnelState.STARTING;
      this.statusMessage = `正在切换到${label}模式`;
      const result: CoreStatus = await coreService.restart(this.filesDir());
      this.tunnelState = result.state;
      if (result.state === TunnelState.CONNECTED) {
        await this.applyClashSelection();
      }
      this.statusMessage = result.state === TunnelState.CONNECTED ? `已切换到${label}模式` : result.message;
      this.busy = false;
    } else {
      this.statusMessage = `已切换到${label}模式`;
    }
  }

  private async selectProxy(name: string): Promise<void> {
    if (name === this.selectedProxy || this.busy) return;
    subscriptionService.saveSelectedProxy(this.filesDir(), name);
    this.selectedProxy = name;
    if (this.tunnelState === TunnelState.CONNECTED) {
      this.busy = true;
      this.tunnelState = TunnelState.STARTING;
      this.statusMessage = `正在切换到 ${name}`;
      const result: CoreStatus = await coreService.restart(this.filesDir());
      this.tunnelState = result.state;
      if (result.state === TunnelState.CONNECTED) {
        await this.applyClashSelection();
      }
      this.statusMessage = result.state === TunnelState.CONNECTED ? `已切换到 ${name}` : result.message;
      this.busy = false;
    } else {
      this.statusMessage = `已选择 ${name}`;
    }
  }

  private async applyClashSelection(): Promise<void> {
    if (this.activeEngine !== 'clashrs' || this.selectorGroupName.length === 0 ||
      this.selectedProxy.length === 0) {
      return;
    }
    const selected: boolean = await coreControllerService.selectNode(
      this.selectorGroupName, this.selectedProxy);
    if (!selected) {
      this.statusMessage = `节点 ${this.selectedProxy} 选择失败`;
    }
  }

  private async testAllNodes(): Promise<void> {
    if (this.testingNodes) return;
    const temporaryCore: boolean = this.tunnelState !== TunnelState.CONNECTED;
    this.testingNodes = true;
    if (!await this.prepareLatencyTest()) {
      this.testingNodes = false;
      return;
    }
    this.delayLabels = this.proxyNames.map((_name: string) => '测速中…');
    const results: NodeDelayResult[] = [];
    const concurrency: number = 8;
    for (let offset: number = 0; offset < this.proxyNames.length; offset += concurrency) {
      const names: string[] = this.proxyNames.slice(offset, offset + concurrency);
      const tasks: Promise<NodeDelayResult>[] = names.map((name: string, batchIndex: number) =>
        coreControllerService.testNode(name,
          this.activeEngine === 'xray' ? offset + batchIndex : -1));
      const batch: NodeDelayResult[] = await Promise.all(tasks);
      results.push(...batch);
      const progress: string[] = this.delayLabels.slice();
      batch.forEach((result: NodeDelayResult, batchIndex: number) => {
        progress[offset + batchIndex] = result.available ? `${result.delay} ms` : '不可用';
      });
      this.delayLabels = progress;
    }
    this.delayLabels = results.map((result: NodeDelayResult) =>
      result.available ? `${result.delay} ms` : '不可用');
    const available: number = results.filter((result: NodeDelayResult) => result.available).length;
    this.statusMessage = `测速完成，${available}/${results.length} 个节点可用`;
    if (temporaryCore) await this.stopTemporaryTestCore();
    this.testingNodes = false;
  }

  private async testOneNode(name: string, index: number): Promise<void> {
    if (index < 0 || this.testingNodes) return;
    const temporaryCore: boolean = this.tunnelState !== TunnelState.CONNECTED;
    this.testingNodes = true;
    if (!await this.prepareLatencyTest()) {
      this.testingNodes = false;
      return;
    }
    const labels: string[] = this.delayLabels.slice();
    labels[index] = '测速中…';
    this.delayLabels = labels;
    const result: NodeDelayResult = await coreControllerService.testNode(
      name, this.activeEngine === 'xray' ? index : -1);
    const next: string[] = this.delayLabels.slice();
    next[index] = result.available ? `${result.delay} ms` : '不可用';
    this.delayLabels = next;
    this.statusMessage = result.available ? `${name} · ${result.delay} ms` : `${name} 不可用`;
    if (temporaryCore) await this.stopTemporaryTestCore();
    this.testingNodes = false;
  }

  private async prepareLatencyTest(): Promise<boolean> {
    if (this.tunnelState === TunnelState.CONNECTED) return true;
    this.tunnelState = TunnelState.STARTING;
    this.statusMessage = '正在临时启动测速内核';
    const started: CoreStatus = await coreService.connect(this.filesDir());
    if (started.state !== TunnelState.CONNECTED) {
      this.tunnelState = started.state;
      this.statusMessage = started.message;
      return false;
    }
    this.tunnelState = TunnelState.CONNECTED;
    this.statusMessage = '正在等待测速服务就绪';
    const ready: boolean = await coreControllerService.waitUntilReady();
    if (!ready) {
      await this.stopTemporaryTestCore();
      this.statusMessage = '测速服务启动超时';
    }
    return ready;
  }

  private async stopTemporaryTestCore(): Promise<void> {
    const message: string = this.statusMessage;
    await coreService.disconnect(this.filesDir());
    this.tunnelState = TunnelState.DISCONNECTED;
    this.statusMessage = message;
    this.resetTrafficBaseline();
  }

  private async addSubscription(url: string): Promise<void> {
    if (this.importing) return;
    this.importing = true;
    this.statusMessage = '正在下载并校验配置';
    try {
      const result: SubscriptionImportResult = await subscriptionService.addFromUrl(url, this.filesDir(), '');
      this.reloadSubscriptions();
      this.statusMessage = `配置添加成功，识别到 ${result.proxyNames.length} 个节点`;
    } catch (error) {
      this.statusMessage = `添加失败：${(error as Error).message}`;
    }
    this.importing = false;
  }

  private async updateSubscription(id: string, quiet: boolean = false): Promise<void> {
    if (this.importing || this.updatingId.length > 0) return;
    this.updatingId = id;
    if (!quiet) this.statusMessage = '正在更新配置';
    try {
      const result: SubscriptionImportResult = await subscriptionService.updateSubscription(id, this.filesDir());
      this.reloadSubscriptions();
      this.statusMessage = `配置已更新，识别到 ${result.proxyNames.length} 个节点`;
      if (this.tunnelState === TunnelState.CONNECTED) {
        this.busy = true;
        const status: CoreStatus = await coreService.restart(this.filesDir());
        this.tunnelState = status.state;
        if (status.state === TunnelState.CONNECTED) {
          await this.applyClashSelection();
        }
        this.statusMessage = status.state === TunnelState.CONNECTED ? '配置已更新并重新连接' : status.message;
        this.busy = false;
      }
    } catch (error) {
      this.statusMessage = `更新失败：${(error as Error).message}`;
    }
    this.updatingId = '';
  }

  private async activateSubscription(id: string): Promise<void> {
    try {
      const active: SubscriptionInfo = subscriptionService.activateSubscription(id, this.filesDir());
      this.reloadSubscriptions();
      this.statusMessage = `已启用 ${active.name}`;
      if (this.tunnelState === TunnelState.CONNECTED) {
        this.busy = true;
        const status: CoreStatus = await coreService.restart(this.filesDir());
        this.tunnelState = status.state;
        if (status.state === TunnelState.CONNECTED) {
          await this.applyClashSelection();
        }
        this.statusMessage = status.state === TunnelState.CONNECTED ? `已启用并连接 ${active.name}` : status.message;
        this.busy = false;
      }
    } catch (error) {
      this.statusMessage = `启用失败：${(error as Error).message}`;
    }
  }

  private confirmDelete(id: string): void {
    AlertDialog.show({
      title: '删除配置？',
      message: '配置内容和保存的订阅地址将从此设备移除。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除', fontColor: '#C4320A', action: () => this.deleteSubscription(id) }
    });
  }

  private async deleteSubscription(id: string): Promise<void> {
    const deletingActive: boolean = this.subscriptions.some(
      (item: SubscriptionInfo) => item.id === id && item.active);
    subscriptionService.deleteSubscription(id, this.filesDir());
    this.reloadSubscriptions();
    if (deletingActive && this.tunnelState === TunnelState.CONNECTED) {
      this.busy = true;
      const status: CoreStatus = this.proxyNames.length > 0 ? await coreService.restart(this.filesDir()) :
        await coreService.disconnect(this.filesDir());
      this.tunnelState = status.state;
      this.busy = false;
    }
    this.statusMessage = '配置已删除';
  }

  private async scanSubscriptionUrl(): Promise<string> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableAlbum: true,
        enableMultiMode: false
      });
      const value: string = result.originalValue.trim();
      if (!value.startsWith('https://')) {
        this.statusMessage = '二维码内容不是 HTTPS 订阅链接';
        return '';
      }
      return value;
    } catch (_error) {
      return '';
    }
  }

  private updateAutoHours(hours: number): void {
    this.autoUpdateHours = hours;
    appPreferencesService.setAutoUpdateHours(this.filesDir(), hours);
    this.statusMessage = hours === 0 ? '已关闭订阅自动更新' : `订阅将每 ${hours} 小时检查更新`;
  }

  private updateAutoSelect(enabled: boolean): void {
    this.autoSelectNode = enabled;
    appPreferencesService.setAutoSelectNode(this.filesDir(), enabled);
    this.statusMessage = enabled ? '已开启连接时自动选择最佳节点' : '已关闭自动选择节点';
  }

  private togglePreferredCountry(country: string): void {
    const countries: string[] = this.preferredCountries.includes(country) ?
      this.preferredCountries.filter((item: string) => item !== country) :
      [...this.preferredCountries, country];
    this.preferredCountries = countries;
    appPreferencesService.setPreferredCountries(this.filesDir(), countries);
    this.statusMessage = countries.length > 0 ? `优先地区：${countries.join('、')}` :
      '未指定优先地区，将从全部节点中选择';
  }

  private updateIfDue(): void {
    if (this.autoUpdateHours <= 0) return;
    const active: SubscriptionInfo | undefined = this.subscriptions.find((item: SubscriptionInfo) => item.active);
    if (active && active.url.length > 0 &&
      Date.now() - active.updatedAt >= this.autoUpdateHours * 60 * 60 * 1000) {
      this.updateSubscription(active.id, true);
    }
  }

  private async refreshRuntimeMetrics(): Promise<void> {
    if (this.tunnelState !== TunnelState.CONNECTED) {
      this.uploadRate = '0 B/s';
      this.downloadRate = '0 B/s';
      this.activeConnections = 0;
      this.sessionDuration = '00:00';
      this.resetTrafficBaseline();
      return;
    }
    if (this.metricsRefreshing) return;
    this.metricsRefreshing = true;
    const now: number = Date.now();
    const stats: TrafficStats = this.activeEngine === 'clashrs' ?
      await coreControllerService.getTrafficStats() : NativeCoreBridge.getTrafficStats();
    if (this.activeEngine === 'clashrs') {
      this.uploadRate = this.formatRate(stats.uploadBytes);
      this.downloadRate = this.formatRate(stats.downloadBytes);
    } else if (this.lastStatsAt > 0) {
      const seconds: number = Math.max(0.2, (now - this.lastStatsAt) / 1000);
      this.uploadRate = this.formatRate(Math.max(0, stats.uploadBytes - this.lastStats.uploadBytes) / seconds);
      this.downloadRate = this.formatRate(Math.max(0, stats.downloadBytes - this.lastStats.downloadBytes) / seconds);
    }
    this.activeConnections = stats.activeConnections;
    this.lastStats = stats;
    this.lastStatsAt = now;
    const connectedAt: number = runtimeStateService.getConnectedAt(this.filesDir());
    if (connectedAt > 0) {
      const totalSeconds: number = Math.floor((now - connectedAt) / 1000);
      const minutes: number = Math.floor(totalSeconds / 60);
      const seconds: number = totalSeconds % 60;
      this.sessionDuration = `${minutes < 10 ? '0' : ''}${minutes}:${seconds < 10 ? '0' : ''}${seconds}`;
    }
    this.metricsRefreshing = false;
  }

  private resetTrafficBaseline(): void {
    this.lastStats = { uploadBytes: 0, downloadBytes: 0, activeConnections: 0 };
    this.lastStatsAt = 0;
  }

  private formatRate(bytes: number): string {
    if (bytes < 1024) return `${Math.round(bytes)} B/s`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB/s`;
    return `${(bytes / 1024 / 1024).toFixed(1)} MB/s`;
  }

  private modeLabel(): string {
    return this.routingMode === 'global' ? '全局' : (this.routingMode === 'direct' ? '直连' : '规则');
  }

  private pageTitle(): string {
    if (this.currentSection === 1) return '节点';
    if (this.currentSection === 2) return '配置';
    if (this.currentSection === 3) return '设置';
    return 'Clash HOS';
  }

  build() {
    Row() {
      if (this.isWide) {
        this.sideNavigation()
      }
      Column() {
        Row() {
          Text(this.pageTitle()).fontSize(this.isWide ? 22 : 20).fontWeight(FontWeight.Bold)
            .fontColor(this.dark ? '#F3F4F6' : '#172033')
          Blank()
          Text(this.tunnelState === TunnelState.CONNECTED ? '已连接' : '未连接')
            .fontSize(12).fontColor(this.tunnelState === TunnelState.CONNECTED ?
              (this.dark ? '#45C997' : '#087A55') : (this.dark ? '#A6ADBB' : '#667085'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 }).borderRadius(14)
            .backgroundColor(this.tunnelState === TunnelState.CONNECTED ?
              (this.dark ? '#17372D' : '#E8F7F0') : (this.dark ? '#252A33' : '#EAECF0'))
        }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 8 })

        Scroll(this.pageScroller) {
          Column() {
            if (this.currentSection === 0) {
              HomePage({
                tunnelState: this.tunnelState, statusMessage: this.statusMessage,
                selectedProxy: this.selectedProxy, routingMode: this.modeLabel(),
                uploadRate: this.uploadRate, downloadRate: this.downloadRate,
                sessionDuration: this.sessionDuration, activeConnections: this.activeConnections,
                profileName: this.profileName, nodeCount: this.proxyNames.length, busy: this.busy,
                dark: this.dark,
                onToggle: () => this.toggleConnection(), onMode: (mode: string) => this.changeMode(mode),
                onOpenNodes: () => this.navigate(1), onOpenProfiles: () => this.navigate(2)
              })
            } else if (this.currentSection === 1) {
              ProxyPage({ proxyNames: this.proxyNames, selectedProxy: this.selectedProxy,
                delayLabels: this.delayLabels, testing: this.testingNodes,
                dark: this.dark,
                onTestAll: () => this.testAllNodes(),
                onTestOne: (name: string, index: number) => this.testOneNode(name, index),
                onSelect: (name: string) => this.selectProxy(name),
                onOpenProfiles: () => this.navigate(2) })
            } else if (this.currentSection === 2) {
              ProfilesPage({ subscriptions: this.subscriptions, importing: this.importing,
                updatingId: this.updatingId,
                showScanner: !this.isWide, dark: this.dark,
                onScan: () => this.scanSubscriptionUrl(),
                onAdd: (url: string) => this.addSubscription(url),
                onUpdate: (id: string) => this.updateSubscription(id),
                onActivate: (id: string) => this.activateSubscription(id),
                onDelete: (id: string) => this.confirmDelete(id) })
            } else {
              SettingsPage({ routingMode: this.modeLabel(), autoUpdateHours: this.autoUpdateHours,
                autoSelectNode: this.autoSelectNode, preferredCountries: this.preferredCountries,
                version: '0.9.0', dark: this.dark,
                onAutoUpdate: (hours: number) => this.updateAutoHours(hours),
                onAutoSelect: (enabled: boolean) => this.updateAutoSelect(enabled),
                onCountry: (country: string) => this.togglePreferredCountry(country) })
            }
          }.width('100%').constraintSize({ minHeight: '100%', maxWidth: 920 })
            .alignItems(HorizontalAlign.Start)
            .padding({ left: 18, right: 18, top: 8, bottom: 20 })
        }.layoutWeight(1).width('100%')

        if (!this.isWide) {
          this.bottomNavigation()
        }
      }.layoutWeight(1).height('100%')
    }.width('100%').height('100%').backgroundColor(this.dark ? '#0F1115' : '#F3F6FC')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.isWide = Number(newValue.width) >= 760;
      })
  }

  @Builder
  private sideNavigation() {
    Column({ space: 8 }) {
      Text('Clash HOS').fontSize(20).fontWeight(FontWeight.Bold)
        .fontColor(this.dark ? '#F3F4F6' : '#172033')
        .width('100%').padding({ left: 14, top: 12, bottom: 24 })
      this.sideItem('首页', 0)
      this.sideItem('节点', 1)
      this.sideItem('配置', 2)
      this.sideItem('设置', 3)
      Blank()
      Text('HarmonyOS 原生客户端').fontSize(11)
        .fontColor(this.dark ? '#7F8794' : '#98A2B3').padding(14)
    }.width(220).height('100%').padding(12).backgroundColor(this.dark ? '#1B1E24' : Color.White)
  }

  @Builder
  private sideItem(label: string, section: number) {
    Button(label).width('100%').height(46).fontSize(14)
      .fontColor(this.currentSection === section ? (this.dark ? '#8FA5FF' : '#315CFF') :
        (this.dark ? '#A6ADBB' : '#475467'))
      .backgroundColor(this.currentSection === section ? (this.dark ? '#1E2B57' : '#EEF2FF') : Color.Transparent)
      .onClick(() => this.navigate(section))
  }

  @Builder
  private bottomNavigation() {
    Row() {
      this.bottomItem('首页', $r('app.media.tab_home'), 0)
      this.bottomItem('节点', $r('app.media.tab_nodes'), 1)
      this.bottomItem('配置', $r('app.media.tab_profiles'), 2)
      this.bottomItem('设置', $r('app.media.tab_settings'), 3)
    }.width('100%').height(64).padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .backgroundColor(this.dark ? '#1B1E24' : Color.White)
      .border({ width: { top: 1 }, color: this.dark ? '#303641' : '#EAECF0' })
  }

  @Builder
  private bottomItem(label: string, icon: Resource, section: number) {
    Button() {
      Column({ space: 2 }) {
        Row() {
          Image(icon).width(17).height(17)
            .fillColor(this.currentSection === section ? (this.dark ? '#AFC0FF' : '#315CFF') :
              (this.dark ? '#98A2B3' : '#667085'))
        }.width(64).height(30).justifyContent(FlexAlign.Center).borderRadius(15)
          .backgroundColor(this.currentSection === section ?
            (this.dark ? '#26335E' : '#E9EEFF') : Color.Transparent)
        Text(label).fontSize(10)
          .fontColor(this.currentSection === section ? (this.dark ? '#8FA5FF' : '#315CFF') :
            (this.dark ? '#A6ADBB' : '#667085'))
          .fontWeight(this.currentSection === section ? FontWeight.Medium : FontWeight.Regular)
      }
    }.layoutWeight(1).height(52)
      .backgroundColor(Color.Transparent)
      .onClick(() => this.navigate(section))
  }
}
