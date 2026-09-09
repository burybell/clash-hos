import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { TunnelState } from '../core/CoreTypes';
import { NativeCoreBridge } from '../core/NativeCoreBridge';
import { runtimeStateService } from '../core/RuntimeStateService';
import { xrayProfileService } from '../core/XrayProfileService';
import { subscriptionService } from '../subscription/SubscriptionService';
import { appPreferencesService, RoutingMode } from '../core/AppPreferencesService';

const DOMAIN: number = 0xC105;
const TAG: string = 'ClashVpnExtension';
const APP_BUNDLE: string = 'io.github.clashhos';

export default class ClashVpnExtensionAbility extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private tunFd: number = -1;
  private starting: boolean = false;
  private statsTimer: number = -1;
  private lastDiagnosticErrors: number = 0;

  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, 'VPN extension created: %{public}s', want.abilityName ?? 'unknown');
    this.connection = vpnExtension.createVpnConnection(this.context);
    this.setupWhenCoreIsReady();
  }

  onRequest(_want: Want, _startId: number): void {
    hilog.info(DOMAIN, TAG, 'VPN extension requested');
    if (this.tunFd < 0) {
      this.setupWhenCoreIsReady();
    }
  }

  onDestroy(): void {
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
        this.buildClashRuntimeConfig(profile);
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
      this.starting = false;
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'TUN creation failed (%{public}d): %{public}s',
        businessError.code, businessError.message);
      await this.destroyTunnel();
      this.writeFailedState(`VPN 创建失败（${businessError.code}）`);
    }
  }

  private buildClashRuntimeConfig(profile: string): string {
    const withoutController: string = profile
      .replace(/^\s*external-controller\s*:.*$/gm, '')
      .replace(/^\s*secret\s*:.*$/gm, '');
    return `external-controller: 127.0.0.1:9090\nsecret: \"\"\n${withoutController}`;
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

  private stopStatsReporter(): void {
    if (this.statsTimer >= 0) {
      clearInterval(this.statsTimer);
      this.statsTimer = -1;
    }
    this.lastDiagnosticErrors = 0;
  }

  private writeFailedState(message: string): void {
    runtimeStateService.write(this.context.filesDir, {
      state: TunnelState.FAILED,
      message: message
    });
  }
}
