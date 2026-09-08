import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { CoreStatus, TunnelState } from './CoreTypes';
import { NativeCoreBridge } from './NativeCoreBridge';
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
      if (stored.state === TunnelState.CONNECTED && !NativeCoreBridge.getStatus().running) {
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
    if (!NativeCoreBridge.isAvailable()) {
      this.status = {
        state: TunnelState.FAILED,
        message: '原生内核尚未就绪，未创建 VPN 连接。'
      };
      return this.status;
    }

    this.status = {
      state: TunnelState.STARTING,
      message: '正在请求 VPN 授权'
    };

    try {
      runtimeStateService.clear(filesDir);
      await vpnExtension.startVpnExtensionAbility(VPN_WANT);
      this.status = await this.waitForRuntime(filesDir);
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

  private async waitForRuntime(filesDir: string): Promise<CoreStatus> {
    for (let attempt: number = 0; attempt < 30; attempt++) {
      const runtimeStatus: CoreStatus | undefined = runtimeStateService.read(filesDir);
      if (runtimeStatus) {
        return runtimeStatus;
      }
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, 100);
      });
    }
    return {
      state: TunnelState.FAILED,
      message: 'VPN 扩展启动超时，请重试或检查系统授权'
    };
  }
}

export const coreService: CoreService = new CoreService();
