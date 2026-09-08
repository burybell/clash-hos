export interface NativeCoreStatus {
  available: boolean;
  running: boolean;
  runtimeAbi: number;
  message: string;
}

export interface NativeTrafficStats {
  uploadBytes: number;
  downloadBytes: number;
  activeConnections: number;
}

export const getStatus: () => NativeCoreStatus;
export const start: (config: string, workDir: string, tunFd: number) => NativeCoreStatus;
export const stop: () => NativeCoreStatus;
export const probeCompatibilityCore: () => boolean;
export const getCompatibilityCoreStatus: () => string;
export const getTrafficStats: () => NativeTrafficStats;
