import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { CoreStatus, TunnelState } from './CoreTypes';
import { runtimeStateService } from './RuntimeStateService';

const VPN_WANT: Want = {
  deviceId: '',
  bundleName: 'io.github.clashhos',
  abilityName: 'ClashVpnExtensionAbility'
};

export class CoreService {
  private status: CoreStatus = {
    state: TunnelState.DISCONNECTED,
    message: '准备就绪'
  };

  getStatus(): CoreStatus {
    return this.status;
  }

  hydrate(filesDir: string): CoreStatus {
    const stored: CoreStatus | undefined = runtimeStateService.read(filesDir);
    if (stored) {
      if (stored.state === TunnelState.CONNECTED && !runtimeStateService.isHeartbeatFresh(filesDir)) {
        this.status = {
          state: TunnelState.DISCONNECTED,
          message: '上次连接已结束，可以重新连接'
        };
        runtimeStateService.write(filesDir, this.status);
      } else {
        this.status = stored;
      }
    }
    return this.status;
  }

  async connect(filesDir: string): Promise<CoreStatus> {
    this.status = {
      state: TunnelState.STARTING,
      message: '正在请求 VPN 授权'
    };

    try {
      runtimeStateService.clear(filesDir);
      const requestStartedAt: number = Date.now();
      await vpnExtension.startVpnExtensionAbility(VPN_WANT);
      this.status = await this.waitForRuntime(filesDir, requestStartedAt);
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      this.status = {
        state: TunnelState.FAILED,
        message: `VPN 启动失败（${businessError.code}）：${businessError.message}`
      };
    }
    return this.status;
  }

  async disconnect(filesDir: string): Promise<CoreStatus> {
    this.status = {
      state: TunnelState.STOPPING,
      message: '正在停止 VPN 扩展'
    };

    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_WANT);
      this.status = {
        state: TunnelState.DISCONNECTED,
        message: '已断开连接'
      };
      runtimeStateService.write(filesDir, this.status);
    } catch (error) {
      const businessError: BusinessError = error as BusinessError;
      this.status = {
        state: TunnelState.FAILED,
        message: `VPN 停止失败（${businessError.code}）：${businessError.message}`
      };
    }
    return this.status;
  }

  async restart(filesDir: string): Promise<CoreStatus> {
    await this.disconnect(filesDir);
    await new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, 250);
    });
    return this.connect(filesDir);
  }

  private async waitForRuntime(filesDir: string, requestStartedAt: number): Promise<CoreStatus> {
    // The first VPN authorization can remain visible while the user reviews the
    // system dialog. Do not turn that normal interaction into a false timeout.
    for (let attempt: number = 0; attempt < 150; attempt++) {
      const runtimeStatus: CoreStatus | undefined = runtimeStateService.readSince(filesDir, requestStartedAt);
      if (runtimeStatus) {
        return runtimeStatus;
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 100);
      });
    }
    return {
      state: TunnelState.FAILED,
      message: 'VPN 扩展在 15 秒内未就绪，请检查系统授权后重试'
    };
  }
}

export const coreService: CoreService = new CoreService();
