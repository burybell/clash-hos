import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { TunnelState } from '../core/CoreTypes';
import { NativeCoreBridge } from '../core/NativeCoreBridge';
import { runtimeStateService } from '../core/RuntimeStateService';
import { xrayProfileService } from '../core/XrayProfileService';
import { subscriptionService } from '../subscription/SubscriptionService';
import { appPreferencesService, RoutingMode } from '../core/AppPreferencesService';

const DOMAIN: number = 0xC105;
const TAG: string = 'ClashVpnExtension';
const APP_BUNDLE: string = 'io.github.clashhos';
const RECOVERY_DEBOUNCE_MS: number = 2000;
const RECOVERY_WINDOW_MS: number = 2 * 60 * 1000;
const MAX_RECOVERY_ATTEMPTS: number = 3;

interface UnderlyingNetwork {
  netId: number;
  bearer: connection.NetBearType;
}

export default class ClashVpnExtensionAbility extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private tunFd: number = -1;
  private starting: boolean = false;
  private statsTimer: number = -1;
  private lastDiagnosticErrors: number = 0;
  private networkWatchers: connection.NetConnection[] = [];
  private knownUnderlyingNets: UnderlyingNetwork[] = [];
  private underlyingSignature: string = '';
  private recoveryTimer: number = -1;
  private recoveryAttempts: number[] = [];
  private recoveryInProgress: boolean = false;
  private recoveryArmedAt: number = Number.MAX_SAFE_INTEGER;
  private defaultNetworkId: number = 0;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'VPN extension created: %{public}s', want.abilityName ?? 'unknown');
    this.connection = vpnExtension.createVpnConnection(this.context);
    this.registerNetworkWatchers();
    this.setupWhenCoreIsReady();
  }

  onRequest(_want: Want, _startId: number): void {
    hilog.info(DOMAIN, TAG, 'VPN extension requested');
    if (this.tunFd < 0) {
      this.setupWhenCoreIsReady();
    }
  }

  onDestroy(): void {
    this.unregisterNetworkWatchers();
    this.cancelRecoveryTimer();
    this.destroyTunnel();
    runtimeStateService.write(this.context.filesDir, {
      state: TunnelState.DISCONNECTED,
      message: 'VPN 扩展已停止'
    });
  }

  private async setupWhenCoreIsReady(): Promise<void> {
    if (!NativeCoreBridge.isAvailable()) {
      hilog.warn(DOMAIN, TAG, 'Native core unavailable; refusing to create a default-route VPN');
      this.writeFailedState('原生内核加载失败');
      return;
    }
    if (!this.connection || this.tunFd >= 0 || this.starting) {
      return;
    }
    this.starting = true;

    const profilePath: string = `${this.context.filesDir}/profiles/active.yaml`;
    let profile: string;
    try {
      profile = fileIo.readTextSync(profilePath);
    } catch (_error) {
      this.writeFailedState('请先导入有效订阅配置');
      this.starting = false;
      return;
    }
    if (profile.trim().length === 0) {
      this.writeFailedState('订阅配置为空，请重新导入');
      this.starting = false;
      return;
    }

    const config: vpnExtension.VpnConfig = {
      addresses: [
        {
          address: {
            address: '198.18.0.1',
            family: 1
          },
          prefixLength: 30
        }
      ],
      routes: [
        {
          interface: '',
          destination: {
            address: {
              address: '0.0.0.0',
              family: 1
            },
            prefixLength: 0
          },
          gateway: {
            address: '',
            family: 1
          },
          hasGateway: false,
          isDefaultRoute: true
        }
      ],
      dnsAddresses: ['198.18.0.2'],
      mtu: 1500,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      trustedApplications: [],
      blockedApplications: [APP_BUNDLE]
    };

    try {
      await this.connection.protectProcessNet();
      this.tunFd = await this.connection.create(config);
      hilog.info(DOMAIN, TAG, 'TUN created, fd=%{public}d', this.tunFd);
      const selectedProxy: string = subscriptionService.getSelectedProxy(this.context.filesDir);
      const routingMode: RoutingMode = appPreferencesService.getRoutingMode(this.context.filesDir);
      const runtimeConfig: string = xrayProfileService.shouldTranslate(profile) ?
        xrayProfileService.buildConfig(profile, selectedProxy, routingMode) :
        this.buildClashRuntimeConfig(profile, routingMode);
      const coreStatus = NativeCoreBridge.start(runtimeConfig, this.context.filesDir, this.tunFd);
      if (!coreStatus.running) {
        this.writeFailedState(coreStatus.message);
        await this.destroyTunnel();
        return;
      }
      runtimeStateService.write(this.context.filesDir, {
        state: TunnelState.CONNECTED,
        message: routingMode === 'direct' ? '直连模式正在运行' :
          (routingMode === 'global' ? '全局代理正在运行' : '规则代理正在运行')
      });
      this.startStatsReporter();
      this.recoveryArmedAt = Date.now() + 3000;
      this.starting = false;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'TUN creation failed (%{public}d): %{public}s',
        businessError.code, businessError.message);
      await this.destroyTunnel();
      this.writeFailedState(`VPN 创建失败（${businessError.code}）`);
    }
  }

  private buildClashRuntimeConfig(profile: string, routingMode: RoutingMode): string {
    const withoutController: string = profile
      .replace(/^\s*external-controller\s*:.*$/gm, '')
      .replace(/^\s*secret\s*:.*$/gm, '')
      .replace(/^\s*mode\s*:.*$/gm, '');
    return `external-controller: 127.0.0.1:9090\nsecret: \"\"\nmode: ${routingMode}\n${withoutController}`;
  }

  private async destroyTunnel(): Promise<void> {
    this.stopStatsReporter();
    NativeCoreBridge.stop();
    if (!this.connection) {
      return;
    }
    try {
      await this.connection.destroy();
      hilog.info(DOMAIN, TAG, 'VPN tunnel destroyed');
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'VPN destroy failed (%{public}d): %{public}s',
        businessError.code, businessError.message);
    } finally {
      this.tunFd = -1;
      this.starting = false;
      this.connection = undefined;
    }
  }

  private startStatsReporter(): void {
    this.stopStatsReporter();
    const report = (): void => {
      this.checkDefaultNetwork();
      if (this.tunFd >= 0 && !NativeCoreBridge.getStatus().running) {
        this.scheduleRecovery('代理内核意外退出');
        return;
      }
      const stats = NativeCoreBridge.getTrafficStats();
      runtimeStateService.writeTraffic(this.context.filesDir, stats);
      const errors: number = (stats.droppedPackets ?? 0) + (stats.tcpOpenErrors ?? 0) +
        (stats.udpOpenErrors ?? 0) + (stats.udpQuicBlockedPackets ?? 0) +
        (stats.udpVisionRejections ?? 0);
      if (errors > this.lastDiagnosticErrors) {
        hilog.warn(DOMAIN, TAG,
          'TUN diagnostics: in=%{public}d out=%{public}d drop=%{public}d tcpErr=%{public}d udpErr=%{public}d quic=%{public}d vision=%{public}d',
          stats.inboundPackets ?? 0, stats.outboundPackets ?? 0, stats.droppedPackets ?? 0,
          stats.tcpOpenErrors ?? 0, stats.udpOpenErrors ?? 0, stats.udpQuicBlockedPackets ?? 0,
          stats.udpVisionRejections ?? 0);
        this.lastDiagnosticErrors = errors;
      }
    };
    report();
    this.statsTimer = setInterval(report, 1000);
  }

  private checkDefaultNetwork(): void {
    try {
      const nextId: number = connection.getDefaultNetSync().netId;
      if (nextId <= 0) return;
      const changed: boolean = this.defaultNetworkId > 0 && this.defaultNetworkId !== nextId;
      this.defaultNetworkId = nextId;
      if (changed) this.scheduleRecovery('默认网络出口已变化');
    } catch (_error) {
    }
  }

  private stopStatsReporter(): void {
    if (this.statsTimer >= 0) {
      clearInterval(this.statsTimer);
      this.statsTimer = -1;
    }
    this.lastDiagnosticErrors = 0;
  }

  private registerNetworkWatchers(): void {
    const bearerTypes: connection.NetBearType[] = [
      connection.NetBearType.BEARER_CELLULAR,
      connection.NetBearType.BEARER_WIFI,
      connection.NetBearType.BEARER_ETHERNET
    ];
    bearerTypes.forEach((bearer: connection.NetBearType) => {
      const watcher: connection.NetConnection = connection.createNetConnection({
        netCapabilities: {
          bearerTypes: [bearer],
          networkCap: [connection.NetCap.NET_CAPABILITY_INTERNET]
        }
      }, 5000);
      watcher.on('netAvailable', (handle: connection.NetHandle): void => {
        this.recordUnderlyingNetwork(handle, bearer);
      });
      watcher.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo): void => {
        this.recordUnderlyingNetwork(info.netHandle, bearer);
      });
      watcher.on('netLost', (handle: connection.NetHandle): void => {
        const previousLength: number = this.knownUnderlyingNets.length;
        this.knownUnderlyingNets = this.knownUnderlyingNets.filter(
          (item: UnderlyingNetwork) => item.netId !== handle.netId || item.bearer !== bearer);
        if (previousLength !== this.knownUnderlyingNets.length) {
          this.handleUnderlyingTopologyChange('检测到底层网络切换');
        }
      });
      watcher.register((error?: BusinessError): void => {
        if (error) {
          hilog.warn(DOMAIN, TAG, 'Network watcher registration failed: %{public}s', error.message);
        }
      });
      this.networkWatchers.push(watcher);
    });
  }

  private recordUnderlyingNetwork(handle: connection.NetHandle, bearer: connection.NetBearType): void {
    const existing: UnderlyingNetwork | undefined = this.knownUnderlyingNets.find(
      (item: UnderlyingNetwork) => item.netId === handle.netId && item.bearer === bearer);
    if (existing && existing.bearer === bearer) return;
    this.knownUnderlyingNets = this.knownUnderlyingNets.filter(
      (item: UnderlyingNetwork) => item.netId !== handle.netId || item.bearer !== bearer);
    this.knownUnderlyingNets.push({ netId: handle.netId, bearer });
    this.handleUnderlyingTopologyChange('检测到底层网络可用');
  }

  private unregisterNetworkWatchers(): void {
    this.networkWatchers.forEach((watcher: connection.NetConnection) => {
      try {
        watcher.unregister((_error?: BusinessError): void => {});
      } catch (_error) {
      }
    });
    this.networkWatchers = [];
    this.knownUnderlyingNets = [];
    this.underlyingSignature = '';
  }

  private handleUnderlyingTopologyChange(reason: string): void {
    const priorities: connection.NetBearType[] = [
      connection.NetBearType.BEARER_ETHERNET,
      connection.NetBearType.BEARER_WIFI,
      connection.NetBearType.BEARER_CELLULAR
    ];
    let preferred: UnderlyingNetwork | undefined;
    for (let index: number = 0; index < priorities.length && !preferred; index += 1) {
      preferred = this.knownUnderlyingNets.find(
        (item: UnderlyingNetwork) => item.bearer === priorities[index]);
    }
    const nextSignature: string = preferred ? `${preferred.bearer}:${preferred.netId}` : 'offline';
    const changed: boolean = this.underlyingSignature.length > 0 &&
      this.underlyingSignature !== nextSignature;
    this.underlyingSignature = nextSignature;
    if (changed) this.scheduleRecovery(reason);
  }

  private scheduleRecovery(reason: string): void {
    if (this.tunFd < 0 || this.starting || this.recoveryInProgress || Date.now() < this.recoveryArmedAt) {
      return;
    }
    this.cancelRecoveryTimer();
    this.recoveryTimer = setTimeout((): void => {
      this.recoveryTimer = -1;
      this.recoverTunnel(reason);
    }, RECOVERY_DEBOUNCE_MS);
  }

  private cancelRecoveryTimer(): void {
    if (this.recoveryTimer >= 0) {
      clearTimeout(this.recoveryTimer);
      this.recoveryTimer = -1;
    }
  }

  private async recoverTunnel(reason: string): Promise<void> {
    if (this.recoveryInProgress || (this.tunFd < 0 && this.recoveryAttempts.length === 0)) return;
    const now: number = Date.now();
    this.recoveryAttempts = this.recoveryAttempts.filter(
      (startedAt: number) => now - startedAt <= RECOVERY_WINDOW_MS);
    if (this.recoveryAttempts.length >= MAX_RECOVERY_ATTEMPTS) {
      await this.destroyTunnel();
      this.writeFailedState('网络恢复连续失败 3 次，连接已安全关闭，请手动重试');
      return;
    }
    this.recoveryAttempts.push(now);
    this.recoveryInProgress = true;
    this.recoveryArmedAt = Number.MAX_SAFE_INTEGER;
    runtimeStateService.write(this.context.filesDir, {
      state: TunnelState.STARTING,
      message: `${reason}，正在恢复连接（${this.recoveryAttempts.length}/${MAX_RECOVERY_ATTEMPTS}）`
    });
    hilog.info(DOMAIN, TAG, 'Recovering VPN after network change, attempt=%{public}d',
      this.recoveryAttempts.length);
    await this.destroyTunnel();
    await new Promise<void>((resolve: () => void) => setTimeout(resolve, 400));
    this.connection = vpnExtension.createVpnConnection(this.context);
    this.recoveryInProgress = false;
    await this.setupWhenCoreIsReady();
    if (this.tunFd < 0) {
      if (this.recoveryAttempts.length >= MAX_RECOVERY_ATTEMPTS) {
        this.writeFailedState('自动恢复连续失败 3 次，连接已安全关闭，请手动重试');
      } else {
        runtimeStateService.write(this.context.filesDir, {
          state: TunnelState.STARTING,
          message: `恢复未成功，准备重试（${this.recoveryAttempts.length + 1}/${MAX_RECOVERY_ATTEMPTS}）`
        });
        this.recoveryTimer = setTimeout((): void => {
          this.recoveryTimer = -1;
          this.recoverTunnel(reason);
        }, 1000);
      }
    }
  }

  private writeFailedState(message: string): void {
    runtimeStateService.write(this.context.filesDir, {
      state: TunnelState.FAILED,
      message: message
    });
  }
}
