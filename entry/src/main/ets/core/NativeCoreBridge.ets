import nativeCore from 'libclash_core.so';
import { NativeCoreStatus, TrafficStats } from './CoreTypes';

export class NativeCoreBridge {
  static getStatus(): NativeCoreStatus {
    if (!nativeCore) {
      return {
        available: false,
        running: false,
        runtimeAbi: 0,
        message: '原生内核加载失败'
      };
    }
    return nativeCore.getStatus();
  }

  static isAvailable(): boolean {
    return NativeCoreBridge.getStatus().available;
  }

  static start(config: string, workDir: string, tunFd: number): NativeCoreStatus {
    return nativeCore.start(config, workDir, tunFd);
  }

  static stop(): NativeCoreStatus {
    return nativeCore.stop();
  }

  static probeCompatibilityCore(): boolean {
    return nativeCore.probeCompatibilityCore();
  }

  static getCompatibilityCoreStatus(): string {
    return nativeCore.getCompatibilityCoreStatus();
  }

  static getTrafficStats(): TrafficStats {
    return nativeCore.getTrafficStats();
  }
}
